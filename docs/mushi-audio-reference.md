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

A follow-up comparison found that the reference carries more quiet upper
energy than the first two-tone reconstruction. In matching analysis windows,
the 5–10 kHz band was about −40 dB relative to the 550–1100 Hz fundamentals
in the reference, versus about −88 dB in the reconstruction. Much of the
reference's 3–5 kHz content clusters near the upper voice's second through
fifth harmonics (~1.97, 2.95, 3.94, and 4.93 kHz). There is also a mobile
6.50–6.54 kHz cluster, even while the lower note stays near 650 Hz. That
cluster could include a separate glass resonance or another untuned sound;
the recording alone does not identify its cause. A quiet, detuned bright layer
is a synthesis hypothesis, while a full-volume saw or square would add much
stronger low harmonics than the recording shows. The intended in-game harmony
palette stays mostly fourths and fifths, without thirds.

`python3 scripts/generate_reference_fifth.py` writes three original mono
auditions under `.local/audio-auditions-reference-synth/`: `close` follows the
measured pitch pair and balance, `living` lets the notes move a little more,
and `staggered` starts the upper note later. Each uses small pitch drift,
alternating ~2.9 Hz rubbing pulses, weaker slow swells, and faint second or
third harmonics.

`python3 scripts/generate_reference_fifth.py --bright` writes another three
auditions under `.local/audio-auditions-bright/`. `etched` adds faint upper
partials and moving high resonances near the reference's measured bands;
`reese` adds a little detuned beating; `friction` raises the contact noise.
The 5–10 kHz energy in all three is roughly 41 dB below the fundamental band,
close to the reference's roughly 40 dB. This matches one spectral measure,
not perceived timbre or a verified account of the recording's production.
The CLI also supports `--interval fourth|fifth` and `--root-hz` for auditions.

After comparing the three auditions, the user chose the brighter contact
texture. The game generator now uses `friction` for all four calls, with two
near fourths and two near fifths. The detuned `reese` version remains an
audition only. Sparse playback and small per-play pitch changes remain; the
spatialized result and category mix still need ear review.
