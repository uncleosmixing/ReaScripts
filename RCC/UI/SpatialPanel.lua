local SpatialPanel = {}
local UIUtils = require("UIUtils")
local ImGui = nil

function SpatialPanel.SetImGui(imgui)
  ImGui = imgui
end

local HEATMAP_SIZE = 32

local function UpdateExpandAnimation(state, target)
  state.spatial_expand_anim = state.spatial_expand_anim or target
  state.spatial_expand_anim_time = state.spatial_expand_anim_time or reaper.time_precise()

  local now = reaper.time_precise()
  local dt = math.max(0.0, math.min(0.05, now - state.spatial_expand_anim_time))
  state.spatial_expand_anim_time = now

  local speed = target > state.spatial_expand_anim and 2.8 or 4.8
  state.spatial_expand_anim = UIUtils.Approach(state.spatial_expand_anim, target, speed, dt)
  return UIUtils.EaseOutCubic(state.spatial_expand_anim)
end

local function DrawSpatialContextMenu(ctx, state)
  local begin_popup = ImGui and ImGui.BeginPopupContextItem or reaper.ImGui_BeginPopupContextItem
  local end_popup = ImGui and ImGui.EndPopup or reaper.ImGui_EndPopup
  if not begin_popup or not begin_popup(ctx, "##spatial_context_menu") then
    return
  end

  local selectable = ImGui and ImGui.Selectable or reaper.ImGui_Selectable
  local checkbox = ImGui and ImGui.Checkbox or reaper.ImGui_Checkbox

  local function PushAccent(active)
    if active then
      local push_sc = ImGui and ImGui.PushStyleColor or reaper.ImGui_PushStyleColor
      local col_txt = ImGui and ImGui.Col_Text or reaper.ImGui_Col_Text
      push_sc(ctx, col_txt(), 0x5CFFB6FF)
    end
  end
  local function PopAccent(active)
    if active then
      local pop_sc = ImGui and ImGui.PopStyleColor or reaper.ImGui_PopStyleColor
      pop_sc(ctx, 1)
    end
  end

  state.spatial_display_mode = state.spatial_display_mode or "points"
  local pts_sel = state.spatial_display_mode == "points"
  PushAccent(pts_sel)
  if selectable and selectable(ctx, "Display: Points", pts_sel) then
    state.spatial_display_mode = "points"
  end
  PopAccent(pts_sel)

  local heat_sel = state.spatial_display_mode == "heatmap"
  PushAccent(heat_sel)
  if selectable and selectable(ctx, "Display: Heatmap", heat_sel) then
    state.spatial_display_mode = "heatmap"
  end
  PopAccent(heat_sel)

  if selectable then selectable(ctx, "---", false) end

  state.spatial_show_grid = state.spatial_show_grid == nil and true or state.spatial_show_grid
  state.spatial_show_labels = state.spatial_show_labels == nil and true or state.spatial_show_labels
  state.spatial_show_corr = state.spatial_show_corr == nil and true or state.spatial_show_corr
  state.spatial_show_width = state.spatial_show_width == nil and true or state.spatial_show_width

  local ch
  if checkbox then ch = checkbox(ctx, "Show Grid", state.spatial_show_grid) end
  if ch then state.spatial_show_grid = not state.spatial_show_grid end

  ch = nil
  if checkbox then ch = checkbox(ctx, "Show Labels", state.spatial_show_labels) end
  if ch then state.spatial_show_labels = not state.spatial_show_labels end

  ch = nil
  if checkbox then ch = checkbox(ctx, "Show Correlation", state.spatial_show_corr) end
  if ch then state.spatial_show_corr = not state.spatial_show_corr end

  ch = nil
  if checkbox then ch = checkbox(ctx, "Show Width", state.spatial_show_width) end
  if ch then state.spatial_show_width = not state.spatial_show_width end

  if selectable then selectable(ctx, "---", false) end

  local reset_sel = false
  PushAccent(reset_sel)
  if selectable and selectable(ctx, "Reset All", false) then
    state.spatial_expanded = false
    state.spatial_display_mode = "points"
    state.spatial_show_grid = true
    state.spatial_show_labels = true
    state.spatial_show_corr = true
    state.spatial_show_width = true
    state.spatial_trail_length = 1.6
    state.spatial_gain = 1.0
    state.spatial_corr_peak = 0
  end
  PopAccent(reset_sel)

  end_popup(ctx)
end

local function DrawGoniometerHeatmap(ctx, draw_list, draw_api, scope, center_x, center_y, radius, gain, trail_length)
  local grid = {}
  for i = 1, HEATMAP_SIZE * HEATMAP_SIZE do
    grid[i] = 0
  end

  local max_hits = 1
  for index = 1, #scope do
    local point = scope[index]
    local side = (point.x or 0) * gain
    local mid = (point.y or 0) * gain
    local amp = math.sqrt(side * side + mid * mid)
    if amp > 1.0 then
      side = side / amp
      mid = mid / amp
    end

    local gx = math.floor((side + 1.0) * 0.5 * (HEATMAP_SIZE - 1) + 0.5)
    local gy = math.floor((1.0 - mid) * 0.5 * (HEATMAP_SIZE - 1) + 0.5)
    gx = math.max(0, math.min(HEATMAP_SIZE - 1, gx))
    gy = math.max(0, math.min(HEATMAP_SIZE - 1, gy))
    local idx = gy * HEATMAP_SIZE + gx + 1
    grid[idx] = grid[idx] + 1
    if grid[idx] > max_hits then max_hits = grid[idx] end
  end

  local cell_w = (radius * 2) / HEATMAP_SIZE
  local cell_h = (radius * 2) / HEATMAP_SIZE

  for gy = 0, HEATMAP_SIZE - 1 do
    for gx = 0, HEATMAP_SIZE - 1 do
      local idx = gy * HEATMAP_SIZE + gx + 1
      local hits = grid[idx]
      if hits > 0 then
        local intensity = hits / math.max(1, max_hits)
        local r, g, b
        if intensity < 0.25 then
          r = 28; g = 60 + math.floor(intensity * 4 * 80); b = 42
        elseif intensity < 0.5 then
          local t = (intensity - 0.25) * 4
          r = math.floor(28 + t * 168); g = math.floor(140 + t * 10); b = math.floor(42 - t * 14)
        elseif intensity < 0.75 then
          local t = (intensity - 0.5) * 4
          r = math.floor(196 + t * 0); g = math.floor(150 - t * 80); b = math.floor(28 + t * 0)
        else
          local t = (intensity - 0.75) * 4
          r = math.floor(196 - t * 46); g = math.floor(70 - t * 34); b = math.floor(28 + t * 50)
        end
        local alpha = math.floor(40 + intensity * 180)
        local px = center_x - radius + gx * cell_w
        local py = center_y - radius + gy * cell_h
        draw_api.rect_filled(draw_list, px, py, px + cell_w + 0.5, py + cell_h + 0.5,
          (r << 24) | (g << 16) | (b << 8) | alpha, 0)
      end
    end
  end
end

function SpatialPanel.Draw(ctx, state, analyzer, small_font, small_font_size)
  local get_avail = ImGui and ImGui.GetContentRegionAvail or reaper.ImGui_GetContentRegionAvail
  local width = get_avail(ctx)
  state.spatial_expanded = state.spatial_expanded or false
  state.spatial_trail_length = state.spatial_trail_length or 1.6
  state.spatial_gain = state.spatial_gain or 1.0
  state.spatial_show_grid = state.spatial_show_grid == nil and true or state.spatial_show_grid
  state.spatial_show_labels = state.spatial_show_labels == nil and true or state.spatial_show_labels
  state.spatial_show_corr = state.spatial_show_corr == nil and true or state.spatial_show_corr
  state.spatial_show_width = state.spatial_show_width == nil and true or state.spatial_show_width
  state.spatial_display_mode = state.spatial_display_mode or "points"

  local anim = UpdateExpandAnimation(state, state.spatial_expanded and 1.0 or 0.0)
  local expanded_height = math.floor(200 + (320 - 200) * anim + 0.5)
  local height, _, collapse_anim = UIUtils.GetCollapsiblePanelHeight(state, "spatial_analyzer", expanded_height, 22)
  local draw_api = UIUtils.GetDrawApi()

  if not draw_api then
    return
  end

  local draw_list = draw_api.get_draw_list(ctx)
  local x, y = draw_api.get_cursor_pos(ctx)
  local right = x + width
  local bottom = y + height

  UIUtils.DrawInstrumentPanel(draw_list, draw_api, x, y, right, bottom, 6.0)
  UIUtils.DrawCollapsibleModuleLabel(ctx, draw_list, draw_api, x, y, "SPATIAL ANALYZER", "spatial_analyzer", state, small_font, small_font_size)

  local body_clip = UIUtils.BeginAnimatedPanelBodyClip(ctx, x, y, right, bottom, collapse_anim)
  if not body_clip then
    reaper.ImGui_SetCursorScreenPos(ctx, x, y)
    draw_api.dummy(ctx, width, height)
    return
  end

  local radius = math.floor(48 + (90 - 48) * anim + 0.5)
  local center_x = x + width * 0.5
  local center_y = y + 22 + radius + 8
  local scope = analyzer.scope or {}
  local gain = state.spatial_gain
  local trail_length = state.spatial_trail_length

  if state.spatial_show_grid then
    draw_api.line(draw_list, center_x, center_y - radius * 1.1, center_x, center_y + radius * 1.1, 0x2A2C30FF, 1)
    draw_api.line(draw_list, center_x - radius * 1.1, center_y, center_x + radius * 1.1, center_y, 0x2A2C30FF, 1)
    draw_api.line(draw_list, center_x - radius * 0.9, center_y - radius * 0.9, center_x + radius * 0.9, center_y + radius * 0.9, 0x363A42FF, 1)
    draw_api.line(draw_list, center_x + radius * 0.9, center_y - radius * 0.9, center_x - radius * 0.9, center_y + radius * 0.9, 0x363A42FF, 1)
    if draw_api.circle then
      draw_api.circle(draw_list, center_x, center_y, radius, 0x3A3E48FF, 32, 1.0)
      draw_api.circle(draw_list, center_x, center_y, radius * 0.5, 0x26292FFF, 32, 1.0)
    end
  end

  if state.spatial_show_labels and draw_api.text then
    local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
    local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
    local calc_t = ImGui and ImGui.CalcTextSize or reaper.ImGui_CalcTextSize
    if small_font then push_f(ctx, small_font, small_font_size) end

    local label_color = 0x8C94A0DD
    local side_color = 0x6A727EDD
    local label_h = small_font_size or 10
    if calc_t then
      local _, measured_h = calc_t(ctx, "M")
      if measured_h and measured_h > 0 then label_h = measured_h end
    end

    local function DrawCenteredLabel(label, lx, ly, color)
      local lw = UIUtils.TextWidth(ctx, label)
      draw_api.text(draw_list, math.floor(lx - lw * 0.5 + 0.5), math.floor(ly - label_h * 0.5 + 0.5), color, label)
    end

    local label_offset = radius + 15
    local diagonal_label_offset = radius * 0.72
    local diagonal_label_lift = 8

    DrawCenteredLabel("M", center_x, center_y - radius - 7, label_color)
    DrawCenteredLabel("L", center_x - diagonal_label_offset, center_y - diagonal_label_offset - diagonal_label_lift, label_color)
    DrawCenteredLabel("R", center_x + diagonal_label_offset, center_y - diagonal_label_offset - diagonal_label_lift, label_color)
    DrawCenteredLabel("S", center_x - label_offset, center_y, side_color)
    DrawCenteredLabel("S", center_x + label_offset, center_y, side_color)

    if small_font then pop_f(ctx) end
  end

  if state.spatial_display_mode == "heatmap" then
    DrawGoniometerHeatmap(ctx, draw_list, draw_api, scope, center_x, center_y, radius, gain, trail_length)
  else
    for index = 1, #scope do
      local point = scope[index]
      local side = (point.x or 0) * gain
      local mid = (point.y or 0) * gain
      local amp = math.sqrt(side * side + mid * mid)
      if amp > 1.0 then
        side = side / amp
        mid = mid / amp
        amp = 1.0
      end
      local px = center_x - side * radius
      local py = center_y - mid * radius
      local age = index / math.max(1, #scope)
      local alpha = math.floor(255 * (age ^ trail_length) * math.min(1.0, amp * 6.0))
      if alpha > 15 then
        local color = (0x39 << 24) | (0xFF << 16) | (0x88 << 8) | alpha
        if draw_api.circle_filled then
          draw_api.circle_filled(draw_list, px, py, 1.25, color)
        else
          draw_api.rect_filled(draw_list, px - 1, py - 1, px + 1, py + 1, color)
        end
      end
    end
  end

  local corr = math.max(-1.0, math.min(1.0, analyzer.correlation or 0))

  state.spatial_corr_peak = state.spatial_corr_peak or 0
  if math.abs(corr) > math.abs(state.spatial_corr_peak) then
    state.spatial_corr_peak = corr
  else
    state.spatial_corr_peak = state.spatial_corr_peak * 0.995
  end

  local corr_section_top = center_y + radius + 16
  local corr_label_y = corr_section_top

  if state.spatial_show_corr then
    local bar_x = x + 24
    local bar_w = width - 48
    local bar_right = bar_x + bar_w
    local bar_y = math.floor(corr_label_y + 16)
    local mid_x = math.floor(bar_x + bar_w * 0.5)

    draw_api.rect_filled(draw_list, bar_x, bar_y - 2, mid_x, bar_y + 2, 0x4A1E1EFF, 0)
    draw_api.rect_filled(draw_list, mid_x, bar_y - 2, bar_right, bar_y + 2, 0x1E4A28FF, 0)
    draw_api.line(draw_list, mid_x, bar_y - 5, mid_x, bar_y + 5, 0x555555FF, 1)

    local corr_x = bar_x + bar_w * ((corr + 1.0) * 0.5)
    local color_theme = corr < -0.15 and 0xFF4F4EFF or 0x4EFFB3FF

    draw_api.rect_filled(draw_list, corr_x - 3, bar_y - 8, corr_x + 3, bar_y + 8, (color_theme & 0xFFFFFF00) | 0x33, 2.0)
    draw_api.rect_filled(draw_list, corr_x - 1, bar_y - 7, corr_x + 1, bar_y + 7, color_theme, 1.0)

    local peak_x = bar_x + bar_w * ((state.spatial_corr_peak + 1.0) * 0.5)
    draw_api.rect_filled(draw_list, peak_x - 0.5, bar_y - 6, peak_x + 0.5, bar_y + 6, 0xFF9E3D88, 1.0)

    if draw_api.text and small_font then
      local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
      local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
      push_f(ctx, small_font, small_font_size)
      draw_api.text(draw_list, bar_x - 14, bar_y - 5, 0x7A828EFF, "-1")
      draw_api.text(draw_list, bar_right + 5, bar_y - 5, 0x7A828EFF, "+1")

      local text_corr = string.format("%+.2f", corr)
      local corr_text_color = corr < -0.15 and 0xFF5C5CFF or 0x5CFFB6FF
      draw_api.text(draw_list, right - 48, corr_label_y, corr_text_color, text_corr)
      draw_api.text(draw_list, x + 12, corr_label_y, 0x7A828EFF, "Phase")
      pop_f(ctx)
    end
    corr_section_top = bar_y + 14
  end

  if state.spatial_show_width and #scope > 0 then
    local mid_sum, side_sum = 0, 0
    for index = 1, #scope do
      local point = scope[index]
      local mid_val = math.abs(point.y or 0)
      local side_val = math.abs(point.x or 0)
      mid_sum = mid_sum + mid_val * mid_val
      side_sum = side_sum + side_val * side_val
    end
    local count = #scope
    local rms_mid = math.sqrt(mid_sum / math.max(1, count))
    local rms_side = math.sqrt(side_sum / math.max(1, count))
    local stereo_width = rms_mid > 0.0001 and (rms_side / rms_mid) or 0

    if draw_api.text and small_font then
      local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
      local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
      push_f(ctx, small_font, small_font_size)

      local width_color
      if stereo_width < 0.3 or stereo_width > 1.5 then
        width_color = 0xFF5C5CFF
      elseif stereo_width < 0.5 or stereo_width > 1.2 then
        width_color = 0xFFD700FF
      else
        width_color = 0x5CFFB6FF
      end

      draw_api.text(draw_list, x + 12, corr_section_top + 2, 0x7A828EFF, "Width")
      draw_api.text(draw_list, right - 48, corr_section_top + 2, width_color, string.format("%.2f", stereo_width))
      pop_f(ctx)
    end
    corr_section_top = corr_section_top + 16
  end

  if anim > 0.5 then
    local push_iw = ImGui and ImGui.PushItemWidth or reaper.ImGui_PushItemWidth
    local pop_iw = ImGui and ImGui.PopItemWidth or reaper.ImGui_PopItemWidth
    local push_sc = ImGui and ImGui.PushStyleColor or reaper.ImGui_PushStyleColor
    local pop_sc = ImGui and ImGui.PopStyleColor or reaper.ImGui_PopStyleColor
    local push_sv = ImGui and ImGui.PushStyleVar or reaper.ImGui_PushStyleVar
    local pop_sv = ImGui and ImGui.PopStyleVar or reaper.ImGui_PopStyleVar
    local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
    local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
    local set_csp = ImGui and ImGui.SetCursorScreenPos or reaper.ImGui_SetCursorScreenPos

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

    local slider_x = x + 7
    local slider_w = width - 14
    local slider_y = corr_section_top + 4

    local function PushSliderStyle()
      push_iw(ctx, slider_w)
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
    end

    local function PopSliderStyle()
      pop_sv(ctx, 3)
      pop_sc(ctx, 7)
      pop_iw(ctx)
    end

    set_csp(ctx, slider_x, slider_y)
    PushSliderStyle()
    if small_font then push_f(ctx, small_font, small_font_size) end
    local trail_changed, new_trail = UIUtils.SliderDoubleReset(ctx, "##sp_trail", state.spatial_trail_length, 0.5, 3.0, "Trail  %.1f", 1.6)
    if small_font then pop_f(ctx) end
    PopSliderStyle()
    if trail_changed then state.spatial_trail_length = new_trail end

    set_csp(ctx, slider_x, slider_y + 24)
    PushSliderStyle()
    if small_font then push_f(ctx, small_font, small_font_size) end
    local gain_changed, new_gain = UIUtils.SliderDoubleReset(ctx, "##sp_gain", state.spatial_gain, 0.25, 4.0, "Gain  %.2fx", 1.0)
    if small_font then pop_f(ctx) end
    PopSliderStyle()
    if gain_changed then state.spatial_gain = new_gain end
  end

  local set_csp = ImGui and ImGui.SetCursorScreenPos or reaper.ImGui_SetCursorScreenPos
  local inv_btn = ImGui and ImGui.InvisibleButton or reaper.ImGui_InvisibleButton
  if collapse_anim > 0.96 then
    set_csp(ctx, center_x - radius, center_y - radius)
    if inv_btn(ctx, "##spatial_expand_toggle", radius * 2, radius * 2) then
      state.spatial_expanded = not state.spatial_expanded
    end
    local is_hov = ImGui and ImGui.IsItemHovered or reaper.ImGui_IsItemHovered
    local set_mc = ImGui and ImGui.SetMouseCursor or reaper.ImGui_SetMouseCursor
    local mc_hand = ImGui and ImGui.MouseCursor_Hand or reaper.ImGui_MouseCursor_Hand
    if is_hov(ctx) then
      set_mc(ctx, mc_hand())
    end
  end

  DrawSpatialContextMenu(ctx, state)

  UIUtils.EndAnimatedPanelBodyClip(ctx, body_clip)
  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  draw_api.dummy(ctx, width, height)
end

return SpatialPanel
