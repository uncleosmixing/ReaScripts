local GmemRead = {}

local GMEM_NAME = "RCC_ANALYZER_TAP"
local MAGIC = 822031
local SPECTRUM_BINS = 128
local SCOPE_POINTS = 384
local analyzer = {
  spectrum = {},
  scope = {},
  waveform = {},
  waveform_l = {},
  waveform_r = {},
}

local function EnsureAttached()
  reaper.gmem_attach(GMEM_NAME)
end

local function Db(value)
  if value <= 0 then
    return -150.0
  end

  return 20 * (math.log(value) / math.log(10))
end

function GmemRead.ReadAnalyzer()
  EnsureAttached()

  local magic = reaper.gmem_read(0)
  local version = reaper.gmem_read(1)
  local counter = reaper.gmem_read(2)
  local active = magic == MAGIC and counter > 0
  local peak_l = active and reaper.gmem_read(3) or 0
  local peak_r = active and reaper.gmem_read(4) or 0
  local rms_l = active and reaper.gmem_read(5) or 0
  local rms_r = active and reaper.gmem_read(6) or 0
  local correlation = active and reaper.gmem_read(7) or 0
  local true_peak_l = active and reaper.gmem_read(9) or 0
  local true_peak_r = active and reaper.gmem_read(10) or 0
  local lufs_m = active and reaper.gmem_read(11) or -150
  local lufs_s = active and reaper.gmem_read(12) or -150
  local lufs_i = active and reaper.gmem_read(13) or -150
  local scope_count = active and math.floor(reaper.gmem_read(14)) or 0
  local scope_write = active and math.floor(reaper.gmem_read(15)) or 0
  local waveform_supported = active and reaper.gmem_read(17) == 1
  local waveform_stereo_supported = active and reaper.gmem_read(18) == 1
  local waveform_write = scope_write
  if active and version >= 16 then
    waveform_write = math.floor(reaper.gmem_read(151))
  end
  local sample_rate = active and reaper.gmem_read(153) or 0
  local spectrum_count = active and math.floor(reaper.gmem_read(8)) or 0
  if spectrum_count <= 0 or spectrum_count > SPECTRUM_BINS then
    spectrum_count = SPECTRUM_BINS
  end

  local spectrum = analyzer.spectrum
  for index = 1, spectrum_count do
    spectrum[index] = active and reaper.gmem_read(19 + index) or 0
  end
  for index = spectrum_count + 1, #spectrum do
    spectrum[index] = nil
  end

  if scope_count <= 0 or scope_count > SCOPE_POINTS then
    scope_count = SCOPE_POINTS
  end

  local scope = analyzer.scope
  local waveform = analyzer.waveform
  local waveform_l = analyzer.waveform_l
  local waveform_r = analyzer.waveform_r
  for index = 1, scope_count do
    local scope_source_index = (scope_write + index - 1) % scope_count
    local waveform_source_index = (waveform_write + index - 1) % scope_count
    local scope_point = scope[index]
    if not scope_point then
      scope_point = {}
      scope[index] = scope_point
    end
    scope_point.x = active and reaper.gmem_read(200 + scope_source_index * 2) or 0
    scope_point.y = active and reaper.gmem_read(201 + scope_source_index * 2) or 0

    local wave_point = waveform[index]
    if not wave_point then
      wave_point = {}
      waveform[index] = wave_point
    end
    wave_point.min = waveform_supported and reaper.gmem_read(1200 + waveform_source_index * 2) or 0
    wave_point.max = waveform_supported and reaper.gmem_read(1201 + waveform_source_index * 2) or 0

    local wave_l_point = waveform_l[index]
    if not wave_l_point then
      wave_l_point = {}
      waveform_l[index] = wave_l_point
    end
    wave_l_point.min = waveform_stereo_supported and reaper.gmem_read(2000 + waveform_source_index * 4) or 0
    wave_l_point.max = waveform_stereo_supported and reaper.gmem_read(2001 + waveform_source_index * 4) or 0

    local wave_r_point = waveform_r[index]
    if not wave_r_point then
      wave_r_point = {}
      waveform_r[index] = wave_r_point
    end
    wave_r_point.min = waveform_stereo_supported and reaper.gmem_read(2002 + waveform_source_index * 4) or 0
    wave_r_point.max = waveform_stereo_supported and reaper.gmem_read(2003 + waveform_source_index * 4) or 0
  end
  for index = scope_count + 1, #scope do
    scope[index] = nil
    waveform[index] = nil
    waveform_l[index] = nil
    waveform_r[index] = nil
  end

  analyzer.active = active
  analyzer.version = version
  analyzer.counter = counter
  analyzer.peak_l = peak_l
  analyzer.peak_r = peak_r
  analyzer.rms_l = rms_l
  analyzer.rms_r = rms_r
  analyzer.peak_l_db = Db(peak_l)
  analyzer.peak_r_db = Db(peak_r)
  analyzer.rms_l_db = Db(rms_l)
  analyzer.rms_r_db = Db(rms_r)
  analyzer.correlation = correlation
  analyzer.true_peak_l = true_peak_l
  analyzer.true_peak_r = true_peak_r
  analyzer.true_peak_l_db = Db(true_peak_l)
  analyzer.true_peak_r_db = Db(true_peak_r)
  analyzer.lufs_m = lufs_m
  analyzer.lufs_s = lufs_s
  analyzer.lufs_i = lufs_i
  analyzer.spectrum_count = spectrum_count
  analyzer.scope_count = scope_count
  analyzer.waveform_count = scope_count
  analyzer.waveform_write = waveform_write
  analyzer.sample_rate = sample_rate > 0 and sample_rate or nil
  analyzer.waveform_supported = waveform_supported
  analyzer.waveform_stereo_supported = waveform_stereo_supported

  return analyzer
end

return GmemRead
