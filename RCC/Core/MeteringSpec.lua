local MeteringSpec = {}

MeteringSpec.metrics = {
  peak = {
    label = "Peak",
    unit = "dBFS",
    source = "JSFX sample peak detector",
    math = "max(abs(L), abs(R)) with UI peak hold/decay",
    status = "sample-accurate peak, not inter-sample",
  },
  true_peak = {
    label = "TP",
    unit = "dBTP",
    source = "JSFX oversampled reconstruction peak",
    math = "sample peak plus 4x fractional sinc/Blackman FIR reconstruction peak",
    status = "BS.1770-style true peak detector; needs official test-set validation before calling it certified",
  },
  rms = {
    label = "RMS",
    unit = "dBFS",
    source = "JSFX exponential RMS detector",
    math = "sqrt(one-pole average of squared samples), coeff 0.999",
    status = "realtime RMS ballistics, not a fixed 300 ms AES meter yet",
  },
  lufs_m = {
    label = "LUFS-M",
    unit = "LUFS",
    source = "JSFX K-weighted block energy",
    math = "K-weighting, stereo energy, 400 ms rectangular window updated every 100 ms",
    status = "BS.1770/EBU Mode style momentary window; needs official test-set validation",
  },
  lufs_s = {
    label = "LUFS-S",
    unit = "LUFS",
    source = "JSFX K-weighted block energy",
    math = "K-weighting, stereo energy, 3 s rectangular window updated every 100 ms",
    status = "BS.1770/EBU Mode style short-term window; needs official test-set validation",
  },
  lufs_i = {
    label = "LUFS-I",
    unit = "LUFS",
    source = "JSFX K-weighted gated block energy",
    math = "400 ms blocks updated every 100 ms, absolute gate -70 LUFS, relative gate -10 LU",
    status = "BS.1770-style gated integrated loudness; limited by in-plugin history cap and needs official test-set validation",
  },
  correlation = {
    label = "Correlation",
    unit = "",
    source = "JSFX normalized L/R product",
    math = "E[L*R] / sqrt(E[L^2] * E[R^2]), one-pole realtime smoothing",
    status = "realtime phase correlation",
  },
}

MeteringSpec.modes = {
  dbfs = {"peak", "rms", "true_peak"},
  lufs = {"lufs_m", "lufs_s", "lufs_i"},
  streaming = {"lufs_i", "target_diff", "true_peak"},
  k_system = {"peak", "rms", "headroom"},
}

return MeteringSpec
