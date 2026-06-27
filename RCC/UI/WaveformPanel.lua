local WaveformPanel = {}
local UIUtils = require("UIUtils")
local ImGui = nil

function WaveformPanel.SetImGui(imgui)
  ImGui = imgui
end

local COLOR = {
  green = 0x32A852FF,
  red = 0xD55353FF,
}

local function GetDrawApi()
  return UIUtils.GetDrawApi()
end

local function UpdateAnimation(state, target)
  state.waveform_anim = state.waveform_anim or target
  state.waveform_anim_time = state.waveform_anim_time or reaper.time_precise()

  local now = reaper.time_precise()
  local dt = math.max(0.0, math.min(0.05, now - state.waveform_anim_time))
  state.waveform_anim_time = now

  local speed = target > state.waveform_anim and 2.8 or 4.8
  state.waveform_anim = UIUtils.Approach(state.waveform_anim, target, speed, dt)
  return UIUtils.EaseOutCubic(state.waveform_anim)
end

local function WithAlpha(color, alpha)
  return (color & 0xFFFFFF00) | math.max(0, math.min(255, math.floor(alpha)))
end

local SPEED_MODES = {
  { label = "FAST", compact = "F", divisor = 16 },
  { label = "NAT", compact = "N", divisor = 64 },
  { label = "SLOW", compact = "S", divisor = 192 },
}

local function ActiveSpeedModeIndex(state)
  local divisor = state.waveform_divisor or 64
  local best_index = 1
  local best_distance = math.huge

  for index, mode in ipairs(SPEED_MODES) do
    local distance = math.abs(divisor - mode.divisor)
    if distance < best_distance then
      best_distance = distance
      best_index = index
    end
  end

  return best_index
end

local function DrawHeaderControls(ctx, draw_list, draw_api, x, y, right, width, state, small_font, small_font_size)
  if not draw_api.text or not small_font then
    return
  end

  local get_csp = ImGui and ImGui.GetCursorScreenPos or reaper.ImGui_GetCursorScreenPos
  local set_csp = ImGui and ImGui.SetCursorScreenPos or reaper.ImGui_SetCursorScreenPos
  local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
  local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
  local inv_btn = ImGui and ImGui.InvisibleButton or reaper.ImGui_InvisibleButton

  local saved_x, saved_y = get_csp(ctx)
  push_f(ctx, small_font, small_font_size)

  local title_w = UIUtils.TextWidth(ctx, "WAVEFORM")
  local title_right = x + UIUtils.HEADER_LABEL_X + title_w + 10
  local available_right = right - 7
  local available_w = math.max(0, available_right - title_right)
  local state_label = state.waveform_expanded and "STEREO" or "SUM"
  local state_w = UIUtils.TextWidth(ctx, state_label)
  local mode_y = UIUtils.HeaderTextY(ctx, y, "FAST", small_font, small_font_size)
  local active_index = ActiveSpeedModeIndex(state)

  local function measure(labels)
    local total = 0
    for index, label in ipairs(labels) do
      total = total + math.max(10, UIUtils.TextWidth(ctx, label) + 4)
      if index > 1 then
        total = total + 4
      end
    end
    return total
  end

  local labels = { SPEED_MODES[1].label, SPEED_MODES[2].label, SPEED_MODES[3].label }
  local modes_w = measure(labels)
  if modes_w > available_w and width < 245 then
    labels = { SPEED_MODES[1].compact, SPEED_MODES[2].compact, SPEED_MODES[3].compact }
    modes_w = measure(labels)
  end

  local show_state = modes_w + state_w + 8 <= available_w
  local can_show_modes = modes_w <= available_w

  if can_show_modes then
    local mode_x = math.floor(available_right - modes_w)
    if show_state then
      draw_api.text(draw_list, math.floor(mode_x - state_w - 8), mode_y, 0x8C94A056, state_label)
    end

    for index, mode in ipairs(SPEED_MODES) do
      local label = labels[index]
      local item_w = math.max(10, UIUtils.TextWidth(ctx, label) + 4)
      local active = index == active_index
      draw_api.text(draw_list, mode_x + 2, mode_y, active and 0x5CFFB6CC or 0x8C94A056, label)
      set_csp(ctx, mode_x, y + 1)
      if inv_btn(ctx, "##waveform_speed_" .. mode.label, item_w, 17) then
        state.waveform_divisor = mode.divisor
      end
      mode_x = mode_x + item_w + 4
    end
  else
    local mode = SPEED_MODES[active_index]
    local label = mode.compact
    local item_w = math.max(10, UIUtils.TextWidth(ctx, label) + 4)
    if item_w <= available_w then
      local mode_x = math.floor(available_right - item_w)
      draw_api.text(draw_list, mode_x + 2, mode_y, 0x5CFFB6CC, label)
      set_csp(ctx, mode_x, y + 1)
      if inv_btn(ctx, "##waveform_speed_cycle", item_w, 17) then
        local next_index = active_index % #SPEED_MODES + 1
        state.waveform_divisor = SPEED_MODES[next_index].divisor
      end
    end
  end

  pop_f(ctx)
  set_csp(ctx, saved_x, saved_y)
end

local function DrawLane(ctx, draw_list, draw_api, waveform, start_index, count, cfg, x, y, right, bottom, label, color, small_font, small_font_size, alpha_scale, vertical_zoom)
  alpha_scale = alpha_scale or 1.0
  vertical_zoom = vertical_zoom or 1.0
  if alpha_scale <= 0.01 then
    return
  end

  local plot_w = math.max(1, right - x)
  local plot_h = math.max(1, bottom - y)
  local center_y = y + plot_h * 0.5
  local visible_count = math.min(count, cfg.points)

  draw_api.line(draw_list, x, center_y, right, center_y, WithAlpha(0x28493600, 120 * alpha_scale), 1)
  draw_api.line(draw_list, x, y + plot_h * 0.25, right, y + plot_h * 0.25, WithAlpha(0x1C1E2400, 180 * alpha_scale), 1)
  draw_api.line(draw_list, x, y + plot_h * 0.75, right, y + plot_h * 0.75, WithAlpha(0x1C1E2400, 180 * alpha_scale), 1)

  for idx = 1, 3 do
    local gx = math.floor(x + plot_w * idx * 0.25)
    draw_api.line(draw_list, gx, y, gx, bottom, WithAlpha(0x1F202500, 160 * alpha_scale), 1)
  end

  if visible_count > 1 then
    local last_px = nil
    local last_min_y = nil
    local last_max_y = nil
    local amp_scale = plot_h * 0.48 * vertical_zoom

    local end_index = math.min(count, start_index + visible_count - 1)
    for i = start_index, end_index do
      local pt = waveform[i]
      local min_val = pt and pt.min or 0
      local max_val = pt and pt.max or 0
      local norm_x = (i - start_index) / math.max(1, visible_count - 1)
      local px = math.floor(x + plot_w * norm_x)
      local min_off = math.max(-amp_scale, math.min(amp_scale, min_val * amp_scale))
      local max_off = math.max(-amp_scale, math.min(amp_scale, max_val * amp_scale))
      local min_y = math.max(y + 1, math.min(bottom - 1, center_y - min_off))
      local max_y = math.max(y + 1, math.min(bottom - 1, center_y - max_off))
      local top_y = math.min(min_y, max_y)
      local bot_y = math.max(min_y, max_y)

      if math.abs(bot_y - top_y) > 0.4 then
        local body_alpha = math.min(104, math.max(16, math.floor(18 + math.abs(bot_y - top_y) * 1.2)))
        draw_api.line(draw_list, px, top_y, px, bot_y, WithAlpha(color, body_alpha * alpha_scale), 1.0)
      end
      if last_px then
        draw_api.line(draw_list, last_px, last_max_y + 1, px, max_y + 1, WithAlpha(0x06100B00, 168 * alpha_scale), 2.0)
        draw_api.line(draw_list, last_px, last_min_y + 1, px, min_y + 1, WithAlpha(0x06100B00, 168 * alpha_scale), 2.0)
        draw_api.line(draw_list, last_px, last_max_y, px, max_y, WithAlpha(color, 221 * alpha_scale), 1.05)
        draw_api.line(draw_list, last_px, last_min_y, px, min_y, WithAlpha(color, 221 * alpha_scale), 1.05)
      end

      last_px = px
      last_min_y = min_y
      last_max_y = max_y
    end
  end

  if draw_api.text and small_font then
    local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
    local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
    push_f(ctx, small_font, small_font_size)
    if label and label ~= "" then
      draw_api.text(draw_list, x + 1, y + 1, WithAlpha(0x8C94A000, 122 * alpha_scale), label)
    end
    pop_f(ctx)
  end
end

function WaveformPanel.Draw(ctx, state, analyzer, small_font, small_font_size)
  local get_avail = ImGui and ImGui.GetContentRegionAvail or reaper.ImGui_GetContentRegionAvail
  local width = get_avail(ctx)
  state.waveform_expanded = state.waveform_expanded or false
  local anim = UpdateAnimation(state, state.waveform_expanded and 1.0 or 0.0)
  local full_height = math.floor(108 + (212 - 108) * anim + 0.5)
  local height, _, collapse_anim = UIUtils.GetCollapsiblePanelHeight(state, "waveform", full_height, 22)
  local draw_api = GetDrawApi()

  if not draw_api then
    return
  end

  local draw_list = draw_api.get_draw_list(ctx)
  local x, y = draw_api.get_cursor_pos(ctx)
  local right = x + width
  local bottom = y + height
  local rounding = 6.0

  UIUtils.DrawInstrumentPanel(draw_list, draw_api, x, y, right, bottom, rounding)

  local plot_x = x + 7
  local plot_y = y + 27
  local plot_right = right - 7
  local plot_bottom = bottom - 15
  local plot_w = math.max(1, plot_right - plot_x)
  local plot_h = math.max(1, plot_bottom - plot_y)
  local center_y = plot_y + plot_h * 0.5

  if state.clip_l or state.clip_r then
    local pulse = 0.5 + 0.5 * math.sin(reaper.time_precise() * 7.0)
    local red_base = COLOR.red & 0xFFFFFF00
    draw_api.rect(draw_list, x + 1, y + 1, right - 1, bottom - 1, red_base | math.floor(25 + 55 * pulse), rounding, nil, 1.2)
  end

  UIUtils.DrawCollapsibleModuleLabel(ctx, draw_list, draw_api, x, y, "WAVEFORM", "waveform", state, small_font, small_font_size)
  DrawHeaderControls(ctx, draw_list, draw_api, x, y, right, width, state, small_font, small_font_size)

  local body_clip = UIUtils.BeginAnimatedPanelBodyClip(ctx, x, y, right, bottom, collapse_anim)
  if not body_clip then
    draw_api.dummy(ctx, width, height)
    return
  end

  local set_csp = ImGui and ImGui.SetCursorScreenPos or reaper.ImGui_SetCursorScreenPos
  local inv_btn = ImGui and ImGui.InvisibleButton or reaper.ImGui_InvisibleButton
  local is_hov = ImGui and ImGui.IsItemHovered or reaper.ImGui_IsItemHovered
  local set_mc = ImGui and ImGui.SetMouseCursor or reaper.ImGui_SetMouseCursor
  local mc_hand = ImGui and ImGui.MouseCursor_Hand or reaper.ImGui_MouseCursor_Hand

  local btn_w = plot_right - plot_x
  local btn_h = plot_bottom - plot_y
  if collapse_anim > 0.96 and btn_w > 0.001 and btn_h > 0.001 then
    set_csp(ctx, plot_x, plot_y)
    if inv_btn(ctx, "##waveform_expand_toggle", btn_w, btn_h) then
      state.waveform_expanded = not state.waveform_expanded
    end
    if is_hov(ctx) then
      set_mc(ctx, mc_hand())
    end
  end
  set_csp(ctx, x, y)

  -- Dynamic speed and time window calculation
  state.waveform_divisor = state.waveform_divisor or 64
  local divisor = state.waveform_divisor
  local srate = analyzer.sample_rate or 44100
  local duration_sec = (384 * divisor) / srate
  local duration_str
  if duration_sec >= 1.0 then
    duration_str = string.format("%.1fs", duration_sec)
  else
    duration_str = string.format("%.0fms", duration_sec * 1000)
  end

  local cfg = {
    points = 384,
    divisor = divisor,
    duration = duration_str,
  }

  if reaper.gmem_attach and reaper.gmem_write and state.waveform_sent_divisor ~= cfg.divisor then
    reaper.gmem_attach("RCC_ANALYZER_TAP")
    reaper.gmem_write(150, cfg.divisor)
    state.waveform_sent_divisor = cfg.divisor
  end

  local waveform = analyzer.waveform or {}
  local waveform_l = analyzer.waveform_l or {}
  local waveform_r = analyzer.waveform_r or {}
  local count = #waveform
  local visible_count = math.min(count, cfg.points)
  local start_index = math.max(1, count - visible_count + 1)

  local sum_alpha = 1.0 - math.max(0.0, math.min(1.0, anim * 0.95))
  local stereo_alpha = math.max(0.0, math.min(1.0, (anim - 0.18) / 0.82))

  -- Apply protection clip rect to prevent line bleeding outside bounds
  local push_cr = ImGui and ImGui.PushClipRect or reaper.ImGui_PushClipRect
  local pop_cr = ImGui and ImGui.PopClipRect or reaper.ImGui_PopClipRect
  if push_cr then
    push_cr(ctx, plot_x, plot_y, plot_right, plot_bottom, true)
  end

  state.waveform_vzoom = state.waveform_vzoom or 1.0
  local vzoom = state.waveform_vzoom

  DrawLane(ctx, draw_list, draw_api, waveform, start_index, count, cfg, plot_x, plot_y, plot_right, plot_bottom, "", 0x5CFFB600, small_font, small_font_size, sum_alpha, vzoom)

  local gap = 7
  local lane_h = (plot_h - gap) * 0.5
  local l_bottom = plot_y + lane_h
  local r_top = l_bottom + gap
  if stereo_alpha > 0.01 then
    draw_api.line(draw_list, plot_x, l_bottom + gap * 0.5, plot_right, l_bottom + gap * 0.5, WithAlpha(0x24252A00, 255 * stereo_alpha), 1)
    DrawLane(ctx, draw_list, draw_api, waveform_l, start_index, count, cfg, plot_x, plot_y, plot_right, l_bottom, "", 0x5CFFB600, small_font, small_font_size, stereo_alpha, vzoom)
    DrawLane(ctx, draw_list, draw_api, waveform_r, start_index, count, cfg, plot_x, r_top, plot_right, plot_bottom, "", 0x44D98F00, small_font, small_font_size, stereo_alpha, vzoom)
  end

  if pop_cr then
    pop_cr(ctx)
  end

  if draw_api.text and small_font then
    local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
    local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
    push_f(ctx, small_font, small_font_size)
    draw_api.text(draw_list, plot_x, bottom - 12, 0x6A727EFF, "-" .. cfg.duration)
    draw_api.text(draw_list, math.floor(plot_x + plot_w * 0.5 - 3), bottom - 12, 0x4A505AFF, "0")
    draw_api.text(draw_list, right - 22, bottom - 12, 0x6A727EFF, "now")
    pop_f(ctx)
  end

  UIUtils.EndAnimatedPanelBodyClip(ctx, body_clip)
  draw_api.dummy(ctx, width, height)

  if collapse_anim <= 0.96 then
    return
  end

  local push_iw = ImGui and ImGui.PushItemWidth or reaper.ImGui_PushItemWidth
  local pop_iw = ImGui and ImGui.PopItemWidth or reaper.ImGui_PopItemWidth
  local push_sc = ImGui and ImGui.PushStyleColor or reaper.ImGui_PushStyleColor
  local pop_sc = ImGui and ImGui.PopStyleColor or reaper.ImGui_PopStyleColor
  local push_sv = ImGui and ImGui.PushStyleVar or reaper.ImGui_PushStyleVar
  local pop_sv = ImGui and ImGui.PopStyleVar or reaper.ImGui_PopStyleVar
  local col_frame = ImGui and ImGui.Col_FrameBg or reaper.ImGui_Col_FrameBg
  local col_frame_h = ImGui and ImGui.Col_FrameBgHovered or reaper.ImGui_Col_FrameBgHovered
  local col_frame_a = ImGui and ImGui.Col_FrameBgActive or reaper.ImGui_Col_FrameBgActive
  local col_slider = ImGui and ImGui.Col_SliderGrab or reaper.ImGui_Col_SliderGrab
  local col_slider_a = ImGui and ImGui.Col_SliderGrabActive or reaper.ImGui_Col_SliderGrabActive
  local col_border = ImGui and ImGui.Col_Border or reaper.ImGui_Col_Border
  local col_text = ImGui and ImGui.Col_Text or reaper.ImGui_Col_Text
  local sv_fround = ImGui and ImGui.StyleVar_FrameRounding or reaper.ImGui_StyleVar_FrameRounding
  local sv_ground = ImGui and ImGui.StyleVar_GrabRounding or reaper.ImGui_StyleVar_GrabRounding
  local sv_fborder = ImGui and ImGui.StyleVar_FrameBorderSize or reaper.ImGui_StyleVar_FrameBorderSize
  local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
  local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont

  push_iw(ctx, width)
  push_sc(ctx, col_frame(), UIUtils.STYLE.panel_bg)
  push_sc(ctx, col_frame_h(), UIUtils.STYLE.button_hover)
  push_sc(ctx, col_frame_a(), UIUtils.STYLE.button_pressed)
  push_sc(ctx, col_slider(), (UIUtils.STYLE.accent & 0xFFFFFF00) | 0xD0)
  push_sc(ctx, col_slider_a(), UIUtils.STYLE.accent)
  push_sc(ctx, col_border(), UIUtils.STYLE.panel_border)
  push_sc(ctx, col_text(), (UIUtils.STYLE.text_dim & 0xFFFFFF00) | 0x80)
  push_sv(ctx, sv_fround(), 6.0)
  push_sv(ctx, sv_ground(), 6.0)
  push_sv(ctx, sv_fborder(), 1.0)

  if small_font then
    push_f(ctx, small_font, small_font_size)
  end
  local changed, new_divisor = UIUtils.SliderIntReset(ctx, "##waveform_speed_slider", state.waveform_divisor, 8, 512, "Waveform Speed  %d", 64)
  if small_font then
    pop_f(ctx)
  end

  pop_sv(ctx, 3)
  pop_sc(ctx, 7)
  pop_iw(ctx)

  if changed then
    state.waveform_divisor = new_divisor
  end

  push_iw(ctx, width)
  push_sc(ctx, col_frame(), UIUtils.STYLE.panel_bg)
  push_sc(ctx, col_frame_h(), UIUtils.STYLE.button_hover)
  push_sc(ctx, col_frame_a(), UIUtils.STYLE.button_pressed)
  push_sc(ctx, col_slider(), (UIUtils.STYLE.accent & 0xFFFFFF00) | 0xD0)
  push_sc(ctx, col_slider_a(), UIUtils.STYLE.accent)
  push_sc(ctx, col_border(), UIUtils.STYLE.panel_border)
  push_sc(ctx, col_text(), (UIUtils.STYLE.text_dim & 0xFFFFFF00) | 0x80)
  push_sv(ctx, sv_fround(), 6.0)
  push_sv(ctx, sv_ground(), 6.0)
  push_sv(ctx, sv_fborder(), 1.0)

  if small_font then
    push_f(ctx, small_font, small_font_size)
  end
  local vzoom_changed, new_vzoom = UIUtils.SliderDoubleReset(ctx, "##waveform_vzoom", state.waveform_vzoom, 1.0, 10.0, "Vertical Zoom  %.1fx", 1.0)
  if small_font then
    pop_f(ctx)
  end

  pop_sv(ctx, 3)
  pop_sc(ctx, 7)
  pop_iw(ctx)

  if vzoom_changed then
    state.waveform_vzoom = new_vzoom
  end
end

return WaveformPanel
