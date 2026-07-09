local LevelPanel = {}
local UIUtils = require("UIUtils")
local MeteringConfig = require("MeteringConfig")
local LevelBar = require("LevelBar")

local METERING_MODES = MeteringConfig.METERING_MODES
local METERING_MODE_LABELS = MeteringConfig.METERING_MODE_LABELS
local STREAMING_TARGETS = MeteringConfig.STREAMING_TARGETS

local function DrawMeteringModePopup(ctx, state)
  if not reaper.ImGui_BeginPopupContextItem or not reaper.ImGui_Selectable then
    return
  end

  local function PushStyleVar(var_fn, value, value2)
    if var_fn then
      if value2 ~= nil then
        reaper.ImGui_PushStyleVar(ctx, var_fn(), value, value2)
      else
        reaper.ImGui_PushStyleVar(ctx, var_fn(), value)
      end
      return 1
    end

    return 0
  end

  local style_var_count = 0
  local style_color_count = 0

  if reaper.ImGui_IsItemClicked and reaper.ImGui_IsItemClicked(ctx, 1) then
    state.metering_menu_open_time = reaper.time_precise()
  end

  local now = reaper.time_precise()
  local open_time = state.metering_menu_open_time or now
  local fade = math.min(1.0, math.max(0.0, (now - open_time) / 0.12))
  fade = 1.0 - (1.0 - fade) * (1.0 - fade)

  if reaper.ImGui_StyleVar_Alpha then
    style_var_count = style_var_count + PushStyleVar(reaper.ImGui_StyleVar_Alpha, fade)
  end
  style_var_count = style_var_count + PushStyleVar(reaper.ImGui_StyleVar_WindowRounding, 7.0)
  style_var_count = style_var_count + PushStyleVar(reaper.ImGui_StyleVar_FrameRounding, 4.0)
  style_var_count = style_var_count + PushStyleVar(reaper.ImGui_StyleVar_WindowPadding, 8.0, 7.0)
  style_var_count = style_var_count + PushStyleVar(reaper.ImGui_StyleVar_ItemSpacing, 4.0, 3.0)

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x121316F4)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x3A3D44FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x163B2A66)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x32A85242)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x32A85266)
  style_color_count = style_color_count + 5

  if reaper.ImGui_BeginPopupContextItem(ctx, "##metering_mode_menu") then
    for _, item in ipairs(METERING_MODES) do
      local selected = state.metering_mode == item.id
      if selected then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x5CFFB6FF)
      else
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xD7DAE0FF)
      end

      if reaper.ImGui_Selectable(ctx, item.label .. "##meter_" .. item.id, selected) then
        state.metering_mode = item.id
      end

      reaper.ImGui_PopStyleColor(ctx, 1)
    end
    reaper.ImGui_EndPopup(ctx)
  end

  reaper.ImGui_PopStyleColor(ctx, style_color_count)
  if style_var_count > 0 then
    reaper.ImGui_PopStyleVar(ctx, style_var_count)
  end
end

local function DrawMeteringModeSelector(ctx, state, width)
  state.metering_mode = state.metering_mode or "dbfs"

  local label = METERING_MODE_LABELS[state.metering_mode] or "dBFS"
  local label_w = UIUtils.TextWidth(ctx, label)

  if width > 140 then
    reaper.ImGui_SameLine(ctx, math.max(0, width - label_w - 4))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x5CFFB6FF)
    reaper.ImGui_Text(ctx, label)
    reaper.ImGui_PopStyleColor(ctx, 1)
    DrawMeteringModePopup(ctx, state)
  end
end

local function MeterDt(state)
  local now = reaper.time_precise and reaper.time_precise() or os.clock()
  local last = state.level_meter_last_time or now
  state.level_meter_last_time = now
  return math.max(0.0, math.min(0.08, now - last))
end

local function FollowValue(current, target, dt, attack_tau, release_tau)
  current = current or target or 0.0
  target = target or 0.0
  local tau = target > current and (attack_tau or 0.001) or (release_tau or 0.22)
  if tau <= 0.001 then
    return target
  end
  local coeff = 1.0 - math.exp(-dt / tau)
  return current + (target - current) * coeff
end

local function UpdatePeakHold(state, value_key, timer_key, input, dt, hold_seconds, decay_tau)
  input = input or 0.0
  hold_seconds = hold_seconds or 1.5
  decay_tau = decay_tau or 0.75

  local held = state[value_key] or 0.0
  local timer = state[timer_key] or 0.0

  if input >= held then
    state[value_key] = input
    state[timer_key] = hold_seconds
    return input
  end

  timer = math.max(0.0, timer - dt)
  state[timer_key] = timer
  if timer > 0.0 then
    return held
  end

  local coeff = 1.0 - math.exp(-dt / decay_tau)
  held = held + (input - held) * coeff
  if math.abs(held - input) < 0.000001 then
    held = input
  end
  state[value_key] = math.max(input, held)
  return state[value_key]
end

function LevelPanel.Draw(ctx, state, analyzer, manager, small_font, small_font_size)
  local width = reaper.ImGui_GetContentRegionAvail(ctx)
  local full_height = 112
  local height, _, collapse_anim = UIUtils.GetCollapsiblePanelHeight(state, "level_loudness", full_height, 22)
  local draw_api = UIUtils.GetDrawApi()

  if not draw_api then
    return
  end

  local draw_list = draw_api.get_draw_list(ctx)
  local x, y = draw_api.get_cursor_pos(ctx)
  local right = x + width
  local bottom = y + height

  UIUtils.DrawInstrumentPanel(draw_list, draw_api, x, y, right, bottom, 6.0)
  UIUtils.DrawCollapsibleModuleLabel(ctx, draw_list, draw_api, x, y, "LEVEL & LOUDNESS", "level_loudness", state, small_font, small_font_size)

  -- Get active metering mode
  state.metering_mode = state.metering_mode or "dbfs"
  local mode = state.metering_mode
  local mode_label = METERING_MODE_LABELS[mode] or "dBFS"
  local compact_mode_labels = {
    spotify = "SPOT",
    youtube = "YT",
    apple = "APL",
    netflix = "NFLX",
    aes18 = "AES",
  }
  local title_w = UIUtils.TextWidth(ctx, "LEVEL & LOUDNESS")
  local mode_available_w = math.max(0, width - UIUtils.HEADER_LABEL_X - title_w - 26)
  if UIUtils.TextWidth(ctx, mode_label) > mode_available_w then
    mode_label = compact_mode_labels[mode] or mode_label:gsub("%s.*$", "")
  end
  local mode_label_w = UIUtils.TextWidth(ctx, mode_label)
  local mode_label_y = UIUtils.HeaderTextY(ctx, y, mode_label, small_font, small_font_size)
  local saved_x, saved_y = reaper.ImGui_GetCursorScreenPos(ctx)
  if mode_label_w <= mode_available_w and mode_available_w > 16 then
    reaper.ImGui_SetCursorScreenPos(ctx, math.floor(right - mode_label_w), mode_label_y)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x5CFFB6FF)
    if small_font then
      reaper.ImGui_PushFont(ctx, small_font, small_font_size)
    end
    reaper.ImGui_Text(ctx, mode_label)
    if small_font then
      reaper.ImGui_PopFont(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx, 1)
    DrawMeteringModePopup(ctx, state)
  end
  reaper.ImGui_SetCursorScreenPos(ctx, saved_x, saved_y)

  local body_clip = UIUtils.BeginAnimatedPanelBodyClip(ctx, x, y, right, bottom, collapse_anim)
  if not body_clip then
    draw_api.dummy(ctx, width, height)
    return
  end

  -- Fetch dynamic mode configuration from core config module
  local cfg = MeteringConfig.Get(mode)
  local is_loudness_mode = mode == "ebu" or STREAMING_TARGETS[mode] ~= nil
  local dt = MeterDt(state)

  -- Draw Stereo Peak & RMS Meter Bars
  local peak_l = analyzer.peak_l or 0
  local peak_r = analyzer.peak_r or 0
  local rms_l = analyzer.rms_l or 0
  local rms_r = analyzer.rms_r or 0

  -- Peak ballistics: Cox formula (instant attack, 150ms half-life decay)
  state.display_peak_l = state.display_peak_l or 0
  state.display_peak_r = state.display_peak_r or 0
  local pk_decay = 0.5 ^ (dt / 0.150)
  state.display_peak_l = math.max(peak_l, state.display_peak_l * pk_decay)
  state.display_peak_r = math.max(peak_r, state.display_peak_r * pk_decay)

  -- Smooth RMS Ballistics
  state.display_rms_l = state.display_rms_l or 0
  state.display_rms_r = state.display_rms_r or 0
  state.display_rms_l = FollowValue(state.display_rms_l, rms_l, dt, 0.08, 0.35)
  state.display_rms_r = FollowValue(state.display_rms_r, rms_r, dt, 0.08, 0.35)

  -- Auto-decay peak hold ballistics in seconds
  state.peak_hold_l = state.peak_hold_l or 0
  state.peak_hold_r = state.peak_hold_r or 0
  state.true_peak_hold_l = state.true_peak_hold_l or 0
  state.true_peak_hold_r = state.true_peak_hold_r or 0
  state.peak_hold_timer_l = state.peak_hold_timer_l or 0
  state.peak_hold_timer_r = state.peak_hold_timer_r or 0
  state.true_peak_hold_timer_l = state.true_peak_hold_timer_l or 0
  state.true_peak_hold_timer_r = state.true_peak_hold_timer_r or 0

  -- Freeze indicators: hipkval from JSFX (absolute max, never decays)
  state.peak_max_l = state.peak_max_l or 0
  state.peak_max_r = state.peak_max_r or 0
  local hipk_l = analyzer.hipkval_l or 0
  local hipk_r = analyzer.hipkval_r or 0
  state.peak_max_l = math.max(state.peak_max_l, hipk_l)
  state.peak_max_r = math.max(state.peak_max_r, hipk_r)

  UpdatePeakHold(state, "true_peak_hold_l", "true_peak_hold_timer_l", math.max(analyzer.true_peak_l or 0, peak_l), dt, 1.5, 0.75)
  UpdatePeakHold(state, "true_peak_hold_r", "true_peak_hold_timer_r", math.max(analyzer.true_peak_r or 0, peak_r), dt, 1.5, 0.75)

  -- Calculate normalized values for RMS, Peak, and Peak Hold based on active mode
  local rms_l_norm, rms_r_norm, peak_l_norm, peak_r_norm, hold_l_norm, hold_r_norm

  if is_loudness_mode then
    local val_m = analyzer.lufs_m or -150
    local val_s = analyzer.lufs_s or -150
    
    state.display_lufs_m = state.display_lufs_m or -150
    state.display_lufs_s = state.display_lufs_s or -150
    
    state.display_lufs_m = FollowValue(state.display_lufs_m, val_m, dt, 0.08, 0.45)
    state.display_lufs_s = FollowValue(state.display_lufs_s, val_s, dt, 0.18, 0.85)
    
    peak_l_norm = cfg.to_norm_db(state.display_lufs_m)
    peak_r_norm = cfg.to_norm_db(state.display_lufs_m)
    rms_l_norm = cfg.to_norm_db(state.display_lufs_s)
    rms_r_norm = cfg.to_norm_db(state.display_lufs_s)
    
    state.ebu_hold = state.ebu_hold or -150
    if state.display_lufs_m >= state.ebu_hold then
      state.ebu_hold = state.display_lufs_m
      state.ebu_hold_timer = hold_time
    else
      if state.ebu_hold_timer and state.ebu_hold_timer > 0 then
        state.ebu_hold_timer = math.max(0.0, state.ebu_hold_timer - dt)
      else
        state.ebu_hold = FollowValue(state.ebu_hold, -150, dt, 0.001, 4.0)
      end
    end
    
    hold_l_norm = cfg.to_norm_db(state.ebu_hold)
    hold_r_norm = cfg.to_norm_db(state.ebu_hold)
  else
    rms_l_norm = cfg.to_norm(state.display_rms_l)
    rms_r_norm = cfg.to_norm(state.display_rms_r)
    peak_l_norm = cfg.to_norm(state.display_peak_l)
    peak_r_norm = cfg.to_norm(state.display_peak_r)
    hold_l_norm = cfg.to_norm(state.peak_max_l)
    hold_r_norm = cfg.to_norm(state.peak_max_r)
  end

  -- Detect and hold persistent clip state based on active mode standards
  local true_peak_l_db = UIUtils.Db(analyzer.true_peak_l or 0)
  local true_peak_r_db = UIUtils.Db(analyzer.true_peak_r or 0)

  if is_loudness_mode then
    if cfg.is_clip(nil, true_peak_l_db) then
      state.clip_l = true
    end
    if cfg.is_clip(nil, true_peak_r_db) then
      state.clip_r = true
    end
  else
    if cfg.is_clip(peak_l) then
      state.clip_l = true
    end
    if cfg.is_clip(peak_r) then
      state.clip_r = true
    end
  end

  -- Shared columns layout geometry
  local pad_l = 12
  local pad_r = 14
  local label_col_w = 12
  local show_readouts = width >= 150
  local show_lamps = width >= 132
  local readout_col_w = show_readouts and (width < 178 and 38 or 48) or 0
  local lamp_col_w = show_lamps and 16 or 0
  local col_gap = 6
  local label_x = x + pad_l
  local meter_x = label_x + label_col_w + 6
  local lamp_x = show_lamps and (right - pad_r - lamp_col_w * 0.5) or (right - pad_r)
  local readout_right = show_readouts and (lamp_x - lamp_col_w * 0.5 - 6) or (right - pad_r)
  local readout_left = readout_right - readout_col_w
  local meter_right = readout_left - col_gap
  local meter_w = math.max(48, meter_right - meter_x)
  
  local bar_y_l = math.floor(y + 25)
  local bar_y_r = math.floor(y + 43)
  local bar_h = 8

  -- Draw DB scale ticks
  if draw_api.text and small_font and meter_w >= 82 then
    reaper.ImGui_PushFont(ctx, small_font, small_font_size)
    local ticks = cfg.ticks
    if meter_w < 124 and #ticks > 2 then
      ticks = { cfg.ticks[1], cfg.ticks[#cfg.ticks] }
    end
    for idx, tk in ipairs(ticks) do
      local norm_x = cfg.to_norm_db(tk)
      local tx = math.floor(meter_x + meter_w * norm_x)
      local lbl = tostring(tk)
      local lbl_w = UIUtils.TextWidth(ctx, lbl)
      
      local draw_x = tx
      if idx == 1 then
        draw_x = tx
      elseif idx == #ticks then
        draw_x = tx - lbl_w
      else
        draw_x = math.floor(tx - lbl_w * 0.5)
      end
      
      draw_api.text(draw_list, draw_x, bar_y_r + bar_h + 3, 0x5C626EFF, lbl)
    end
    reaper.ImGui_PopFont(ctx)
  end

  -- Delegate segmented meter rendering to UI/LevelBar module
  LevelBar.DrawSegmentedMeter(draw_list, draw_api, meter_x, bar_y_l, meter_w, bar_h, rms_l_norm, peak_l_norm, hold_l_norm, mode, cfg)
  LevelBar.DrawSegmentedMeter(draw_list, draw_api, meter_x, bar_y_r, meter_w, bar_h, rms_r_norm, peak_r_norm, hold_r_norm, mode, cfg)

  -- Print channel labels (L / R)
  if draw_api.text and small_font then
    reaper.ImGui_PushFont(ctx, small_font, small_font_size)

    local l_w = UIUtils.TextWidth(ctx, "L")
    local r_w = UIUtils.TextWidth(ctx, "R")
    local label_x_l = label_x + math.floor((12 - l_w) * 0.5)
    local label_x_r = label_x + math.floor((12 - r_w) * 0.5)

    draw_api.text(draw_list, label_x_l, bar_y_l - 3.0, 0xFFFFFFDD, "L")
    draw_api.text(draw_list, label_x_r, bar_y_r - 3.0, 0xFFFFFFDD, "R")
    
    local db_l_text, db_r_text
    local color_l, color_r
    
    if is_loudness_mode then
      db_l_text = cfg.format_db(state.display_lufs_m)
      db_r_text = cfg.format_db(state.display_lufs_m)
      color_l = cfg.label_color(state.display_lufs_m, state.clip_l)
      color_r = cfg.label_color(state.display_lufs_m, state.clip_r)
    else
      local db_l = UIUtils.Db(state.peak_max_l)
      local db_r = UIUtils.Db(state.peak_max_r)
      db_l_text = cfg.format_db(db_l)
      db_r_text = cfg.format_db(db_r)
      color_l = cfg.label_color(db_l, state.clip_l)
      color_r = cfg.label_color(db_r, state.clip_r)
    end
    
    if show_readouts then
      if readout_col_w < 42 then
        db_l_text = db_l_text:gsub("%s.*$", "")
        db_r_text = db_r_text:gsub("%s.*$", "")
      end
      local text_w_l = UIUtils.TextWidth(ctx, db_l_text)
      local text_w_r = UIUtils.TextWidth(ctx, db_r_text)
      local text_x_l = math.floor(readout_right - text_w_l)
      local text_x_r = math.floor(readout_right - text_w_r)
      draw_api.text(draw_list, text_x_l, bar_y_l - 4.0, color_l, db_l_text)
      draw_api.text(draw_list, text_x_r, bar_y_r - 4.0, color_r, db_r_text)
    end

    reaper.ImGui_PopFont(ctx)
  end

  if draw_api.text and show_lamps then
    -- Draw small round LED clip lamps
    local lamp_y_l = bar_y_l + 4.5
    local lamp_y_r = bar_y_r + 4.5
    local lamp_r = 3.5
    
    local now = reaper.time_precise()
    local pulse = 0.5 + 0.5 * math.sin(now * 8.0)
    
    if state.clip_l then
      local outer_r = lamp_r + 3.0 + 3.0 * pulse
      local outer_alpha = math.floor(8 + 16 * pulse)
      local outer_col = 0xFF000000 | outer_alpha
      
      local mid_r = lamp_r + 1.0 + 1.5 * pulse
      local mid_alpha = math.floor(20 + 35 * pulse)
      local mid_col = 0xFF3F3E00 | mid_alpha
      
      local r_val = math.floor(220 + 35 * pulse)
      local g_val = math.floor(60 + 30 * pulse)
      local b_val = math.floor(60 + 30 * pulse)
      local core_col = (r_val << 24) | (g_val << 16) | (b_val << 8) | 0xFF
      
      draw_api.circle_filled(draw_list, lamp_x, lamp_y_l, outer_r, outer_col)
      draw_api.circle_filled(draw_list, lamp_x, lamp_y_l, mid_r, mid_col)
      draw_api.circle_filled(draw_list, lamp_x, lamp_y_l, lamp_r, core_col)
      draw_api.circle_filled(draw_list, lamp_x - 1.0, lamp_y_l - 1.0, 1.0, 0xFFFFFFDD)
    else
      draw_api.circle_filled(draw_list, lamp_x, lamp_y_l, lamp_r + 1.5, 0x33353DFF)
      draw_api.circle_filled(draw_list, lamp_x, lamp_y_l, lamp_r + 0.5, 0x18191EFF)
      draw_api.circle_filled(draw_list, lamp_x, lamp_y_l, lamp_r, 0x0E0F12FF)
      draw_api.circle_filled(draw_list, lamp_x - 0.7, lamp_y_l - 0.7, 0.7, 0xFFFFFF1F)
    end
    
    if state.clip_r then
      local outer_r = lamp_r + 3.0 + 3.0 * pulse
      local outer_alpha = math.floor(8 + 16 * pulse)
      local outer_col = 0xFF000000 | outer_alpha
      
      local mid_r = lamp_r + 1.0 + 1.5 * pulse
      local mid_alpha = math.floor(20 + 35 * pulse)
      local mid_col = 0xFF3F3E00 | mid_alpha
      
      local r_val = math.floor(220 + 35 * pulse)
      local g_val = math.floor(60 + 30 * pulse)
      local b_val = math.floor(60 + 30 * pulse)
      local core_col = (r_val << 24) | (g_val << 16) | (b_val << 8) | 0xFF
      
      draw_api.circle_filled(draw_list, lamp_x, lamp_y_r, outer_r, outer_col)
      draw_api.circle_filled(draw_list, lamp_x, lamp_y_r, mid_r, mid_col)
      draw_api.circle_filled(draw_list, lamp_x, lamp_y_r, lamp_r, core_col)
      draw_api.circle_filled(draw_list, lamp_x - 1.0, lamp_y_r - 1.0, 1.0, 0xFFFFFFDD)
    else
      draw_api.circle_filled(draw_list, lamp_x, lamp_y_r, lamp_r + 1.5, 0x33353DFF)
      draw_api.circle_filled(draw_list, lamp_x, lamp_y_r, lamp_r + 0.5, 0x18191EFF)
      draw_api.circle_filled(draw_list, lamp_x, lamp_y_r, lamp_r, 0x0E0F12FF)
      draw_api.circle_filled(draw_list, lamp_x - 0.7, lamp_y_r - 0.7, 0.7, 0xFFFFFF1F)
    end
  end

  -- Native InvisibleButton for Peak & Clip Reset
  local cur_x, cur_y = reaper.ImGui_GetCursorScreenPos(ctx)
  reaper.ImGui_SetCursorScreenPos(ctx, meter_right + 4, bar_y_l - 4.0)
  if reaper.ImGui_InvisibleButton(ctx, "##peak_reset_trigger", math.max(10, right - meter_right - 8), 28) then
    manager.ResetAnalyzerMax(state)
    state.clip_l = false
    state.clip_r = false
    state.peak_hold_l = 0
    state.peak_hold_r = 0
    state.true_peak_hold_l = 0
    state.true_peak_hold_r = 0
    state.peak_hold_timer_l = 0
    state.peak_hold_timer_r = 0
    state.true_peak_hold_timer_l = 0
    state.true_peak_hold_timer_r = 0
    state.peak_max_l = 0
    state.peak_max_r = 0
    state.true_peak_max_l = 0
    state.true_peak_max_r = 0
    state.display_peak_l = 0
    state.display_peak_r = 0
    state.display_rms_l = 0
    state.display_rms_r = 0
    state.display_lufs_m = -150
    state.display_lufs_s = -150
    state.ebu_hold = -150
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
  end
  reaper.ImGui_SetCursorScreenPos(ctx, cur_x, cur_y)

  -- Draw Loudness Grid
  local lufs_y = y + 76
  local lufs_left = x + (width < 170 and 8 or 16)
  local lufs_right = right - (width < 170 and 8 or 16)
  local col_w = (lufs_right - lufs_left) / 3
  
  local cx1 = lufs_left + col_w * 0.5
  local cx2 = lufs_left + col_w * 1.5
  local cx3 = lufs_left + col_w * 2.5
  
  local function FitColumnText(text, max_w)
    text = tostring(text or "")
    if UIUtils.TextWidth(ctx, text) <= max_w then return text end
    local out = text:gsub("%s.*$", "")
    if out ~= text and UIUtils.TextWidth(ctx, out) <= max_w then return out end
    local dots = ".."
    while #out > 0 and UIUtils.TextWidth(ctx, out .. dots) > max_w do
      out = out:sub(1, #out - 1)
    end
    return out ~= "" and (out .. dots) or ""
  end

  local function DrawCenteredColumn(draw_list, cx, label, val_text, val_color, column_w)
    column_w = math.max(1, column_w or col_w)
    label = FitColumnText(label, column_w - 4)
    val_text = FitColumnText(val_text, column_w - 4)
    local lbl_w = UIUtils.TextWidth(ctx, label)
    local val_w = UIUtils.TextWidth(ctx, val_text)
    
    if column_w >= 32 then
      draw_api.text(draw_list, math.floor(cx - lbl_w * 0.5), lufs_y, 0x8C94A0FF, label)
      draw_api.text(draw_list, math.floor(cx - val_w * 0.5), lufs_y + 12, val_color, val_text)
    end
  end

  if draw_api.text then
    local col1_lbl, col1_val, col1_col
    local col2_lbl, col2_val, col2_col
    local col3_lbl, col3_val, col3_col
    local function PeakHeadroomText()
      local peak_db = UIUtils.Db(math.max(state.peak_max_l or 0, state.peak_max_r or 0))
      if peak_db <= -149 then return "-inf", 0x39FF88FF end
      local headroom = 0.0 - peak_db
      local color = headroom < 1.0 and 0xFF4F4EFF or (headroom < 3.0 and 0xE4BD13FF or 0x39FF88FF)
      return string.format("%.1f", headroom), color
    end
    
    if mode == "dbfs" then
      col1_lbl = "Peak"
      local peak_db = UIUtils.Db(math.max(state.peak_max_l or 0, state.peak_max_r or 0))
      col1_val = UIUtils.DbText(peak_db)
      col1_col = 0x4EFFB3FF
      
      col2_lbl = "RMS"
      local rms_db = UIUtils.Db(math.max(state.display_rms_l or 0, state.display_rms_r or 0))
      col2_val = UIUtils.DbText(rms_db)
      col2_col = 0x5CFFB6FF
      
      col3_lbl = "Head"
      col3_val, col3_col = PeakHeadroomText()
    elseif mode == "lufs" then
      col1_lbl = "M"
      col1_val = UIUtils.DbText(analyzer.lufs_m or -150)
      col1_col = 0x4EFFB3FF

      col2_lbl = "S"
      col2_val = UIUtils.DbText(analyzer.lufs_s or -150)
      col2_col = 0x5CFFB6FF

      col3_lbl = "I"
      col3_val = UIUtils.DbText(analyzer.lufs_i or -150)
      col3_col = 0x39FF88FF
    elseif STREAMING_TARGETS[mode] ~= nil then
      local target = cfg.target or -14.0

      col1_lbl = "I"
      col1_val = UIUtils.DbText(analyzer.lufs_i or -150)
      local delta_i = (analyzer.lufs_i or -150) - target
      col1_col = delta_i > 1.0 and 0xFF4F4EFF or (delta_i > 0.0 and 0xE4BD13FF or 0x4EFFB3FF)

      col2_lbl = "Diff"
      col2_val = analyzer.lufs_i and analyzer.lufs_i > -149 and string.format("%+.1f", delta_i) or "-inf"
      col2_col = delta_i > 1.0 and 0xFF4F4EFF or (delta_i > 0.0 and 0xE4BD13FF or 0x5CFFB6FF)

      col3_lbl = "Head"
      col3_val, col3_col = PeakHeadroomText()
    elseif mode == "k14" or mode == "k12" or mode == "k20" then
      local target = (mode == "k14" and -14.0 or (mode == "k12" and -12.0 or -20.0))

      local peak_db = UIUtils.Db(math.max(state.peak_max_l or 0, state.peak_max_r or 0))
      local rms_db = UIUtils.Db(math.max(state.display_rms_l or 0, state.display_rms_r or 0))
      local peak_dbr = peak_db - target
      local rms_dbr = rms_db - target
      local headroom = 0.0 - peak_db

      col1_lbl = "Peak"
      col1_val = peak_db <= -149 and "-inf" or string.format("%+.1f", peak_dbr)
      col1_col = peak_dbr > 2.0 and 0xFF4F4EFF or (peak_dbr > 0.0 and 0xE4BD13FF or 0x4EFFB3FF)

      col2_lbl = "RMS"
      col2_val = rms_db <= -149 and "-inf" or string.format("%+.1f", rms_dbr)
      col2_col = rms_dbr > 2.0 and 0xFF4F4EFF or (rms_dbr > 0.0 and 0xE4BD13FF or 0x5CFFB6FF)

      col3_lbl = "Head"
      col3_val = peak_db <= -149 and "-inf" or string.format("%.1f", headroom)
      col3_col = headroom < 1.0 and 0xFF4F4EFF or (headroom < 3.0 and 0xE4BD13FF or 0x39FF88FF)
    elseif mode == "ebu" then
      col1_lbl = "I"
      col1_val = UIUtils.DbText(analyzer.lufs_i or -150)
      local val_i = (analyzer.lufs_i or -150) + 23.0
      col1_col = val_i > 5.0 and 0xFF4F4EFF or (val_i > 0.0 and 0xE4BD13FF or 0x4EFFB3FF)

      col2_lbl = "Diff"
      col2_val = analyzer.lufs_i and analyzer.lufs_i > -149 and string.format("%+.1f", val_i) or "-inf"
      col2_col = val_i > 5.0 and 0xFF4F4EFF or (val_i > 0.0 and 0xE4BD13FF or 0x5CFFB6FF)
      
      col3_lbl = "Head"
      col3_val, col3_col = PeakHeadroomText()
    end
    
    if small_font then
      reaper.ImGui_PushFont(ctx, small_font, small_font_size)
    end

    DrawCenteredColumn(draw_list, cx1, col1_lbl, col1_val, col1_col, col_w)
    DrawCenteredColumn(draw_list, cx2, col2_lbl, col2_val, col2_col, col_w)
    DrawCenteredColumn(draw_list, cx3, col3_lbl, col3_val, col3_col, col_w)

    if small_font then
      reaper.ImGui_PopFont(ctx)
    end
  end

  UIUtils.EndAnimatedPanelBodyClip(ctx, body_clip)
  draw_api.dummy(ctx, width, height)
end

return LevelPanel
