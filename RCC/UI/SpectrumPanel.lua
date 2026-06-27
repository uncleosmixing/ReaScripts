local SpectrumPanel = {}
local UIUtils = require("UIUtils")
local ImGui = nil

function SpectrumPanel.SetImGui(imgui)
  ImGui = imgui
end

local SPECTRUM_LABELS = {
  { label = "20",  norm = 0.0,   show_text = true },
  { label = "50",  norm = 0.133, show_text = false },
  { label = "100", norm = 0.233, show_text = true },
  { label = "200", norm = 0.333, show_text = false },
  { label = "500", norm = 0.466, show_text = true },
  { label = "1k",  norm = 0.566, show_text = true },
  { label = "2k",  norm = 0.666, show_text = false },
  { label = "5k",  norm = 0.799, show_text = true },
  { label = "10k", norm = 0.899, show_text = false },
  { label = "20k", norm = 1.0,   show_text = true }
}

local SPECTRUM_PRESETS = {
  mix = {
    tilt_db_octave = 4.5,
    smooth_factor = 0.25,
    peak_decay_factor = 0.92,
    gauss_bw_scale = 0.8,
    curve_width = 2.0,
    fill_gain = 1.0,
  },
  master = {
    tilt_db_octave = 3.0,
    smooth_factor = 0.88,
    peak_decay_factor = 0.997,
    gauss_bw_scale = 2.5,
    curve_width = 1.2,
    fill_gain = 0.65,
  }
}

local DB_RANGES = {
  { label = "30", floor = -30, ticks = {-6, -12, -18, -24, -30} },
  { label = "40", floor = -40, ticks = {-8, -16, -24, -32, -40} },
  { label = "60", floor = -60, ticks = {-12, -24, -36, -48, -60} },
  { label = "90", floor = -90, ticks = {-18, -36, -54, -72, -90} },
}

local function UpdateExpandAnimation(state, target)
  state.spectrum_expand_anim = state.spectrum_expand_anim or target
  state.spectrum_expand_anim_time = state.spectrum_expand_anim_time or reaper.time_precise()

  local now = reaper.time_precise()
  local dt = math.max(0.0, math.min(0.05, now - state.spectrum_expand_anim_time))
  state.spectrum_expand_anim_time = now

  local speed = target > state.spectrum_expand_anim and 2.8 or 4.8
  state.spectrum_expand_anim = UIUtils.Approach(state.spectrum_expand_anim, target, speed, dt)
  return UIUtils.EaseOutCubic(state.spectrum_expand_anim)
end

local GAUSS_CACHE = nil
local function GetGaussWindow(size)
  if GAUSS_CACHE and GAUSS_CACHE.size == size then
    return GAUSS_CACHE.window
  end
  local w = {}
  local sigma = math.max(1, size * 0.25)
  local half = math.floor(size * 0.5)
  local total = 0
  for i = 0, size - 1 do
    local d = i - half
    local v = math.exp(-0.5 * (d / sigma) ^ 2)
    w[i + 1] = v
    total = total + v
  end
  for i = 1, size do w[i] = w[i] / total end
  GAUSS_CACHE = { size = size, window = w }
  return w
end

local function GetSpectrumZoneColor(norm, val_norm, peak_norm)
  local stops = {
    { n = 0.00, r = 150, g = 36,  b = 78  },
    { n = 0.20, r = 190, g = 74,  b = 28  },
    { n = 0.42, r = 196, g = 150, b = 28  },
    { n = 0.62, r = 42,  g = 166, b = 74  },
    { n = 0.82, r = 28,  g = 145, b = 192 },
    { n = 1.00, r = 108, g = 66,  b = 184 },
  }

  local left = stops[1]
  local right = stops[#stops]
  for i = 1, #stops - 1 do
    if norm >= stops[i].n and norm <= stops[i + 1].n then
      left = stops[i]
      right = stops[i + 1]
      break
    end
  end

  local span = math.max(0.001, right.n - left.n)
  local t = (norm - left.n) / span
  local smooth = t * t * (3.0 - 2.0 * t)
  local energy = math.max(0.0, math.min(1.0, val_norm))
  local peak = math.max(0.0, math.min(1.0, peak_norm or energy))
  local brightness = 0.28 + energy * 0.72
  local alpha = 20 + 145 * (energy ^ 0.85) + 42 * peak

  local r, g, b
  r = (left.r + (right.r - left.r) * smooth) * brightness
  g = (left.g + (right.g - left.g) * smooth) * brightness
  b = (left.b + (right.b - left.b) * smooth) * brightness

  r = math.max(0, math.min(255, math.floor(r)))
  g = math.max(0, math.min(255, math.floor(g)))
  b = math.max(0, math.min(255, math.floor(b)))
  alpha = math.max(12, math.min(215, math.floor(alpha)))

  return (r << 24) | (g << 16) | (b << 8) | alpha
end

local function FormatFreq(freq)
  if freq >= 10000 then
    return string.format("%.1fk", freq / 1000)
  elseif freq >= 1000 then
    return string.format("%.2fk", freq / 1000)
  end

  return string.format("%.0f", freq)
end

local function FormatHoverFreq(freq)
  if freq >= 10000 then
    return string.format("%.1fk", freq / 1000)
  elseif freq >= 1000 then
    return string.format("%.1fk", freq / 1000)
  end

  return string.format("%.0f", freq)
end

local function FindPeakMarkers(spectrum_data, min_db, log_min, log_max)
  local markers = {}
  local count = #spectrum_data
  if count < 5 then return markers end

  local candidates = {}
  for i = 3, count - 2 do
    local db = UIUtils.Db(spectrum_data[i] or 0)
    local left_db = UIUtils.Db(spectrum_data[i - 1] or 0)
    local right_db = UIUtils.Db(spectrum_data[i + 1] or 0)
    local shoulder_db = math.max(
      UIUtils.Db(spectrum_data[i - 2] or 0),
      UIUtils.Db(spectrum_data[i + 2] or 0)
    )

    if db > min_db + 10 and db >= left_db and db >= right_db and db > shoulder_db + 0.4 then
      local norm = (i - 1) / math.max(1, count - 1)
      candidates[#candidates + 1] = {
        index = i,
        db = db,
        freq = math.exp(log_min + norm * (log_max - log_min)),
        norm = norm,
      }
    end
  end

  table.sort(candidates, function(a, b) return a.db > b.db end)

  for _, item in ipairs(candidates) do
    local keep = true
    for _, chosen in ipairs(markers) do
      local ratio = math.max(item.freq, chosen.freq) / math.max(1, math.min(item.freq, chosen.freq))
      if ratio < 1.18 then
        keep = false
        break
      end
    end
    if keep then
      markers[#markers + 1] = item
      if #markers >= 5 then break end
    end
  end

  return markers
end

local function UpdateSpectrumHoverHold(state, processed_spectrum, min_db, log_min, log_max)
  state.spectrum_hover_hold = state.spectrum_hover_hold or {}

  local count = #processed_spectrum
  for i = 1, count do
    local current = processed_spectrum[i] or 0
    local held = state.spectrum_hover_hold[i]
    if held == nil or current > held then
      state.spectrum_hover_hold[i] = current
    end
  end

  state.spectrum_hover_peaks = FindPeakMarkers(state.spectrum_hover_hold, min_db, log_min, log_max)
end

local function RenderSpectrumCore(ctx, state, spectrum, x, y, width, height, small_font, small_font_size, is_zoomed, collapse_anim)
  local draw_api = UIUtils.GetDrawApi()
  if not draw_api then return end

  local draw_list = draw_api.get_draw_list(ctx)
  local right = x + width
  local bottom = y + height

  local rounding = is_zoomed and 8.0 or 6.0

  UIUtils.DrawInstrumentPanel(draw_list, draw_api, x, y, right, bottom, rounding)
  if is_zoomed then
    UIUtils.DrawModuleLabel(ctx, draw_list, draw_api, x, y, "SPECTRUM", small_font, small_font_size)
  else
    UIUtils.DrawCollapsibleModuleLabel(ctx, draw_list, draw_api, x, y, "SPECTRUM", "spectrum", state, small_font, small_font_size)
  end

  local body_clip = true
  if not is_zoomed then
    body_clip = UIUtils.BeginAnimatedPanelBodyClip(ctx, x, y, right, bottom, collapse_anim or 1.0)
    if not body_clip then
      return
    end
  end

  -- 1. Setup Preset Parameters
  state.spectrum_preset = state.spectrum_preset or "mix"
  local preset = state.spectrum_preset

  local preset_cfg = SPECTRUM_PRESETS[preset] or SPECTRUM_PRESETS.mix
  state.spectrum_db_range = state.spectrum_db_range or 4
  local db_range = DB_RANGES[state.spectrum_db_range] or DB_RANGES[4]
  local min_db = db_range.floor
  local db_ticks = db_range.ticks
  local peak_decay_factor = preset_cfg.peak_decay_factor
  local tilt_db_octave = preset_cfg.tilt_db_octave
  local smooth_factor = preset_cfg.smooth_factor

  -- Pre-compute logarithmic tilt and Peak Hold curves
  local count = #spectrum
  state.spectrum_processed = state.spectrum_processed or {}
  local processed_spectrum = state.spectrum_processed
  state.spectrum_peaks = state.spectrum_peaks or {}
  state.smooth_spectrum = state.smooth_spectrum or {}

  local log_min = math.log(20)
  local log_max = math.log(20000)

  for index = 1, count do
    local norm = (index - 1) / math.max(1, count - 1)
    local freq = math.exp(log_min + norm * (log_max - log_min))

    local tilt_db = tilt_db_octave * (math.log(freq / 1000) / math.log(2))
    local scale = 10 ^ (tilt_db / 20)

    local bw_frac = (0.015 + 0.06 * (1.0 - norm)) * preset_cfg.gauss_bw_scale
    local bw = math.max(1, math.floor(count * bw_frac + 0.5))
    local half = math.floor(bw * 0.5)
    local win = GetGaussWindow(bw)
    local lo = math.max(1, index - half)
    local hi = math.min(count, index + half)
    local wsum = 0
    for b = lo, hi do
      local wi = b - index + half + 1
      wsum = wsum + (spectrum[b] or 0) * (win[wi] or 0)
    end

    state.smooth_spectrum[index] = (state.smooth_spectrum[index] or wsum) * smooth_factor + wsum * (1.0 - smooth_factor)

    local val_tilted = state.smooth_spectrum[index] * scale
    processed_spectrum[index] = val_tilted

    state.spectrum_peaks[index] = math.max(val_tilted, (state.spectrum_peaks[index] or 0) * peak_decay_factor)
  end
  for index = count + 1, #processed_spectrum do
    processed_spectrum[index] = nil
    state.spectrum_peaks[index] = nil
    state.smooth_spectrum[index] = nil
  end

  local is_mhr = ImGui and ImGui.IsMouseHoveringRect or reaper.ImGui_IsMouseHoveringRect
  local get_mpos = ImGui and ImGui.GetMousePos or reaper.ImGui_GetMousePos

  local spectrum_hovered = false
  if is_mhr then
    spectrum_hovered = is_mhr(ctx, x, y + 20, right, bottom - 14)
  end

  local freeze_active = false
  if spectrum_hovered then
    local mouse_x, mouse_y = get_mpos(ctx)
    local now = reaper.time_precise()
    local last_x = state.spectrum_hover_mouse_x
    local last_y = state.spectrum_hover_mouse_y
    local moved = not last_x or not last_y or math.abs(mouse_x - last_x) > 3 or math.abs(mouse_y - last_y) > 3

    if moved or not state.spectrum_hover_still_since then
      state.spectrum_hover_still_since = now
      if state.spectrum_hover_hold then
        state.spectrum_hover_hold = nil
        state.spectrum_hover_peaks = nil
      end
    end

    state.spectrum_hover_mouse_x = mouse_x
    state.spectrum_hover_mouse_y = mouse_y
    freeze_active = (now - (state.spectrum_hover_still_since or now)) >= 3.0
  else
    state.spectrum_hover_still_since = nil
    state.spectrum_hover_mouse_x = nil
    state.spectrum_hover_mouse_y = nil
  end

  if freeze_active then
    UpdateSpectrumHoverHold(state, processed_spectrum, min_db, log_min, log_max)
  else
    state.spectrum_hover_hold = nil
  end
  state.spectrum_was_hovered = spectrum_hovered

  local display_spectrum = state.spectrum_hover_hold or processed_spectrum
  state.spectrum_live_peaks = FindPeakMarkers(display_spectrum, min_db, log_min, log_max)
  local active_peaks = freeze_active and state.spectrum_hover_peaks or state.spectrum_live_peaks

  -- Grid lines: Vertical frequency divisions
  for index = 1, #SPECTRUM_LABELS do
    local item = SPECTRUM_LABELS[index]
    local gx = math.floor(x + (width * item.norm))
    local grid_color = item.show_text and 0x2A2C32FF or 0x1F2025FF
    draw_api.line(draw_list, gx, y + 20, gx, bottom - 14, grid_color, 1)
  end

  -- Grid lines: Horizontal dB scale reference ticks
  if draw_api.text and small_font then
    local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
    local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
    push_f(ctx, small_font, small_font_size)
    for _, db_val in ipairs(db_ticks) do
      local norm_y = (db_val - min_db) / (-min_db)
      local gy = math.floor(bottom - 14 - (norm_y * (height - 40)))
      gy = math.max(y + 20, gy)

      draw_api.line(draw_list, x, gy, right, gy, 0x24262CFF, 1)
      draw_api.text(draw_list, right - 22, gy - 5, 0x5C626EFF, tostring(db_val))
    end
    pop_f(ctx)
  end

  local plot_h = height - 40
  local plot_top = y + 20
  local plot_bot = bottom - 14

  local function DbToY(db_val)
    local norm = math.max(0.0, math.min((db_val - min_db) / (-min_db), 1.0))
    return math.max(plot_top, math.floor(plot_bot - (norm * plot_h)))
  end

  local pts_px = {}
  local pts_py = {}
  local pts_ppy = {}
  for index = 1, count do
    local norm = (index - 1) / math.max(1, count - 1)
    pts_px[index] = math.floor(x + (width * norm))
    pts_py[index] = DbToY(UIUtils.Db(display_spectrum[index] or 0))
    pts_ppy[index] = DbToY(UIUtils.Db(state.spectrum_peaks[index] or 0))
  end

  for index = 1, count do
    local px = pts_px[index]
    local py = pts_py[index]
    local ppy = pts_ppy[index]
    local norm = (index - 1) / math.max(1, count - 1)

    local fill_color = GetSpectrumZoneColor(norm, (UIUtils.Db(display_spectrum[index] or 0) - min_db) / (-min_db) * preset_cfg.fill_gain, (UIUtils.Db(state.spectrum_peaks[index] or 0) - min_db) / (-min_db) * preset_cfg.fill_gain)
    draw_api.line(draw_list, px, plot_bot, px, py, fill_color, 1.0)

    if index > 1 then
      draw_api.line(draw_list, pts_px[index - 1], pts_ppy[index - 1], px, ppy, 0xFF9E3D66, 1.0)
      draw_api.line(draw_list, pts_px[index - 1], pts_py[index - 1] + 1, px, py + 1, 0x0C1A10FF, 3)
      draw_api.line(draw_list, pts_px[index - 1], pts_py[index - 1], px, py, UIUtils.COLOR.green, preset_cfg.curve_width)
    end
  end

  -- Interactive Note & Frequency Crosshair
  if spectrum_hovered then
    local mouse_x, mouse_y = get_mpos(ctx)
    if mouse_x and mouse_y then
      draw_api.line(draw_list, mouse_x, y + 20, mouse_x, bottom - 14, 0xFFFFFF22, 1.0)

      local mouse_norm = math.max(0.0, math.min((mouse_x - x) / width, 1.0))
      local freq = math.exp(log_min + mouse_norm * (log_max - log_min))

      local note_num = 69 + 12 * (math.log(freq / 440) / math.log(2))
      local nearest_note = math.floor(note_num + 0.5)
      local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
      local octave = math.floor(nearest_note / 12) - 1
      local note_idx = (nearest_note % 12) + 1
      local note_name = "N/A"
      if note_idx >= 1 and note_idx <= 12 then
        note_name = note_names[note_idx] .. tostring(octave)
      end

      local mouse_y_norm = math.max(0.0, math.min((bottom - 14 - mouse_y) / (height - 40), 1.0))
      local db_val = min_db + mouse_y_norm * (-min_db)

      if draw_api.text and small_font then
        local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
        local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
        push_f(ctx, small_font, small_font_size)

        local info_str = string.format("%s  %.0fdB  %s", FormatHoverFreq(freq), db_val, note_name)
        local info_w = UIUtils.TextWidth(ctx, info_str)
        local info_left = x + 9 + UIUtils.TextWidth(ctx, "SPECTRUM") + 8
        local mix_left = right - 58
        local info_right = mix_left - 12
        if info_right - info_left >= info_w then
          local info_x = math.floor(info_left + (info_right - info_left - info_w) * 0.5)
          local info_y = UIUtils.HeaderTextY(ctx, y, info_str, small_font, small_font_size)
          draw_api.text(draw_list, info_x, info_y, 0x4EFFB3CC, info_str)
        end

        pop_f(ctx)
      end
    end

    if draw_api.text and small_font and active_peaks then
      local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
      local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
      push_f(ctx, small_font, small_font_size)
      for _, peak in ipairs(active_peaks) do
        local px = x + width * peak.norm
        local peak_norm = math.max(0.0, math.min((peak.db - min_db) / (-min_db), 1.0))
        local py = plot_bot - (peak_norm * plot_h)
        py = math.max(plot_top, py)
        local label = FormatFreq(peak.freq)
        local label_w = UIUtils.TextWidth(ctx, label)
        local label_x = math.max(x + 2, math.min(right - label_w - 2, px - label_w * 0.5))

        draw_api.line(draw_list, px, py - 10, px, py + 8, 0x5CFFB680, 1.0)
        if draw_api.circle_filled then
          draw_api.circle_filled(draw_list, px, py, 6.0, 0x5CFFB622)
          draw_api.circle_filled(draw_list, px, py, 2.4, 0x5CFFB6FF)
        end
        draw_api.text(draw_list, label_x, math.max(plot_top, py - 18), 0xD7FBEAFF, label)
      end
      pop_f(ctx)
    end
  end

  -- Draw frequency labels at the bottom
  if draw_api.text then
    local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
    local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
    if small_font then
      push_f(ctx, small_font, small_font_size)
    end

    for index = 1, #SPECTRUM_LABELS do
      local item = SPECTRUM_LABELS[index]
      if item.show_text then
        local tx = x + width * item.norm
        local label_width = #item.label * 3

        if item.norm > 0.96 then
          tx = tx - label_width - 2
        elseif item.norm > 0.05 then
          tx = tx - label_width * 0.5
        end

        draw_api.text(draw_list, tx, bottom - 11, 0x6A727EFF, item.label)
      end
    end

    if small_font then
      pop_f(ctx)
    end
  end

  if not is_zoomed then
    UIUtils.EndAnimatedPanelBodyClip(ctx, body_clip)
  end

  -- Glassmorphic badge for zoomed popup close
  if is_zoomed and draw_api.text and small_font then
    local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
    local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
    push_f(ctx, small_font, small_font_size)
    draw_api.rect_filled(draw_list, right - 110, y + 6, right - 6, y + 22, 0x222233AA, 4.0)
    draw_api.rect(draw_list, right - 110, y + 6, right - 6, y + 22, 0x5CFFB622, 4.0, nil, 1.0)
    draw_api.text(draw_list, right - 105, y + 8, 0x5CFFB6FF, "Click to Shrink [X]")
    pop_f(ctx)
  end
end

local function DrawPresetSelector(ctx, state, width)
  state.spectrum_preset = state.spectrum_preset or "mix"

  local same_line = ImGui and ImGui.SameLine or reaper.ImGui_SameLine
  local push_sc = ImGui and ImGui.PushStyleColor or reaper.ImGui_PushStyleColor
  local pop_sc = ImGui and ImGui.PopStyleColor or reaper.ImGui_PopStyleColor
  local col_txt = ImGui and ImGui.Col_Text or reaper.ImGui_Col_Text
  local txt = ImGui and ImGui.Text or reaper.ImGui_Text
  local is_hov = ImGui and ImGui.IsItemHovered or reaper.ImGui_IsItemHovered
  local set_mc = ImGui and ImGui.SetMouseCursor or reaper.ImGui_SetMouseCursor
  local mc_hand = ImGui and ImGui.MouseCursor_Hand or reaper.ImGui_MouseCursor_Hand
  local is_clicked = ImGui and ImGui.IsItemClicked or reaper.ImGui_IsItemClicked

  same_line(ctx, math.max(0, width - 80))

  local mix_active = state.spectrum_preset == "mix"
  local master_active = state.spectrum_preset == "master"

  if mix_active then
    push_sc(ctx, col_txt(), 0x5CFFB6FF)
  else
    push_sc(ctx, col_txt(), 0x767D8AFF)
  end
  txt(ctx, "MIX")
  pop_sc(ctx, 1)

  if is_hov(ctx) then
    set_mc(ctx, mc_hand())
  end
  if is_clicked(ctx) then
    state.spectrum_preset = "mix"
  end

  same_line(ctx)
  push_sc(ctx, col_txt(), 0x33353CFF)
  txt(ctx, "|")
  pop_sc(ctx, 1)

  same_line(ctx)

  if master_active then
    push_sc(ctx, col_txt(), 0x5CFFB6FF)
  else
    push_sc(ctx, col_txt(), 0x767D8AFF)
  end
  txt(ctx, "MAST")
  pop_sc(ctx, 1)

  if is_hov(ctx) then
    set_mc(ctx, mc_hand())
  end
  if is_clicked(ctx) then
    state.spectrum_preset = "master"
  end
end

function SpectrumPanel.Draw(ctx, state, spectrum, small_font, small_font_size)
  local get_avail = ImGui and ImGui.GetContentRegionAvail or reaper.ImGui_GetContentRegionAvail
  local width = get_avail(ctx)
  state.spectrum_expanded = state.spectrum_expanded or false
  local anim = UpdateExpandAnimation(state, state.spectrum_expanded and 1.0 or 0.0)
  local full_height = math.floor(126 + (252 - 126) * anim + 0.5)
  local height, _, collapse_anim = UIUtils.GetCollapsiblePanelHeight(state, "spectrum", full_height, 22)
  local draw_api = UIUtils.GetDrawApi()

  if not draw_api then
    return
  end

  local x, y = draw_api.get_cursor_pos(ctx)
  local right = x + width
  local draw_list = draw_api.get_draw_list(ctx)
  local bottom = y + height
  state.spectrum_preset = state.spectrum_preset or "mix"

  RenderSpectrumCore(ctx, state, spectrum, x, y, width, height, small_font, small_font_size, false, collapse_anim)

  local set_csp = ImGui and ImGui.SetCursorScreenPos or reaper.ImGui_SetCursorScreenPos
  local inv_btn = ImGui and ImGui.InvisibleButton or reaper.ImGui_InvisibleButton

  if draw_api.text and small_font then
    local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
    local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont

    push_f(ctx, small_font, small_font_size)
    local mix_x = right - 90
    local mast_x = right - 62
    local range_x = right - 30
    local preset_y = UIUtils.HeaderTextY(ctx, y, "MIX", small_font, small_font_size)
    draw_api.text(draw_list, mix_x, preset_y, state.spectrum_preset == "mix" and 0x5CFFB6FF or 0x767D8AFF, "MIX")
    draw_api.text(draw_list, mast_x, preset_y, state.spectrum_preset == "master" and 0x5CFFB6FF or 0x767D8AFF, "MAST")

    state.spectrum_db_range = state.spectrum_db_range or 4
    local range_label = DB_RANGES[state.spectrum_db_range].label .. "dB"
    draw_api.text(draw_list, range_x, preset_y, 0x5CFFB6AA, range_label)
    pop_f(ctx)

    set_csp(ctx, mix_x - 4, y + 1)
    if inv_btn(ctx, "##spectrum_preset_mix", 30, 17) then
      state.spectrum_preset = "mix"
    end
    set_csp(ctx, mast_x - 4, y + 1)
    if inv_btn(ctx, "##spectrum_preset_master", 38, 17) then
      state.spectrum_preset = "master"
    end
    set_csp(ctx, range_x - 4, y + 1)
    if inv_btn(ctx, "##spectrum_db_range", 46, 17) then
      state.spectrum_db_range = (state.spectrum_db_range % #DB_RANGES) + 1
    end
  end

  local plot_x = x + 7
  local plot_y = y + 27
  local plot_right = right - 7
  local plot_bottom = bottom - 15
  local btn_w = math.max(1, plot_right - plot_x)
  local btn_h = math.max(1, plot_bottom - plot_y)
  if collapse_anim > 0.96 and btn_w > 0.001 and btn_h > 0.001 then
    set_csp(ctx, plot_x, plot_y)
    if inv_btn(ctx, "##spectrum_expand_toggle", btn_w, btn_h) then
      state.spectrum_expanded = not state.spectrum_expanded
    end
    local is_hov = ImGui and ImGui.IsItemHovered or reaper.ImGui_IsItemHovered
    local set_mc = ImGui and ImGui.SetMouseCursor or reaper.ImGui_SetMouseCursor
    local mc_hand = ImGui and ImGui.MouseCursor_Hand or reaper.ImGui_MouseCursor_Hand
    if is_hov(ctx) then
      set_mc(ctx, mc_hand())
    end
  end

  set_csp(ctx, x, y)
  draw_api.dummy(ctx, width, height)
end

return SpectrumPanel
