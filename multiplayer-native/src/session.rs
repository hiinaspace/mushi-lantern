use anyhow::{bail, Context, Result};
use godot::prelude::*;
use godot_network_audio::{AudioStreamNetwork, NetworkAudioSender};
use iroh::{endpoint::{presets, Connection}, Endpoint, EndpointAddr, EndpointId, RelayUrl};
use iroh_base::TransportAddr;
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, sync::{Arc, RwLock, atomic::{AtomicBool, Ordering}}, time::{Duration, SystemTime, UNIX_EPOCH}};
use tokio::sync::mpsc;

const ALPN: &[u8] = b"mushi-lantern/game/1";
const MAX_PLAYERS: usize = 8;
const MAX_DGRAM: usize = 1100;
const LANTERN: u8 = 1;
const RELAY_LANTERN: u8 = 4;
const SNAPSHOT: u8 = 2;
const CONTROL: u8 = 3;
const VOICE: u8 = 5;
const RELAY_VOICE: u8 = 6;
const MAX_VOICE: usize = 1024;

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Address { id: String, relay: Option<String>, direct: Vec<String> }
impl Address {
    fn from_endpoint(endpoint: &Endpoint) -> Self {
        let mut result = Self { id: endpoint.id().to_string(), relay: None, direct: Vec::new() };
        for transport in &endpoint.addr().addrs {
            match transport { TransportAddr::Ip(ip) => result.direct.push(ip.to_string()), TransportAddr::Relay(url) => result.relay = Some(url.to_string()), _ => () }
        }
        result
    }
    fn parse(&self) -> Result<EndpointAddr> {
        let mut addr = EndpointAddr::new(self.id.parse::<EndpointId>()?);
        if let Some(url) = &self.relay { addr = addr.with_relay_url(url.parse::<RelayUrl>()?); }
        for ip in self.direct.iter().take(8) { addr = addr.with_ip_addr(ip.parse()?); }
        Ok(addr)
    }
}
#[derive(Serialize, Deserialize)]
struct ProofHello { protocol: u8, proof: [u8; 32], name: String }
#[derive(Serialize, Deserialize)]
struct LobbyRecord { protocol: u8, address: Address, expires: u64 }

enum Event { Ready(String, bool), Joined(String), Left(String), Lantern(String, Vec<u8>), Snapshot(String, Vec<u8>), Control(String, Vec<u8>), Voice(String, Vec<u8>), Error(String), Ended }
struct Peer { conn: Connection, writer: mpsc::Sender<Vec<u8>> }
struct Shared { peers: RwLock<HashMap<String, Peer>>, events: std::sync::mpsc::SyncSender<Event>, stopped: AtomicBool, host_id: RwLock<String>, local_id: RwLock<String>, is_host: bool }
impl Shared {
    fn emit(&self, event: Event) { let _ = self.events.try_send(event); }
    fn broadcast(&self, kind: u8, data: &[u8]) -> bool {
        if data.len() + 1 > MAX_DGRAM { return false; }
        let mut packet = Vec::with_capacity(data.len()+1); packet.push(kind); packet.extend_from_slice(data);
        for peer in self.peers.read().unwrap().values() { let _ = peer.conn.send_datagram(bytes::Bytes::copy_from_slice(&packet)); }
        true
    }
    fn send_lantern(&self, data: &[u8]) -> bool {
        if data.len()+1 > MAX_DGRAM { return false; }
        let packet = [vec![LANTERN], data.to_vec()].concat();
        if self.is_host { self.broadcast(LANTERN, data) } else {
            let peers = self.peers.read().unwrap();
            let host = self.host_id.read().unwrap();
            peers.get(&*host).is_some_and(|p| p.conn.send_datagram(bytes::Bytes::from(packet)).is_ok())
        }
    }
    fn send_control(&self, peer_id: Option<&str>, data: &[u8]) -> bool {
        if data.len() > 16 * 1024 { return false; }
        let peers = self.peers.read().unwrap();
        if let Some(id) = peer_id { peers.get(id).is_some_and(|p| p.writer.try_send([vec![CONTROL], data.to_vec()].concat()).is_ok()) }
        else { let mut ok = true; for peer in peers.values() { ok &= peer.writer.try_send([vec![CONTROL], data.to_vec()].concat()).is_ok(); } ok }
    }
    fn send_voice(&self, data: &[u8]) -> bool {
        if data.is_empty() || data.len() > MAX_VOICE { return false; }
        if self.is_host { return self.broadcast(VOICE, data); }
        let packet = [vec![VOICE], data.to_vec()].concat();
        let peers = self.peers.read().unwrap();
        let host = self.host_id.read().unwrap();
        peers.get(&*host).is_some_and(|p| p.conn.send_datagram(bytes::Bytes::from(packet)).is_ok())
    }
}

pub struct Handle { shared: Arc<Shared>, events: std::sync::mpsc::Receiver<Event>, worker: Option<std::thread::JoinHandle<()>> }
impl Handle {
    fn start(secret: [u8;32], name: String, host: bool, local_port: Option<u16>) -> Result<Self> {
        let (tx, events) = std::sync::mpsc::sync_channel(4096);
        let shared = Arc::new(Shared { peers: RwLock::new(HashMap::new()), events: tx, stopped: AtomicBool::new(false), host_id: RwLock::new(String::new()), local_id: RwLock::new(String::new()), is_host: host });
        let s = shared.clone();
        let worker = std::thread::Builder::new().name("mushi-network".into()).spawn(move || {
            let runtime = tokio::runtime::Builder::new_multi_thread().worker_threads(2).enable_all().build();
            match runtime { Ok(rt) => if let Err(e) = rt.block_on(run(s.clone(), secret, name, host, local_port)) { s.emit(Event::Error(format!("{e:#}"))); }, Err(e) => s.emit(Event::Error(e.to_string())) }
            s.emit(Event::Ended);
        })?;
        Ok(Self { shared, events, worker: Some(worker) })
    }
    fn stop(&self) { self.shared.stopped.store(true, Ordering::Release); }
}
impl Drop for Handle { fn drop(&mut self) { self.stop(); if let Some(worker) = self.worker.take() { let _ = worker.join(); } } }

#[derive(GodotClass)]
#[class(base=Node)]
pub struct MushiNetwork { base: Base<Node>, handle: Option<Handle>, local_id: GString, host: bool, peers: usize, voice_streams: HashMap<String, Gd<AudioStreamNetwork>>, voice_levels: HashMap<String, f32> }
#[godot_api]
impl INode for MushiNetwork {
    fn init(base: Base<Node>) -> Self { Self { base, handle: None, local_id: GString::new(), host: false, peers: 0, voice_streams: HashMap::new(), voice_levels: HashMap::new() } }
    fn process(&mut self, delta: f64) {
        let events: Vec<Event> = self.handle.as_ref().map(|h| h.events.try_iter().take(512).collect()).unwrap_or_default();
        for event in events { match event {
            Event::Ready(id, host) => { self.local_id = id.as_str().into(); self.host = host; let local_id = self.local_id.clone(); let _ = self.base_mut().emit_signal("session_ready", &[local_id.to_variant(), host.to_variant()]); }
            Event::Joined(id) => { self.peers += 1; self.voice_streams.insert(id.clone(), AudioStreamNetwork::new_gd()); self.base_mut().emit_signal("peer_joined", &[id.to_variant()]); }
            Event::Left(id) => { self.peers = self.peers.saturating_sub(1); self.voice_streams.remove(&id); self.voice_levels.remove(&id); self.base_mut().emit_signal("peer_left", &[id.to_variant()]); }
            Event::Lantern(id, bytes) => { let _ = self.base_mut().emit_signal("lantern_received", &[id.to_variant(), PackedByteArray::from(bytes.as_slice()).to_variant()]); }
            Event::Snapshot(id, bytes) => { let _ = self.base_mut().emit_signal("snapshot_chunk_received", &[id.to_variant(), PackedByteArray::from(bytes.as_slice()).to_variant()]); }
            Event::Control(id, bytes) => { let _ = self.base_mut().emit_signal("control_received", &[id.to_variant(), PackedByteArray::from(bytes.as_slice()).to_variant()]); }
            Event::Voice(id, bytes) => { if let Some(stream) = self.voice_streams.get_mut(&id) { let _=stream.call("push_packet", &[PackedByteArray::from(bytes.as_slice()).to_variant()]); } }
            Event::Error(message) => { let _ = self.base_mut().emit_signal("network_error", &[message.to_variant()]); }
            Event::Ended => { self.handle = None; self.peers = 0; self.voice_streams.clear(); self.voice_levels.clear(); self.local_id = GString::new(); self.base_mut().emit_signal("session_ended", &[]); }
        }}
        for (id,stream) in &self.voice_streams {
            let target=(stream.bind().output_rms()*5.0).clamp(0.0,1.0);
            let level=self.voice_levels.entry(id.clone()).or_default();
            let rate=if target>*level { 25.0 } else { 8.0 };
            *level += (target-*level)*(1.0-(-rate*delta.max(0.0) as f32).exp());
        }
    }
    fn exit_tree(&mut self) { self.handle = None; }
}
#[godot_api]
impl MushiNetwork {
    #[signal] fn session_ready(peer_id: GString, is_host: bool);
    #[signal] fn peer_joined(peer_id: GString);
    #[signal] fn peer_left(peer_id: GString);
    #[signal] fn lantern_received(peer_id: GString, bytes: PackedByteArray);
    #[signal] fn snapshot_chunk_received(peer_id: GString, bytes: PackedByteArray);
    #[signal] fn control_received(peer_id: GString, bytes: PackedByteArray);
    #[signal] fn network_error(message: GString);
    #[signal] fn session_ended();

    /// Start private session. Secret is a human-readable shared phrase; hosting publishes rendezvous, joining waits for it.
    #[func] fn start(&mut self, secret: GString, display_name: GString, hosting: bool) -> bool {
        if self.handle.is_some() { return false; }
        let phrase = secret.to_string().trim().to_owned();
        if phrase.chars().count() < 3 { self.base_mut().emit_signal("network_error", &["Room code must be at least 3 characters".to_variant()]); return false; }
        let key = blake3::derive_key("mushi-lantern shared room phrase v1", phrase.as_bytes());
        let local_port = match std::env::var("MUSHI_NETWORK_LOCAL_PORT") { Ok(value) => match value.parse::<u16>() { Ok(port) if port != 0 => Some(port), _ => { let _=self.base_mut().emit_signal("network_error", &["MUSHI_NETWORK_LOCAL_PORT must be a nonzero UDP port".to_variant()]); return false; } }, Err(_) => None };
        match Handle::start(key, display_name.to_string().chars().take(32).collect(), hosting, local_port) { Ok(h) => { self.handle = Some(h); true }, Err(e) => { self.base_mut().emit_signal("network_error", &[e.to_string().to_variant()]); false } }
    }
    #[func] fn stop(&mut self) {
        if let Some(h) = self.handle.take() { h.stop(); drop(h); }
        self.host = false;
        self.peers = 0;
        self.local_id = GString::new();
        self.voice_streams.clear();
        self.voice_levels.clear();
    }
    #[func] fn is_host(&self) -> bool { self.host }
    #[func] fn peer_count(&self) -> i64 { self.peers as i64 + if self.handle.is_some() { 1 } else { 0 } }
    #[func] fn send_lantern(&self, data: PackedByteArray) -> bool { self.handle.as_ref().is_some_and(|h| h.shared.send_lantern(data.as_slice())) }
    #[func] fn broadcast_snapshot_chunk(&self, data: PackedByteArray) -> bool { self.host && self.handle.as_ref().is_some_and(|h| h.shared.broadcast(SNAPSHOT, data.as_slice())) }
    #[func] fn send_control(&self, peer_id: GString, data: PackedByteArray) -> bool { self.handle.as_ref().is_some_and(|h| h.shared.send_control(Some(&peer_id.to_string()), data.as_slice())) }
    #[func] fn broadcast_control(&self, data: PackedByteArray) -> bool { self.handle.as_ref().is_some_and(|h| h.shared.send_control(None, data.as_slice())) }
    #[func] fn receive_voice_stream(&self, peer_id: GString) -> Option<Gd<AudioStreamNetwork>> { self.voice_streams.get(&peer_id.to_string()).cloned() }
    #[func] fn get_voice_level(&self, peer_id: GString) -> f32 { self.voice_levels.get(&peer_id.to_string()).copied().unwrap_or_default() }
    #[func] fn attach_voice_sender(&self, mut sender: Gd<NetworkAudioSender>) -> bool {
        let Some(handle) = &self.handle else { return false; };
        let shared = Arc::downgrade(&handle.shared);
        sender.bind_mut().install_direct_send_handler(Arc::new(move |data| {
            if let Some(shared) = shared.upgrade() { shared.send_voice(&data); }
        }));
        true
    }
}

fn now_secs() -> u64 { SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs() }
fn proof(conn: &Connection, secret: &[u8;32]) -> Result<[u8;32]> { let mut material = [0;32]; conn.export_keying_material(&mut material, b"mushi-lantern-auth-v1", b"").map_err(|_| anyhow::anyhow!("TLS exporter failed"))?; Ok(*blake3::keyed_hash(secret, &material).as_bytes()) }
async fn write_hello(send: &mut iroh::endpoint::SendStream, hello: &ProofHello) -> Result<()> { let data = serde_json::to_vec(hello)?; send.write_all(&(data.len() as u32).to_be_bytes()).await?; send.write_all(&data).await?; Ok(()) }
async fn read_hello(recv: &mut iroh::endpoint::RecvStream) -> Result<ProofHello> { let mut size=[0;4]; recv.read_exact(&mut size).await?; let n=u32::from_be_bytes(size) as usize; if n>4096 { bail!("hello too large"); } let mut b=vec![0;n]; recv.read_exact(&mut b).await?; Ok(serde_json::from_slice(&b)?) }
async fn admit(conn: Connection, state: Arc<Shared>, secret: [u8;32], outgoing: bool, name: String) -> Result<()> {
    let expected=proof(&conn,&secret)?;
    let (mut send,mut recv)=if outgoing { conn.open_bi().await? } else { conn.accept_bi().await? };
    let remote=if outgoing { write_hello(&mut send,&ProofHello{protocol:1,proof:expected,name}).await?; read_hello(&mut recv).await? } else { let r=read_hello(&mut recv).await?; write_hello(&mut send,&ProofHello{protocol:1,proof:expected,name}).await?; r };
    if remote.protocol!=1 || remote.proof!=expected { conn.close(1u8.into(),b"wrong room"); bail!("room authentication failed"); }
    let id=conn.remote_id().to_string();
    let (tx,mut rx)=mpsc::channel::<Vec<u8>>(128);
    { let mut peers=state.peers.write().unwrap(); if peers.contains_key(&id)||peers.len()+1>=MAX_PLAYERS { conn.close(2u8.into(),b"room full"); bail!("room full"); } peers.insert(id.clone(),Peer{conn:conn.clone(),writer:tx}); }
    if state.is_host { *state.host_id.write().unwrap()=state.local_id.read().unwrap().clone(); } else { *state.host_id.write().unwrap()=id.clone(); }
    state.emit(Event::Joined(id.clone()));
    tokio::spawn(async move { while let Some(b)=rx.recv().await { if b.len()>16*1024+1 { continue; } if send.write_all(&(b.len() as u32).to_be_bytes()).await.is_err() || send.write_all(&b).await.is_err() { break; } } });
    let rs=state.clone(); let rid=id.clone();
    tokio::spawn(async move { loop { let mut size=[0;4]; if recv.read_exact(&mut size).await.is_err() { break; } let n=u32::from_be_bytes(size) as usize; if n==0||n>16*1024+1 { break; } let mut b=vec![0;n]; if recv.read_exact(&mut b).await.is_err() { break; } if b[0]==CONTROL { rs.emit(Event::Control(rid.clone(),b[1..].to_vec())); } } });
    let s=state.clone(); let c=conn.clone();
    tokio::spawn(async move {
        while let Ok(packet)=conn.read_datagram().await {
            if packet.is_empty()||packet.len()>MAX_DGRAM {continue;}
            match packet[0] {
                LANTERN=>{
                    if s.is_host {
                        let peers=s.peers.read().unwrap();
                        let id_bytes = id.as_bytes();
                        if id_bytes.len() <= u8::MAX as usize && packet.len() + id_bytes.len() + 1 <= MAX_DGRAM {
                            let mut relay = Vec::with_capacity(packet.len() + id_bytes.len() + 1);
                            relay.push(RELAY_LANTERN);
                            relay.push(id_bytes.len() as u8);
                            relay.extend_from_slice(id_bytes);
                            relay.extend_from_slice(&packet[1..]);
                            for (peer_id,peer) in peers.iter() { if peer_id!=&id { let _=peer.conn.send_datagram(bytes::Bytes::copy_from_slice(&relay)); } }
                        }
                    }
                    s.emit(Event::Lantern(id.clone(),packet[1..].to_vec()));
                },
                RELAY_LANTERN if !s.is_host => {
                    let id_len = packet.get(1).copied().unwrap_or_default() as usize;
                    if id_len == 0 || packet.len() < 2 + id_len { continue; }
                    if let Ok(origin) = std::str::from_utf8(&packet[2..2 + id_len]) {
                        s.emit(Event::Lantern(origin.to_owned(), packet[2 + id_len..].to_vec()));
                    }
                },
                VOICE => {
                    if s.is_host {
                        let peers=s.peers.read().unwrap();
                        let id_bytes=id.as_bytes();
                        if id_bytes.len() <= u8::MAX as usize && packet.len()+id_bytes.len()+1 <= MAX_DGRAM {
                            let mut relay=Vec::with_capacity(packet.len()+id_bytes.len()+1);
                            relay.push(RELAY_VOICE);
                            relay.push(id_bytes.len() as u8);
                            relay.extend_from_slice(id_bytes);
                            relay.extend_from_slice(&packet[1..]);
                            for (peer_id,peer) in peers.iter() { if peer_id != &id { let _=peer.conn.send_datagram(bytes::Bytes::copy_from_slice(&relay)); } }
                        }
                    }
                    s.emit(Event::Voice(id.clone(),packet[1..].to_vec()));
                },
                RELAY_VOICE if !s.is_host => {
                    let id_len=packet.get(1).copied().unwrap_or_default() as usize;
                    if id_len == 0 || packet.len() < 2+id_len { continue; }
                    if let Ok(origin)=std::str::from_utf8(&packet[2..2+id_len]) {
                        s.emit(Event::Voice(origin.to_owned(),packet[2+id_len..].to_vec()));
                    }
                },
                SNAPSHOT=>s.emit(Event::Snapshot(id.clone(),packet[1..].to_vec())), _=>()
            }
        }
        s.peers.write().unwrap().remove(&id);
        if !s.is_host && *s.host_id.read().unwrap()==id {
            s.emit(Event::Error("Host disconnected; this session has ended".into()));
            s.stopped.store(true,Ordering::Release);
        }
        s.emit(Event::Left(id)); let _=c.close(0u8.into(),b"closed");
    });
    Ok(())
}
fn local_record_path(port: u16, secret: &[u8;32]) -> std::path::PathBuf {
    let short = &blake3::hash(secret).to_hex()[..16];
    std::env::temp_dir().join(format!("mushi-lantern-{port}-{short}.json"))
}
async fn run(state: Arc<Shared>, secret: [u8;32], name: String, hosting: bool, local_port: Option<u16>) -> Result<()> {
    let endpoint=if local_port.is_some() { Endpoint::builder(presets::Minimal).alpns(vec![ALPN.to_vec()]).bind().await? } else { Endpoint::builder(presets::N0).alpns(vec![ALPN.to_vec()]).bind().await? };
    let local=endpoint.id().to_string(); *state.local_id.write().unwrap()=local.clone();
    state.emit(Event::Ready(local,hosting));
    let key=blake3::derive_key("mushi-lantern pkarr discovery v1",&secret);
    let client=if local_port.is_some() { None } else { Some(pkarr::Client::builder().no_relays().build()?) };
    if hosting { *state.host_id.write().unwrap()=endpoint.id().to_string(); }
    if let Some(port)=local_port {
        let path=local_record_path(port,&secret);
        if hosting {
            let mut addr=Address::from_endpoint(&endpoint); addr.direct.truncate(8);
            let record=LobbyRecord{protocol:1,address:addr,expires:now_secs()+3600};
            let json=serde_json::to_vec(&record)?;
            let temp=path.with_extension(format!("{}.tmp",std::process::id()));
            std::fs::write(&temp,&json).context("writing localhost rendezvous file")?;
            #[cfg(unix)] { use std::os::unix::fs::PermissionsExt; std::fs::set_permissions(&temp,std::fs::Permissions::from_mode(0o600))?; }
            std::fs::rename(&temp,&path).context("publishing localhost rendezvous file")?;
        } else {
            let deadline=tokio::time::Instant::now()+Duration::from_secs(90);
            loop {
                if state.stopped.load(Ordering::Acquire)||tokio::time::Instant::now()>deadline { break; }
                if let Ok(bytes)=std::fs::read(&path) {
                    if let Ok(record)=serde_json::from_slice::<LobbyRecord>(&bytes) {
                        if record.protocol==1&&record.expires>now_secs()&&record.address.id!=endpoint.id().to_string() {
                            let conn=endpoint.connect(record.address.parse()?,ALPN).await?;
                            admit(conn,state.clone(),secret,true,name.clone()).await?;
                            break;
                        }
                    }
                }
                tokio::time::sleep(Duration::from_millis(250)).await;
            }
        }
    }
    if let Some(client)=client.as_ref() {
        let kp=pkarr::Keypair::from_secret_key(&key);
        if hosting {
            let publish_client=client.clone(); let publish_endpoint=endpoint.clone();
            tokio::spawn(async move { loop {
                let mut addr=Address::from_endpoint(&publish_endpoint); addr.direct.truncate(4);
                if let Ok(json)=serde_json::to_string(&LobbyRecord{protocol:1,address:addr,expires:now_secs()+90}) {
                    if let Ok(packet)=pkarr::SignedPacket::builder().txt(".".try_into().unwrap(),json.as_str().try_into().unwrap(),30).sign(&kp) { let _=publish_client.publish(&packet,None).await; }
                }
                tokio::time::sleep(Duration::from_secs(25)).await;
            } });
        } else {
            let deadline=tokio::time::Instant::now()+Duration::from_secs(300);
            loop {
                if state.stopped.load(Ordering::Acquire)||tokio::time::Instant::now()>deadline { break; }
                if let Ok(Some(packet))=tokio::time::timeout(Duration::from_secs(8),client.resolve_most_recent(&kp.public_key())).await {
                    for rr in packet.all_resource_records() { if let pkarr::dns::rdata::RData::TXT(txt)=&rr.rdata { let raw: String = txt.clone().try_into().context("invalid lobby TXT")?; if let Ok(record)=serde_json::from_str::<LobbyRecord>(&raw) { if record.protocol==1&&record.expires>now_secs()&&record.address.id!=endpoint.id().to_string() { let conn=endpoint.connect(record.address.parse()?,ALPN).await?; admit(conn,state.clone(),secret,true,name.clone()).await?; break; } } } }
                    if !state.peers.read().unwrap().is_empty() { break; }
                }
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }
    }
    loop {
        tokio::select! { incoming=endpoint.accept()=>{ if let Some(incoming)=incoming { let s=state.clone(); let sec=secret; let n=name.clone(); tokio::spawn(async move { if let Ok(Ok(conn))=tokio::time::timeout(Duration::from_secs(8),incoming).await { let _=admit(conn,s,sec,false,n).await; } }); } }, _=tokio::time::sleep(Duration::from_millis(40))=>if state.stopped.load(Ordering::Acquire){break;} }
    }
    let _=tokio::time::timeout(Duration::from_secs(2),endpoint.close()).await;
    if hosting { if let Some(port)=local_port { let path=local_record_path(port,&secret); let _=std::fs::remove_file(path); } }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn make_shared(host: bool) -> (Arc<Shared>, std::sync::mpsc::Receiver<Event>) {
        let (tx, rx) = std::sync::mpsc::sync_channel(128);
        (Arc::new(Shared { peers: RwLock::new(HashMap::new()), events: tx, stopped: AtomicBool::new(false), host_id: RwLock::new(String::new()), local_id: RwLock::new(String::new()), is_host: host }), rx)
    }
    #[test]
    fn localhost_routes_unreliable_lantern_snapshot_and_reliable_control_then_leave() {
        let rt = tokio::runtime::Builder::new_multi_thread().worker_threads(2).enable_all().build().unwrap();
        rt.block_on(async {
            let host_ep = Endpoint::builder(presets::Minimal).alpns(vec![ALPN.to_vec()]).bind().await.unwrap();
            let client_ep = Endpoint::builder(presets::Minimal).alpns(vec![ALPN.to_vec()]).bind().await.unwrap();
            let (host, host_events) = make_shared(true); let (client, client_events) = make_shared(false);
            *host.local_id.write().unwrap() = host_ep.id().to_string();
            *client.local_id.write().unwrap() = client_ep.id().to_string();
            let accept_state = host.clone(); let accept_ep=host_ep.clone();
            let accept_task = tokio::spawn(async move { let incoming = accept_ep.accept().await.unwrap(); let conn = incoming.await.unwrap(); admit(conn, accept_state, [11;32], false, "Host".into()).await.unwrap(); });
            let conn = client_ep.connect(host_ep.addr(), ALPN).await.unwrap();
            admit(conn, client.clone(), [11;32], true, "Guest".into()).await.unwrap();
            accept_task.await.unwrap();
            *client.host_id.write().unwrap() = host_ep.id().to_string();
            assert!(client.send_lantern(b"lamp"));
            assert!(host.broadcast(SNAPSHOT, b"chunk-0"));
            assert!(host.send_control(None, b"reset-state"));
            let deadline=tokio::time::Instant::now()+Duration::from_secs(5);
            let mut got_lantern=false; let mut got_snapshot=false; let mut got_control=false;
            loop {
                for event in host_events.try_iter() { if let Event::Lantern(_,b)=event { got_lantern=b==b"lamp"; } }
                for event in client_events.try_iter() { match event { Event::Snapshot(_,b)=>got_snapshot=b==b"chunk-0", Event::Control(_,b)=>got_control=b==b"reset-state", _=>() } }
                if got_lantern&&got_snapshot&&got_control { break; }
                assert!(tokio::time::Instant::now()<deadline,"timed out: lantern={got_lantern} snapshot={got_snapshot} control={got_control}");
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
            client_ep.close().await;
            host_ep.close().await;
        });
    }

    #[test]
    fn relayed_lantern_preserves_origin_across_three_peers() {
        let rt = tokio::runtime::Builder::new_multi_thread().worker_threads(2).enable_all().build().unwrap();
        rt.block_on(async {
            let host_ep = Endpoint::builder(presets::Minimal).alpns(vec![ALPN.to_vec()]).bind().await.unwrap();
            let first_ep = Endpoint::builder(presets::Minimal).alpns(vec![ALPN.to_vec()]).bind().await.unwrap();
            let second_ep = Endpoint::builder(presets::Minimal).alpns(vec![ALPN.to_vec()]).bind().await.unwrap();
            let (host, _) = make_shared(true);
            let (first, _) = make_shared(false);
            let (second, second_events) = make_shared(false);
            *host.local_id.write().unwrap() = host_ep.id().to_string();
            *first.local_id.write().unwrap() = first_ep.id().to_string();
            *second.local_id.write().unwrap() = second_ep.id().to_string();
            let accept_host = host.clone(); let accept_ep = host_ep.clone();
            let accept_task = tokio::spawn(async move {
                for _ in 0..2 {
                    let incoming = accept_ep.accept().await.unwrap();
                    admit(incoming.await.unwrap(), accept_host.clone(), [19; 32], false, "Host".into()).await.unwrap();
                }
            });
            let first_conn = first_ep.connect(host_ep.addr(), ALPN).await.unwrap();
            admit(first_conn, first.clone(), [19; 32], true, "First".into()).await.unwrap();
            *first.host_id.write().unwrap() = host_ep.id().to_string();
            let second_conn = second_ep.connect(host_ep.addr(), ALPN).await.unwrap();
            admit(second_conn, second.clone(), [19; 32], true, "Second".into()).await.unwrap();
            *second.host_id.write().unwrap() = host_ep.id().to_string();
            accept_task.await.unwrap();
            let lantern = [42u8; 32];
            assert!(first.send_lantern(&lantern));
            let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
            loop {
                if second_events.try_iter().any(|event| matches!(event, Event::Lantern(id, bytes) if id == first_ep.id().to_string() && bytes == lantern)) { break; }
                assert!(tokio::time::Instant::now() < deadline, "relayed lantern did not retain first peer identity");
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
            let voice = [7u8; 100];
            assert!(first.send_voice(&voice));
            let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
            loop {
                if second_events.try_iter().any(|event| matches!(event, Event::Voice(id, bytes) if id == first_ep.id().to_string() && bytes == voice)) { break; }
                assert!(tokio::time::Instant::now() < deadline, "relayed voice did not retain first peer identity");
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
            host_ep.close().await;
            first_ep.close().await;
            second_ep.close().await;
        });
    }

    #[test]
    fn localhost_eight_player_capacity_and_lantern_relay() {
        let rt = tokio::runtime::Builder::new_multi_thread().worker_threads(4).enable_all().build().unwrap();
        rt.block_on(async {
            let host_ep = Endpoint::builder(presets::Minimal).alpns(vec![ALPN.to_vec()]).bind().await.unwrap();
            let (host, _) = make_shared(true);
            *host.local_id.write().unwrap() = host_ep.id().to_string();
            let accept_host = host.clone();
            let accept_ep = host_ep.clone();
            let accept_task = tokio::spawn(async move {
                let mut accepted = Vec::new();
                for _ in 0..8 {
                    let incoming = accept_ep.accept().await.unwrap();
                    let conn = incoming.await.unwrap();
                    accepted.push(admit(conn, accept_host.clone(), [23; 32], false, "Host".into()).await.is_ok());
                }
                accepted
            });

            let mut client_endpoints = Vec::new();
            let mut client_states = Vec::new();
            let mut client_events = Vec::new();
            for index in 0..8 {
                let endpoint = Endpoint::builder(presets::Minimal).alpns(vec![ALPN.to_vec()]).bind().await.unwrap();
                let (client, events) = make_shared(false);
                *client.local_id.write().unwrap() = endpoint.id().to_string();
                let conn = endpoint.connect(host_ep.addr(), ALPN).await.unwrap();
                // The ninth participant may finish its local handshake before the
                // host's capacity check closes it. Capacity is asserted on the host.
                let _ = admit(conn, client.clone(), [23; 32], true, format!("Guest {index}")).await;
                *client.host_id.write().unwrap() = host_ep.id().to_string();
                client_endpoints.push(endpoint);
                client_states.push(client);
                client_events.push(events);
            }
            let accepted = accept_task.await.unwrap();
            assert_eq!(&accepted[..7], &[true; 7], "host should admit seven remote peers");
            assert!(!accepted[7], "host should reject a ninth participant");
            assert_eq!(host.peers.read().unwrap().len(), 7, "host capacity is eight participants including itself");

            assert!(client_states[0].send_lantern(b"eight-peer-lantern"));
            let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
            let mut received = [false; 8];
            loop {
                for (index, events) in client_events.iter().enumerate().skip(1) {
                    if events.try_iter().any(|event| matches!(event,
                        Event::Lantern(id, bytes) if id == client_endpoints[0].id().to_string() && bytes == b"eight-peer-lantern")) {
                        received[index] = true;
                    }
                }
                if received[1..7].iter().all(|value| *value) { break; }
                assert!(tokio::time::Instant::now() < deadline, "lantern did not reach all admitted peers: {received:?}");
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
            assert!(!received[7], "rejected ninth participant must not receive relayed lantern traffic");

            host_ep.close().await;
            for endpoint in client_endpoints { endpoint.close().await; }
        });
    }
}
