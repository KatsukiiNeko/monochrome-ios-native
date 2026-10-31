# Equalizer research notes

Reference material for the in-app equalizer. Values marked **[Fact]** come from
the cited source; **[Rec]** are engineering choices; **[Data]** are reproducible
values computed from the formulas below.

## Signal path and platform limits

- **[Fact]** `AVPlayerItem.audioMix` is supported only for file-based media and
  **not** for HTTP Live Streaming. Apple documentation:
  <https://developer.apple.com/documentation/avfoundation/avplayeritem/audiomix>
- **[Fact]** `MTAudioProcessingTap` is unavailable for HLS; there is no
  supported way to process HLS audio. Apple forums:
  <https://developer.apple.com/forums/thread/45966>,
  <https://developer.apple.com/forums/thread/758341>
- **[Fact]** The tap receives whatever processing format AVFoundation chooses;
  read the sample rate, channel count and interleaving in `prepare`:
  <https://developer.apple.com/forums/thread/30383>
- The app's catalog source is a single progressive file per track, which counts
  as file-based. Device verification is still required; see the open questions.
- **Decision tree:** tap runs on progressive remote items → ship as designed;
  only on local items → stage the stream through the cache before playing and
  say "Preparing for EQ"; never runs → do not ship a working-looking toggle.

### Real-time rules for `process`

No allocation, blocking locks, logging, Swift array growth, Objective-C
messaging, actors or `async` inside the tap. Allocate in `prepare`; free in
`unprepare`. Keep per-channel state; apply the same curve to every channel;
compute coefficients for the reported sample rate and clamp the center to
`0.45 × sampleRate`. Publish parameter changes as an immutable snapshot and
crossfade; never wait for a lock. Flush denormals.

## Filter math (W3C Audio EQ Cookbook)

Source: <https://www.w3.org/TR/audio-eq-cookbook/>

```
H(z) = (b0 + b1 z^-1 + b2 z^-2) / (a0 + a1 z^-1 + a2 z^-2)
A     = 10^(dBgain / 40)
w0    = 2*pi*f0 / Fs
alpha = sin(w0) / (2*Q)
```

| Type | b0 | b1 | b2 | a0 | a1 | a2 |
|---|---|---|---|---|---|---|
| LPF | (1-cw)/2 | 1-cw | (1-cw)/2 | 1+alpha | -2cw | 1-alpha |
| HPF | (1+cw)/2 | -(1+cw) | (1+cw)/2 | 1+alpha | -2cw | 1-alpha |
| Notch | 1 | -2cw | 1 | 1+alpha | -2cw | 1-alpha |
| Peak | 1+alpha*A | -2cw | 1-alpha*A | 1+alpha/A | -2cw | 1-alpha/A |

With `t = 2*sqrt(A)*alpha`:

```
lowShelf:  b0 =  A*((A+1) - (A-1)*cw + t)   a0 = (A+1) + (A-1)*cw + t
           b1 =  2*A*((A-1) - (A+1)*cw)     a1 = -2*((A-1) + (A+1)*cw)
           b2 =  A*((A+1) - (A-1)*cw - t)   a2 = (A+1) + (A-1)*cw - t

highShelf: b0 =  A*((A+1) + (A-1)*cw + t)   a0 = (A+1) - (A-1)*cw + t
           b1 = -2*A*((A-1) + (A+1)*cw)     a1 =  2*((A-1) - (A+1)*cw)
           b2 =  A*((A+1) + (A-1)*cw - t)   a2 = (A+1) - (A-1)*cw - t
```

Properties used as tests: a peak has exactly its gain at `f0`; a boost and an
equal cut cancel to 1e-9 dB; shelves sit at half gain at their corner; a
second-order high-pass at `Q = 0.7071` is −3.01 dB at `f0`; a normalized
section is stable when `|a2| < 1` and `|a1| < 1 + a2`.

## Bands, preamp and dynamics

- Graphic bands: 31.5, 63, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz, Q 1.414.
- Parametric ranges: frequency 20 Hz–20 kHz, gain ±15 dB, Q 0.1–10, 16 bands.
- Adjacent graphic bands overlap: ten bands at +6 dB peak at **+8.83 dB**, so
  the preamp is computed from the composite curve, not the largest slider.
- Auto preamp: `-max(0, peak)` of the composite response, rounded up to 0.1 dB.
- Dynamic Boost: make-up gain 0–6 dB into a peak limiter at −1 dBFS,
  instantaneous attack, ~100 ms release.
- Stereo width: `M = (L+R)/2`, `S = (L-R)/2*w`, `L' = M+S`, `R' = M-S`,
  `w ∈ [0, 2]`; `w = 1` is identity.
- Effects are ordinary filters so the curve and preamp include them:
  Bass = low shelf 100 Hz; Clarity = high shelf 6 kHz plus a small 3 kHz peak.

## Preset provenance

- Built-in **Monochrome** presets are original parametric shapes, kept
  conservative (largest boost +6 dB). They are starting points, not
  listening-tuned corrections.
- **Classic** presets are the Winamp-lineage ten-band values resampled to the
  ISO centers by log-frequency interpolation, attributed as
  "classic presets (Winamp lineage)".
- Headphone correction is import-only. The app never bundles or fetches the
  AutoEQ database; its data licensing is unclear.

## Import / export format

```
Preamp: -6.4 dB
Filter 1: ON LS Fc 105 Hz Gain 3.8 dB Q 0.70
Filter 2: ON PK Fc 127 Hz Gain -2.4 dB Q 0.70
Filter 3: ON HS Fc 10000 Hz Gain -3.6 dB Q 0.70
```

Accepted types: `PK`, `LS`/`LSC`, `HS`/`HSC`. Shelves may use `S <slope>`
instead of `Q`; convert with `1/Q = sqrt((A + 1/A)*(1/S - 1) + 2)`. Unknown
lines are reported in the import summary, values are clamped, and filters
beyond the supported count are truncated.

## Golden vectors (Fs = 48 kHz, normalized)

| Filter | b0, b1, b2, a1, a2 |
|---|---|
| PK 1000 +6 Q1 | 1.0439530870, -1.8953207239, 0.8677222848, -1.8953207239, 0.9116753718 |
| PK 100 −4 Q2 | 0.9984858904, -1.9916237506, 0.9933085020, -1.9916237506, 0.9917943924 |
| LS 105 +4 Q0.7071 | 1.0022452513, -1.9826329111, 0.9806234402, -1.9826764176, 0.9828251850 |
| HS 8000 +6 Q0.7071 | 1.5716695819, -1.2488751659, 0.4486846379, -0.4335084890, 0.2049875429 |
| HP 80 Q0.7071 | 0.9926224728, -1.9852449456, 0.9926224728, -1.9851905180, 0.9852993732 |
| Notch 1000 Q4 | 0.9839461568, -1.9510567222, 0.9839461568, -1.9510567222, 0.9678923137 |

The same filters at 44.1 kHz are covered by the tests with the published
coefficients. Magnitudes at 63/125/250/500/1k/2k/4k/8k/16k Hz are asserted to
0.01 dB.

## Open questions

1. Does the tap run on progressive remote FLAC/AAC, cached and downloaded
   items, and what processing format does it report?
2. Is the audio track available early enough to attach the mix before playback?
3. Does removing the mix for bypass glitch?
4. CPU cost of ten biquads plus limiter at 192 kHz on the device.

How the equalizer sounds can only be judged by a person.
