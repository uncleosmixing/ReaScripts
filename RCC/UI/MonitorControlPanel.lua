local MonitorControlPanel = {}

local UIUtils = require("UIUtils")
local UIKit = require("UIKit")
local ImGui = nil

function MonitorControlPanel.SetImGui(imgui)
  ImGui = imgui
  UIKit.SetImGui(imgui)
end

local MONITOR_SECTION_HEIGHT = 142
local MONITOR_HEADER_HEIGHT = 26
local ANIM_DURATION = 0.32

local anim = {
  expanded = true,
  t = 1.0,
  last_time = nil,
}

local function TickAnim()
  local now = reaper.time_precise()
  if anim.last_time then
    local dt = now - anim.last_time
    local dir = anim.expanded and 1 or -1
    anim.t = math.max(0, math.min(1, anim.t + dir * dt / ANIM_DURATION))
  end
  anim.last_time = now
  return UIUtils.EaseSmooth(anim.t)
end

local function DrawModeButtons(ctx, state, manager)
  local spacing = 6
  local get_avail = ImGui and ImGui.GetContentRegionAvail or reaper.ImGui_GetContentRegionAvail
  local same_line = ImGui and ImGui.SameLine or reaper.ImGui_SameLine

  local available_width = get_avail(ctx)
  local button_width = math.floor((available_width - spacing * 2) / 3)
  local button_height = 28

  if UIUtils.ThemeMonitorButton(ctx, "MUTE", button_width, button_height, state.mute) then
    manager.ToggleMute(state)
  end

  same_line(ctx, nil, spacing)
  if UIUtils.ThemeMonitorButton(ctx, "DIM", button_width, button_height, state.dim) then
    manager.ToggleDim(state)
  end

  same_line(ctx, nil, spacing)
  if UIUtils.ThemeMonitorButton(ctx, "MONO", button_width, button_height, state.mono) then
    manager.ToggleMono(state)
  end
end

local function DrawListenButtons(ctx, state, manager)
  local get_avail = ImGui and ImGui.GetContentRegionAvail or reaper.ImGui_GetContentRegionAvail
  local available_width = get_avail(ctx)
  local items = {
    { label = "L", id = "left" },
    { label = "R", id = "right" },
    { label = "MID", id = "mid" },
    { label = "SIDE", id = "side" },
  }

  local clicked = UIKit.ThemeSegmentedSelector(ctx, items, state.listen_mode, available_width, 24, "listen")
  if clicked then
    manager.ToggleListenMode(state, clicked)
  end
end

local function DrawBandButtons(ctx, state, manager)
  local get_avail = ImGui and ImGui.GetContentRegionAvail or reaper.ImGui_GetContentRegionAvail
  local available_width = get_avail(ctx)
  local items = {
    { label = "SUB", id = "sub" },
    { label = "LOW", id = "low" },
    { label = "MIDS", id = "mids" },
    { label = "HIGH", id = "high" },
  }

  local clicked = UIKit.ThemeSegmentedSelector(ctx, items, state.band_mode, available_width, 24, "band")
  if clicked then
    manager.ToggleBandMode(state, clicked)
  end
end

function MonitorControlPanel.Draw(ctx, state, manager)
  local theme = UIUtils.Theme()
  local eased = TickAnim()
  local is_animating = eased > 0.001 and eased < 0.999

  local get_csp = ImGui and ImGui.GetCursorScreenPos or reaper.ImGui_GetCursorScreenPos
  local push_sc = ImGui and ImGui.PushStyleColor or reaper.ImGui_PushStyleColor
  local pop_sc = ImGui and ImGui.PopStyleColor or reaper.ImGui_PopStyleColor
  local push_sv = ImGui and ImGui.PushStyleVar or reaper.ImGui_PushStyleVar
  local pop_sv = ImGui and ImGui.PopStyleVar or reaper.ImGui_PopStyleVar
  local col_btn = ImGui and ImGui.Col_Button or reaper.ImGui_Col_Button
  local col_btn_h = ImGui and ImGui.Col_ButtonHovered or reaper.ImGui_Col_ButtonHovered
  local col_btn_a = ImGui and ImGui.Col_ButtonActive or reaper.ImGui_Col_ButtonActive
  local col_child = ImGui and ImGui.Col_ChildBg or reaper.ImGui_Col_ChildBg
  local sv_fround = ImGui and ImGui.StyleVar_FrameRounding or reaper.ImGui_StyleVar_FrameRounding
  local sv_fpad = ImGui and ImGui.StyleVar_FramePadding or reaper.ImGui_StyleVar_FramePadding
  local btn = ImGui and ImGui.Button or reaper.ImGui_Button
  local is_hov = ImGui and ImGui.IsItemHovered or reaper.ImGui_IsItemHovered
  local get_wdl = ImGui and ImGui.GetWindowDrawList or reaper.ImGui_GetWindowDrawList
  local add_t = ImGui and ImGui.DrawList_AddText or reaper.ImGui_DrawList_AddText
  local dummy = ImGui and ImGui.Dummy or reaper.ImGui_Dummy
  local get_avail = ImGui and ImGui.GetContentRegionAvail or reaper.ImGui_GetContentRegionAvail
  local wf_noscroll = ImGui and ImGui.WindowFlags_NoScrollbar or reaper.ImGui_WindowFlags_NoScrollbar
  local begin_child = ImGui and ImGui.BeginChild or reaper.ImGui_BeginChild
  local end_child = ImGui and ImGui.EndChild or reaper.ImGui_EndChild
  local spacing_fn = ImGui and ImGui.Spacing or reaper.ImGui_Spacing

  local listen_text = (state.listen_mode and state.listen_mode ~= "normal") and string.upper(state.listen_mode) or "STEREO"
  local band_text = (state.band_mode and state.band_mode ~= "full") and (" / " .. string.upper(state.band_mode)) or ""
  local mode_text = listen_text .. band_text
  local mode_color = (mode_text == "STEREO") and theme.text_dim or theme.accent

  local hdr_x, hdr_y = get_csp(ctx)
  local text_y = hdr_y + 2
  local monitor_label_w = 52
  local monitor_label_h = 16

  push_sc(ctx, col_btn(), 0x00000000)
  push_sc(ctx, col_btn_h(), 0x00000000)
  push_sc(ctx, col_btn_a(), 0x00000000)
  push_sv(ctx, sv_fround(), 0)
  push_sv(ctx, sv_fpad(), 0, 0)

  if btn(ctx, "##monitor_toggle", monitor_label_w, monitor_label_h) then
    anim.expanded = not anim.expanded
    anim.last_time = nil
  end
  local monitor_btn_hovered = is_hov(ctx)

  pop_sc(ctx, 3)
  pop_sv(ctx, 2)

  local draw_list = get_wdl(ctx)
  local monitor_col = monitor_btn_hovered and theme.text or UIUtils.ThemeColor("text", 0xE8EAF0FF)
  add_t(draw_list, hdr_x, text_y, monitor_col, "Monitor")
  add_t(draw_list, hdr_x + monitor_label_w + 6, text_y, mode_color, mode_text)
  dummy(ctx, 0, monitor_label_h)

  local content_h = math.floor(eased * (MONITOR_SECTION_HEIGHT - MONITOR_HEADER_HEIGHT - 4))
  if content_h < 1 and not is_animating then
    return
  end

  local avail_w = get_avail(ctx)
  local no_scrollbar = wf_noscroll and wf_noscroll() or 0
  push_sc(ctx, col_child(), 0x00000000)
  if begin_child(ctx, "##monitor_body", avail_w, content_h, 0, no_scrollbar) then
    spacing_fn(ctx)
    DrawModeButtons(ctx, state, manager)
    spacing_fn(ctx)
    DrawListenButtons(ctx, state, manager)
    spacing_fn(ctx)
    DrawBandButtons(ctx, state, manager)
    end_child(ctx)
  end
  pop_sc(ctx, 1)
end

function MonitorControlPanel.GetSectionHeight()
  return MONITOR_SECTION_HEIGHT
end

function MonitorControlPanel.GetCurrentHeight()
  local eased = UIUtils.EaseSmooth(anim.t)
  local content_h = math.floor(eased * (MONITOR_SECTION_HEIGHT - MONITOR_HEADER_HEIGHT - 4))
  return MONITOR_HEADER_HEIGHT + 8 + content_h
end

return MonitorControlPanel
