# Audio sample audition shortlist

Listening shortlist from the first sound pass. The six chosen recordings are
now included as edited mono game assets and listed in [Credits](../CREDITS.md);
other links remain candidates. Each linked Freesound page was marked CC0 when
checked on 2026-09-23. Recheck a page before using another clip, and listen
to the downloaded source rather than judging from preview compression.

## Mushi synthesis audition

`python3 scripts/generate_mushi_audio.py` renders three deterministic mono
48 kHz calls to `/tmp/mushi-lantern-audio-audition` by default: `hollow`
(moderate resonant breath), `airy` (wider, noisier bands), and `glassy`
(narrower resonances). They use independent white-noise exciters through
several bandpass filters at a root, fifth, octave, and higher harmonics. Each
band drifts slowly in center frequency and Q. A second audition raises and
narrows the glassy partials to roughly 500–3000 Hz. These are audition files,
not yet game assets; choosing the final timbre by ear comes next.

## Forest ambience

| Recording | Listen for |
| --- | --- |
| [Clark's Tower Ambience 1 RX — greysound](https://freesound.org/people/greysound/sounds/547923/) | Long forest bed; a faint distant backup alarm may be audible. |
| [Forest Ambience — guidofm](https://freesound.org/people/guidofm/sounds/509176/) | Short forest field recording. |
| [Forest Ambience, Chiang Mai — marc.om](https://freesound.org/people/marc.om/sounds/804709/) | Long insects, birds, and leaves; low-bitrate source. |

For localized night insect beds, also audition
[Night Crickets Ambience on Rural Property — OwlStorm](https://freesound.org/people/OwlStorm/sounds/320145/)
and [crickets with two close cicadas — kyles](https://freesound.org/people/kyles/sounds/453862/).
Both pages are marked CC0. The latter may offer distinct chirps to cut into
separate mono sources rather than a full ambient loop.

## Leaf and brush footsteps

| Recording | Listen for |
| --- | --- |
| [Footsteps / Walking on foliage in a forest — Dominik_W](https://freesound.org/people/Dominik_W/sounds/398685/) | Mixed leaf and foliage steps. |
| [Footsteps on dry leaves — eqavox](https://freesound.org/people/eqavox/sounds/683958/) | Sharper dry-leaf crunch. |
| [Crunchy Footsteps On Leaves — lolamadeus](https://freesound.org/people/lolamadeus/sounds/179339/) | Short alternative dry-leaf sequence. |

## Lantern flame

| Recording | Listen for |
| --- | --- |
| [torch.wav — jiaying330](https://freesound.org/people/jiaying330/sounds/634775/) | Small torch/fire texture. |
| [fire_crackling.wav — ceich93](https://freesound.org/people/ceich93/sounds/263864/) | Longer crackle; possibly too large for a lantern. |
| [Wooden Wick Candle Crackle 1 — deadrobotmusic](https://freesound.org/people/deadrobotmusic/sounds/622854/) | Subtle wick texture. |

## Metal and shutters

| Recording | Listen for |
| --- | --- |
| [metal shutter.wav — bruno.auzet](https://freesound.org/people/bruno.auzet/sounds/524695/) | Direct metal shutter movement. |
| [Metallic door - Open & close — Vrymaa](https://freesound.org/people/Vrymaa/sounds/734930/) | Iron door movement for smaller mechanical edits. |
| [creaky door hinge.wav — chonkdonk](https://freesound.org/people/chonkdonk/sounds/619819/) | Metal creak layer for swing or shutter. |

Licenses on recording pages are a starting point. Attribution is not required
for CC0, but retain creator and page URL in asset provenance if selected. The
actual recorded content should also be checked by ear for voices, alarms, or
other unwanted identifiable sounds.
