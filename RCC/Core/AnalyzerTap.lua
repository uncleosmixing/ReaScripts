local AnalyzerTap = {}

local GMEM_NAME = "RCC_ANALYZER_TAP"
local FX_DIR = "RCC"
local FX_FILE = "RCC_AnalyzerTap_v16.jsfx"
local FX_NAMES = {
  "JS: RCC/RCC_AnalyzerTap_v16",
  "JS: RCC Analyzer Tap v16",
  "RCC_AnalyzerTap_v16",
  "RCC Analyzer Tap v16",
  "JS: RCC/RCC_AnalyzerTap_v15",
  "JS: RCC Analyzer Tap v15",
  "RCC_AnalyzerTap_v15",
  "RCC Analyzer Tap v15",
  "JS: RCC/RCC_AnalyzerTap_v14",
  "JS: RCC Analyzer Tap v14",
  "RCC_AnalyzerTap_v14",
  "RCC Analyzer Tap v14",
  "JS: RCC/RCC_AnalyzerTap_v13",
  "JS: RCC Analyzer Tap v13",
  "RCC_AnalyzerTap_v13",
  "RCC Analyzer Tap v13",
  "JS: RCC/RCC_AnalyzerTap_v12",
  "JS: RCC Analyzer Tap v12",
  "RCC_AnalyzerTap_v12",
  "RCC Analyzer Tap v12",
  "JS: RCC/RCC_AnalyzerTap_v11",
  "JS: RCC Analyzer Tap v11",
  "RCC_AnalyzerTap_v11",
  "RCC Analyzer Tap v11",
  "JS: RCC/RCC_AnalyzerTap_v10",
  "JS: RCC Analyzer Tap v10",
  "RCC_AnalyzerTap_v10",
  "RCC Analyzer Tap v10",
  "JS: RCC/RCC_AnalyzerTap_v9",
  "JS: RCC Analyzer Tap v9",
  "RCC_AnalyzerTap_v9",
  "RCC Analyzer Tap v9",
  "JS: RCC/RCC_AnalyzerTap_v8",
  "JS: RCC Analyzer Tap v8",
  "RCC_AnalyzerTap_v8",
  "RCC Analyzer Tap v8",
  "JS: RCC/RCC_AnalyzerTap_v7",
  "JS: RCC Analyzer Tap v7",
  "RCC_AnalyzerTap_v7",
  "RCC Analyzer Tap v7",
  "JS: RCC/RCC_AnalyzerTap_v6",
  "JS: RCC Analyzer Tap v6",
  "RCC_AnalyzerTap_v6",
  "RCC Analyzer Tap v6",
  "JS: RCC/RCC_AnalyzerTap_v5",
  "JS: RCC Analyzer Tap v5",
  "RCC_AnalyzerTap_v5",
  "RCC Analyzer Tap v5",
  "JS: RCC/RCC_AnalyzerTap_v4",
  "JS: RCC Analyzer Tap v4",
  "RCC_AnalyzerTap_v4",
  "RCC Analyzer Tap v4",
}
local REC_FX_OFFSET = 0x1000000
local JSFX = [[desc:RCC Analyzer Tap v16
options:gmem=RCC_ANALYZER_TAP

@init
magic = 822031;
version = 16;
fft_size = 2048;
write_pos = 0;
peak_l = 0;
peak_r = 0;
hipkval_l = 0;
hipkval_r = 0;
peak_decay = pow(0.5, 1.0 / max(1, srate) / 0.150);
true_peak_l = 0;
true_peak_r = 0;
rms_l = 0;
rms_r = 0;
corr_num = 0;
corr_l = 0;
corr_r = 0;
counter = 0;
fft_buffer = 0;
spectrum_base = 5000;
out_base = 20;
bin_count = 128;
scope_base = 3000;
waveform_base = 6000;
scope_points = 384;
scope_write = 0;
scope_divider = 0;
scope_divisor = 64;
waveform_write = 0;
waveform_divider = 0;
waveform_divisor = 64;
wave_min = 0;
wave_max = 0;
wave_l_min = 0;
wave_l_max = 0;
wave_r_min = 0;
wave_r_max = 0;
wave_has = 0;
min_freq = 20;
max_freq = 20000;
log_min = log(min_freq);
log_max = log(max_freq);
log10 = log(10);
momentary_lufs = -150;
short_lufs = -150;
integrated_lufs = -150;
integrated_gated_energy = 0;
integrated_gated_blocks = 0;
block_energy = 0;
block_count = 0;
block_size = max(1, floor(srate * 0.100));
loud_100ms_base = 9000;
loud_gate_base = 9100;
loud_ring_pos = 0;
loud_ring_filled = 0;
loud_gate_write = 0;
loud_gate_count = 0;
loud_gate_max = 7200;
last_play_state = 0;
prev_l = 0;
prev_r = 0;
tp_l_hist = 17000;
tp_r_hist = 17100;
tp_taps = 16;
gmem_write_counter = 0;

function make_highpass(freq q) local(w0 cosw sinw alpha a0) (
  w0 = 2 * $pi * freq / srate;
  cosw = cos(w0);
  sinw = sin(w0);
  alpha = sinw / (2 * q);
  hp_b0 = (1 + cosw) * 0.5;
  hp_b1 = -(1 + cosw);
  hp_b2 = (1 + cosw) * 0.5;
  a0 = 1 + alpha;
  hp_a1 = -2 * cosw;
  hp_a2 = 1 - alpha;
  hp_b0 /= a0; hp_b1 /= a0; hp_b2 /= a0; hp_a1 /= a0; hp_a2 /= a0;
);

function make_highshelf(freq gain_db q) local(a w0 cosw sinw alpha beta a0) (
  a = 10 ^ (gain_db / 40);
  w0 = 2 * $pi * freq / srate;
  cosw = cos(w0);
  sinw = sin(w0);
  alpha = sinw / (2 * q);
  beta = 2 * sqrt(a) * alpha;
  hs_b0 = a * ((a + 1) + (a - 1) * cosw + beta);
  hs_b1 = -2 * a * ((a - 1) + (a + 1) * cosw);
  hs_b2 = a * ((a + 1) + (a - 1) * cosw - beta);
  a0 = (a + 1) - (a - 1) * cosw + beta;
  hs_a1 = 2 * ((a - 1) - (a + 1) * cosw);
  hs_a2 = (a + 1) - (a - 1) * cosw - beta;
  hs_b0 /= a0; hs_b1 /= a0; hs_b2 /= a0; hs_a1 /= a0; hs_a2 /= a0;
);

make_highpass(38.135470876, 0.5);
make_highshelf(1681.974450955, 4.0, 0.7071752369554196);

function kweight_l(x) local(y1 y2) (
  y1 = hs_b0 * x + hs_b1 * hs_l_x1 + hs_b2 * hs_l_x2 - hs_a1 * hs_l_y1 - hs_a2 * hs_l_y2;
  hs_l_x2 = hs_l_x1; hs_l_x1 = x; hs_l_y2 = hs_l_y1; hs_l_y1 = y1;
  y2 = hp_b0 * y1 + hp_b1 * hp_l_x1 + hp_b2 * hp_l_x2 - hp_a1 * hp_l_y1 - hp_a2 * hp_l_y2;
  hp_l_x2 = hp_l_x1; hp_l_x1 = y1; hp_l_y2 = hp_l_y1; hp_l_y1 = y2;
  y2;
);

function kweight_r(x) local(y1 y2) (
  y1 = hs_b0 * x + hs_b1 * hs_r_x1 + hs_b2 * hs_r_x2 - hs_a1 * hs_r_y1 - hs_a2 * hs_r_y2;
  hs_r_x2 = hs_r_x1; hs_r_x1 = x; hs_r_y2 = hs_r_y1; hs_r_y1 = y1;
  y2 = hp_b0 * y1 + hp_b1 * hp_r_x1 + hp_b2 * hp_r_x2 - hp_a1 * hp_r_y1 - hp_a2 * hp_r_y2;
  hp_r_x2 = hp_r_x1; hp_r_x1 = y1; hp_r_y2 = hp_r_y1; hp_r_y1 = y2;
  y2;
);

function sinc(x) (
  abs(x) < 0.000001 ? 1 : sin($pi * x) / ($pi * x);
);

function blackman(i n) local(a) (
  a = i / max(1, n - 1);
  0.42 - 0.5 * cos(2 * $pi * a) + 0.08 * cos(4 * $pi * a);
);

function oversample_peak(hist frac) local(sum i centered tap_pos coef norm w) (
  sum = 0;
  norm = 0;
  i = 0;
  loop(tp_taps,
    centered = i - (tp_taps - 1) * 0.5;
    tap_pos = centered - frac;
    w = blackman(i, tp_taps);
    coef = sinc(tap_pos) * w;
    sum += hist[i] * coef;
    norm += coef;
    i += 1;
  );
  abs(sum / max(0.000000001, norm));
);

function update_true_peak_hist(hist sample) local(i) (
  i = tp_taps - 1;
  loop(tp_taps - 1,
    hist[i] = hist[i - 1];
    i -= 1;
  );
  hist[0] = sample;
);

i = 0;
loop(bin_count,
  spectrum_base[i] = 0;
  i += 1;
);

@sample
abs_l = abs(spl0);
abs_r = abs(spl1);
k_l = kweight_l(spl0);
k_r = kweight_r(spl1);

-- Cox formula: peak decay 150ms half-life
peak_l = max(abs_l, peak_l * peak_decay);
peak_r = max(abs_r, peak_r * peak_decay);

-- Hipkval: absolute max, never decays (matches Cox)
abs_l > hipkval_l ? hipkval_l = abs_l;
abs_r > hipkval_r ? hipkval_r = abs_r;

tp_frame_l = abs_l;
tp_frame_r = abs_r;

update_true_peak_hist(tp_l_hist, spl0);
update_true_peak_hist(tp_r_hist, spl1);
tp_frame_l = max(tp_frame_l, oversample_peak(tp_l_hist, 0.0));
tp_frame_l = max(tp_frame_l, oversample_peak(tp_l_hist, 0.25));
tp_frame_l = max(tp_frame_l, oversample_peak(tp_l_hist, 0.50));
tp_frame_l = max(tp_frame_l, oversample_peak(tp_l_hist, 0.75));
tp_frame_r = max(tp_frame_r, oversample_peak(tp_r_hist, 0.0));
tp_frame_r = max(tp_frame_r, oversample_peak(tp_r_hist, 0.25));
tp_frame_r = max(tp_frame_r, oversample_peak(tp_r_hist, 0.50));
tp_frame_r = max(tp_frame_r, oversample_peak(tp_r_hist, 0.75));
true_peak_l = max(tp_frame_l, true_peak_l);
true_peak_r = max(tp_frame_r, true_peak_r);
prev_l = spl0;
prev_r = spl1;

rms_l = rms_l * 0.999 + spl0 * spl0 * 0.001;
rms_r = rms_r * 0.999 + spl1 * spl1 * 0.001;

scope_mono = (spl0 + spl1) * 0.5;
wave_has == 0 ? (
  wave_min = scope_mono;
  wave_max = scope_mono;
  wave_l_min = spl0;
  wave_l_max = spl0;
  wave_r_min = spl1;
  wave_r_max = spl1;
  wave_has = 1;
) : (
  wave_min = min(wave_min, scope_mono);
  wave_max = max(wave_max, scope_mono);
  wave_l_min = min(wave_l_min, spl0);
  wave_l_max = max(wave_l_max, spl0);
  wave_r_min = min(wave_r_min, spl1);
  wave_r_max = max(wave_r_max, spl1);
);

scope_divisor = gmem[16] > 0 ? min(512, max(8, floor(gmem[16]))) : 64;
scope_divider += 1;
scope_divider >= scope_divisor ? (
  scope_mid = (spl0 + spl1) * 0.70710678118;
  scope_side = (spl0 - spl1) * 0.70710678118;
  scope_base[scope_write * 2] = scope_side;
  scope_base[scope_write * 2 + 1] = scope_mid;
  scope_write = (scope_write + 1) % scope_points;
  scope_divider = 0;
);

waveform_divisor = gmem[150] > 0 ? min(512, max(8, floor(gmem[150]))) : 64;
waveform_divider += 1;
waveform_divider >= waveform_divisor ? (
  waveform_base[waveform_write * 2] = wave_min;
  waveform_base[waveform_write * 2 + 1] = wave_max;
  waveform_base[800 + waveform_write * 4] = wave_l_min;
  waveform_base[801 + waveform_write * 4] = wave_l_max;
  waveform_base[802 + waveform_write * 4] = wave_r_min;
  waveform_base[803 + waveform_write * 4] = wave_r_max;
  waveform_write = (waveform_write + 1) % scope_points;
  waveform_divider = 0;
  wave_has = 0;
);

stereo_energy = k_l * k_l + k_r * k_r;
block_energy += stereo_energy;
block_count += 1;

playing = play_state & 1;
play_state != last_play_state && playing ? (
  momentary_lufs = -150;
  short_lufs = -150;
  integrated_lufs = -150;
  integrated_gated_energy = 0;
  integrated_gated_blocks = 0;
  loud_ring_pos = 0;
  loud_ring_filled = 0;
  loud_gate_write = 0;
  loud_gate_count = 0;
);
last_play_state = play_state;

function energy_to_lufs(e) (
  -0.691 + 10 * log(max(e, 0.000000000001)) / log10;
);

block_count >= block_size ? (
  block_avg = block_energy / block_count;

  loud_100ms_base[loud_ring_pos] = block_avg;
  loud_ring_pos = (loud_ring_pos + 1) % 30;
  loud_ring_filled = min(30, loud_ring_filled + 1);

  loud_ring_filled >= 4 ? (
    sum_m = 0;
    i = 0;
    loop(4,
      idx = (loud_ring_pos - 1 - i + 30) % 30;
      sum_m += loud_100ms_base[idx];
      i += 1;
    );
    momentary_energy_400 = sum_m / 4;
    momentary_lufs = energy_to_lufs(momentary_energy_400);

    momentary_lufs > -70 ? (
      loud_gate_base[loud_gate_write] = momentary_energy_400;
      loud_gate_write = (loud_gate_write + 1) % loud_gate_max;
      loud_gate_count = min(loud_gate_max, loud_gate_count + 1);

      abs_sum = 0;
      i = 0;
      loop(loud_gate_count,
        abs_sum += loud_gate_base[i];
        i += 1;
      );
      abs_avg = loud_gate_count > 0 ? abs_sum / loud_gate_count : 0;
      relative_gate = energy_to_lufs(abs_avg) - 10;

      gated_sum = 0;
      gated_count = 0;
      i = 0;
      loop(loud_gate_count,
        gate_energy = loud_gate_base[i];
        energy_to_lufs(gate_energy) > relative_gate ? (
          gated_sum += gate_energy;
          gated_count += 1;
        );
        i += 1;
      );

      integrated_gated_energy = gated_sum;
      integrated_gated_blocks = gated_count;
      integrated_lufs = gated_count > 0 ? energy_to_lufs(gated_sum / gated_count) : -150;
    );
  );

  loud_ring_filled >= 30 ? (
    sum_s = 0;
    i = 0;
    loop(30,
      idx = (loud_ring_pos - 1 - i + 30) % 30;
      sum_s += loud_100ms_base[idx];
      i += 1;
    );
    short_lufs = energy_to_lufs(sum_s / 30);
  );

  block_energy = 0;
  block_count = 0;
);

corr_num = corr_num * 0.999 + spl0 * spl1 * 0.001;
corr_l = corr_l * 0.999 + spl0 * spl0 * 0.001;
corr_r = corr_r * 0.999 + spl1 * spl1 * 0.001;
corr_den = sqrt(max(corr_l * corr_r, 0.000000000001));
corr = corr_num / corr_den;
corr = max(-1, min(1, corr));

mono = (spl0 + spl1) * 0.5;
window = 0.5 - 0.5 * cos(2 * $pi * write_pos / (fft_size - 1));
fft_buffer[write_pos] = mono * window;
write_pos += 1;

write_pos >= fft_size ? (
  fft_real(fft_buffer, fft_size);
  fft_permute(fft_buffer, fft_size / 2);

  i = 0;
  loop(bin_count,
    norm = i / (bin_count - 1);
    freq = exp(log_min + norm * (log_max - log_min));
    fft_bin = floor(freq * fft_size / srate);
    fft_bin = max(1, min(fft_size / 2 - 2, fft_bin));

    re = fft_buffer[fft_bin * 2];
    im = fft_buffer[fft_bin * 2 + 1];
    mag = sqrt(re * re + im * im) / (fft_size * 0.25);
    spectrum_base[i] = spectrum_base[i] * 0.82 + mag * 0.18;

    i += 1;
  );

  write_pos = 0;
);

counter += 1;
gmem_write_counter += 1;

gmem_write_counter >= 256 ? (
  gmem_write_counter = 0;

  gmem[0] = magic;
  gmem[1] = version;
  gmem[2] = counter;
  gmem[3] = peak_l;
  gmem[4] = peak_r;
  gmem[5] = sqrt(rms_l);
  gmem[6] = sqrt(rms_r);
  gmem[7] = corr;
  gmem[8] = bin_count;
  gmem[9] = true_peak_l;
  gmem[10] = true_peak_r;
  gmem[11] = momentary_lufs;
  gmem[12] = short_lufs;
  gmem[13] = integrated_lufs;
  gmem[14] = scope_points;
  gmem[15] = scope_write;
  gmem[17] = 1;
  gmem[18] = 1;
  gmem[19] = hipkval_l;
  gmem[20] = hipkval_r;
  gmem[151] = waveform_write;
  gmem[152] = scope_points;
  gmem[153] = srate;
  hipkval_l = 0;
  hipkval_r = 0;
  true_peak_l = 0;
  true_peak_r = 0;

  i = 0;
  loop(bin_count,
    gmem[out_base + i] = spectrum_base[i];
    i += 1;
  );

  i = 0;
  loop(scope_points * 2,
    gmem[200 + i] = scope_base[i];
    i += 1;
  );

  i = 0;
  loop(scope_points * 2,
    gmem[1200 + i] = waveform_base[i];
    i += 1;
  );

  i = 0;
  loop(scope_points * 4,
    gmem[2000 + i] = waveform_base[800 + i];
    i += 1;
  );
);
]]

local attached = false
local current_checked = false

local function PathJoin(left, right)
  local sep = package.config:sub(1, 1)
  if left:sub(-1) == sep then
    return left .. right
  end

  return left .. sep .. right
end

local function ReadFile(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()
  return content
end

local function WriteFile(path, content)
  local file = io.open(path, "wb")
  if not file then
    return false
  end

  file:write(content)
  file:close()
  return true
end

local function EnsureAttached()
  if attached then
    return
  end

  reaper.gmem_attach(GMEM_NAME)
  attached = true
end

local function GetFxPath()
  local effects_dir = PathJoin(reaper.GetResourcePath(), "Effects")
  local rcc_dir = PathJoin(effects_dir, FX_DIR)
  return PathJoin(rcc_dir, FX_FILE), rcc_dir
end

local function IsAnalyzerTapName(name)
  return name and (
    name:find("RCC Analyzer Tap", 1, true) ~= nil or
    name:find("RCC_AnalyzerTap", 1, true) ~= nil
  )
end

local function DeleteMatchingFx(track, rec_fx)
  local count = rec_fx and (reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(track) or 0) or reaper.TrackFX_GetCount(track)
  for index = count - 1, 0, -1 do
    local fx_index = rec_fx and (REC_FX_OFFSET + index) or index
    local _, name = reaper.TrackFX_GetFXName(track, fx_index)
    if IsAnalyzerTapName(name) then
      reaper.TrackFX_Delete(track, fx_index)
    end
  end
end

local function RemoveExistingAnalyzerTaps()
  local master = reaper.GetMasterTrack(0)
  DeleteMatchingFx(master, false)
  DeleteMatchingFx(master, true)

  for track_index = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, track_index)
    DeleteMatchingFx(track, false)
    DeleteMatchingFx(track, true)
  end
end

local function ClearGmem()
  if not reaper.gmem_write then
    return
  end

  EnsureAttached()
  for index = 0, 6000 do
    reaper.gmem_write(index, 0)
  end
end

function AnalyzerTap.EnsureCurrent()
  if current_checked then
    return true, nil, false
  end
  current_checked = true

  local fx_path, rcc_dir = GetFxPath()
  reaper.RecursiveCreateDirectory(rcc_dir, 0)

  local changed = ReadFile(fx_path) ~= JSFX
  if not changed then
    return true, nil, false
  end

  if not WriteFile(fx_path, JSFX) then
    return false, "Cannot write RCC Analyzer Tap JSFX", false
  end

  local master = reaper.GetMasterTrack(0)
  local count = reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(master) or 0
  local installed = false
  for index = 0, count - 1 do
    local fx_index = REC_FX_OFFSET + index
    local _, name = reaper.TrackFX_GetFXName(master, fx_index)
    if IsAnalyzerTapName(name) then
      installed = true
      break
    end
  end

  if not installed then
    return true, nil, false
  end

  RemoveExistingAnalyzerTaps()
  ClearGmem()

  if not reaper.TrackFX_AddByName then
    return false, "TrackFX_AddByName is unavailable", false
  end

  local fx_index = -1
  for _, fx_name in ipairs(FX_NAMES) do
    fx_index = reaper.TrackFX_AddByName(master, fx_name, true, 1)
    if fx_index >= 0 then
      break
    end
  end

  if fx_index < 0 then
    return false, "RCC Analyzer Tap update failed", false
  end

  return true, nil, true
end

local function Db(value)
  if value <= 0 then
    return -150.0
  end

  return 20 * (math.log(value) / math.log(10))
end

function AnalyzerTap.Install()
  local effects_dir = PathJoin(reaper.GetResourcePath(), "Effects")
  local rcc_dir = PathJoin(effects_dir, FX_DIR)
  local fx_path = PathJoin(rcc_dir, FX_FILE)

  reaper.RecursiveCreateDirectory(rcc_dir, 0)

  if ReadFile(fx_path) ~= JSFX and not WriteFile(fx_path, JSFX) then
    return false, "Cannot write RCC Analyzer Tap JSFX"
  end

  if not reaper.TrackFX_AddByName then
    return false, "TrackFX_AddByName is unavailable"
  end

  RemoveExistingAnalyzerTaps()
  ClearGmem()

  local master = reaper.GetMasterTrack(0)
  local fx_index = -1

  for _, fx_name in ipairs(FX_NAMES) do
    fx_index = reaper.TrackFX_AddByName(master, fx_name, true, 1)
    if fx_index >= 0 then
      break
    end
  end

  if fx_index < 0 then
    return false, "RCC Analyzer Tap was installed, but REAPER did not load it"
  end

  return true, nil
end

return AnalyzerTap
