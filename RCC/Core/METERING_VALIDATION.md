# RCC Metering Validation

RCC metering targets ITU-R BS.1770 / EBU R128 style behavior, but it must not be described as certified until it passes external reference validation.

## Current DSP

- `RCC_AnalyzerTap_v15.jsfx`
- Sample peak: per-channel absolute sample peak.
- True peak: sample peak plus 4x fractional sinc/Blackman FIR reconstruction peak.
- LUFS-M: K-weighted stereo energy, 400 ms rectangular window, updated every 100 ms.
- LUFS-S: K-weighted stereo energy, 3 s rectangular window, updated every 100 ms.
- LUFS-I: K-weighted 400 ms blocks updated every 100 ms, absolute gate -70 LUFS, relative gate -10 LU.

## Required Reference Checks

- EBU Tech 3341 / EBU Mode behavior for Momentary, Short-term, Integrated, and True Peak.
- ITU-R BS.1770 loudness and true-peak conformance material where available.
- Compare against at least one trusted external meter that publishes BS.1770 / EBU R128 compliance.

## Acceptance Targets

- Integrated loudness should match reference within the tolerance specified by the reference test set.
- Momentary and short-term loudness should follow the expected window timing and reference value tolerances.
- True peak should match reference dBTP tolerance on inter-sample peak test files.
- Reset/transport behavior must be documented: RCC currently resets integrated loudness on playback start.

## Known Limitations Until Validation

- The true-peak FIR is an in-plugin implementation and still needs test-set comparison.
- The integrated loudness history is capped in memory for realtime operation.
- Multichannel weighting beyond stereo is not implemented in the current RCC analyzer.
