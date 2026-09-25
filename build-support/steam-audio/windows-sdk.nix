{ pkgs }:
let
  sdk = pkgs.fetchzip {
    url = "https://github.com/ValveSoftware/steam-audio/releases/download/v4.8.1/steamaudio_4.8.1.zip";
    sha256 = "1h34kngcxrzcbzrabfbnaa3qr0hrm1m72snj1pc7xc7lzsqd0nkd";
  };
in pkgs.runCommand "steam-audio-windows-runtime-4.8.1" { } ''
  mkdir -p "$out/bin" "$out/share/licenses/steam-audio-sdk"
  cp ${sdk}/lib/windows-x64/phonon.dll "$out/bin/"
  cp ${sdk}/lib/windows-x64/TrueAudioNext.dll "$out/bin/"
  cp ${sdk}/lib/windows-x64/GPUUtilities.dll "$out/bin/"
  cp ${sdk}/lib/windows-x64/phonon.lib "$out/bin/"
  cp ${./STEAM_AUDIO_SDK_LICENSE.md} "$out/share/licenses/steam-audio-sdk/LICENSE.md"
  cp ${sdk}/THIRDPARTY.md "$out/share/licenses/steam-audio-sdk/THIRDPARTY.md"
''
