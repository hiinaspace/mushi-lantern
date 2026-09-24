# Mushi call reference: glass harp

The user chose the 1:26–1:33 passage of BeeProductive's
[Glass Harp.wav](https://freesound.org/people/BeeProductive/sounds/382286/) as a
timbre and interval reference. Freesound marks the recording CC0. The
downloaded source is stereo 48 kHz, 24-bit PCM, 95.795 seconds long, with
SHA-256 `ee8d179e50e99a9ea5ea042061deb04229dcfa89e44351c5fe60d104b319dc94`.
The recording itself is not a committed game asset. A local comparison crop
can be made with:

```sh
mkdir -p .local/audio-auditions-reference
ffmpeg -ss 86 -t 7 -i ~/Downloads/382286__beeproductive__glass-harp.wav \
  -ac 1 -ar 48000 .local/audio-auditions-reference/beeproductive_86-93s.wav
```

Measurements from the downloaded passage:

| Feature | Observation |
| --- | --- |
| Main pitches | Roughly 650 and 986 Hz; a fifth about 18–22 cents wider than a 3:2 ratio |
| Balance | Upper note has about 13 dB stronger spectral peak in the analyzed window |
| Motion | Each pitch wanders by only a few hertz; envelopes pulse near 2.9 Hz and often swell in alternation |
| Harmonics | Secondary peaks are weak, roughly 35–50 dB below their fundamentals |
| Edges | The full phrase enters near 84.3 seconds and releases near 93.5 seconds |

The apparent 1–2 Hz spectral line width includes drift and amplitude motion;
it is not a measured physical resonance Q. This passage suggests two near-sine
voices with very faint overtones and irregular rubbing pulses. It does not
imply that every mushi should play the same two exact pitches or reproduce the
source recording's incidental noise.

`python3 scripts/generate_reference_fifth.py` writes three original mono
auditions under `.local/audio-auditions-reference-synth/`: `close` follows the
measured pitch pair and balance, `living` lets the notes move a little more,
and `staggered` starts the upper note later. Each uses small pitch drift,
alternating ~2.9 Hz rubbing pulses, weaker slow swells, and faint second or
third harmonics. None has replaced the current in-game mushi call pending ear
review.
