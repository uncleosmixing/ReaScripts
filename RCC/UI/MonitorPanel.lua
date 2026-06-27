local MonitorPanel = {}
local UIUtils = require("UIUtils")
local LevelPanel = require("LevelPanel")
local ReferencePanel = require("ReferencePanel")
local WaveformPanel = require("WaveformPanel")
local SpectrumPanel = require("SpectrumPanel")
local SpatialPanel = require("SpatialPanel")
local MonitorControlPanel = require("MonitorControlPanel")
local HeadphoneCalPanel = require("HeadphoneCalPanel")

local EXT_SECTION = "RCC"
local EXT_PANEL_ORDER_KEY = "panel_order"

local PANEL_ORDER = {
  "level_loudness",
  "waveform",
  "spectrum",
  "spatial_analyzer",
  "reference",
  "hp_correction",
}

local PANEL_BY_ID = {
  level_loudness = {
    label = "LEVEL & LOUDNESS",
    right_reserve = 64,
    draw = function(ctx, state, active_analyzer, manager, small_font, small_font_size)
      LevelPanel.Draw(ctx, state, active_analyzer, manager, small_font, small_font_size)
    end,
  },
  waveform = {
    label = "WAVEFORM",
    right_reserve = 96,
    draw = function(ctx, state, active_analyzer, _, small_font, small_font_size)
      WaveformPanel.Draw(ctx, state, active_analyzer, small_font, small_font_size)
    end,
  },
  spectrum = {
    label = "SPECTRUM",
    right_reserve = 72,
    draw = function(ctx, state, active_analyzer, _, small_font, small_font_size)
      SpectrumPanel.Draw(ctx, state, active_analyzer.spectrum or {}, small_font, small_font_size)
    end,
  },
  spatial_analyzer = {
    label = "SPATIAL ANALYZER",
    right_reserve = 12,
    draw = function(ctx, state, active_analyzer, _, small_font, small_font_size)
      SpatialPanel.Draw(ctx, state, active_analyzer, small_font, small_font_size)
    end,
  },
  reference = {
    label = "REFERENCE",
    right_reserve = 90,
    draw = function(ctx, state, active_analyzer, manager, small_font, small_font_size)
      ReferencePanel.Draw(ctx, state, active_analyzer, manager, small_font, small_font_size)
    end,
  },
  hp_correction = {
    label = "HP CORRECTION",
    right_reserve = 190,
    draw = function(ctx, state, _, _, small_font, small_font_size)
      HeadphoneCalPanel.Draw(ctx, state, small_font, small_font_size)
    end,
  },
}

local function PanelGap(ctx)
  reaper.ImGui_Dummy(ctx, 0, 4)
end

local function BuildPanelLookup(order)
  local lookup = {}
  for _, id in ipairs(order or {}) do
    lookup[id] = true
  end
  return lookup
end

local function SplitCsv(value)
  local result = {}
  for id in tostring(value or ""):gmatch("[^,]+") do
    result[#result + 1] = id
  end
  return result
end

local function ValidatePanelOrder(order)
  local valid = {}
  local seen = {}
  local normalized = {}

  for _, id in ipairs(PANEL_ORDER) do
    valid[id] = true
  end

  for _, id in ipairs(order or {}) do
    if valid[id] and not seen[id] then
      normalized[#normalized + 1] = id
      seen[id] = true
    end
  end

  for _, id in ipairs(PANEL_ORDER) do
    if not seen[id] then
      normalized[#normalized + 1] = id
      seen[id] = true
    end
  end

  return normalized
end

local function CopyDefaultPanelOrder()
  local order = {}
  for i, id in ipairs(PANEL_ORDER) do
    order[i] = id
  end
  return order
end

local function IsDefaultPanelOrder(order)
  order = ValidatePanelOrder(order)
  for i, id in ipairs(PANEL_ORDER) do
    if order[i] ~= id then
      return false
    end
  end
  return true
end

local function EnsurePanelOrder(state)
  if state.ui_panel_order_initialized then
    return
  end

  local saved = reaper.GetExtState and reaper.GetExtState(EXT_SECTION, EXT_PANEL_ORDER_KEY) or ""
  state.ui_panel_order = ValidatePanelOrder(SplitCsv(saved))
  state.ui_panel_order_lookup = BuildPanelLookup(state.ui_panel_order)
  state.ui_panel_order_initialized = true
end

local function ResetPanelOrder(state)
  state.ui_panel_order = CopyDefaultPanelOrder()
  state.ui_panel_order_lookup = BuildPanelLookup(state.ui_panel_order)
  state.ui_panel_order_dirty = true
  state.ui_panel_rects_prev = nil
  state.ui_panel_drag_candidate = nil
  state.ui_panel_drag_id = nil
  state.ui_panel_drop_target_id = nil
  state.ui_panel_drop_target_rect = nil
end

local function SavePanelOrderIfNeeded(state)
  if not state.ui_panel_order_dirty then
    return
  end

  state.ui_panel_order = ValidatePanelOrder(state.ui_panel_order)
  state.ui_panel_order_lookup = BuildPanelLookup(state.ui_panel_order)
  if reaper.SetExtState then
    reaper.SetExtState(EXT_SECTION, EXT_PANEL_ORDER_KEY, table.concat(state.ui_panel_order, ","), true)
  end
  state.ui_panel_order_dirty = false
end

local function GetMouse(ctx)
  if not reaper.ImGui_GetMousePos then
    return nil, nil
  end
  return reaper.ImGui_GetMousePos(ctx)
end

local function FindPanelRect(rects, id)
  for _, rect in ipairs(rects or {}) do
    if rect.id == id then
      return rect
    end
  end
  return nil
end

local function RegisterPanelRect(ctx, state, id, x, y, right, bottom)
  local panel = PANEL_BY_ID[id]
  if not panel then
    return
  end

  local label_w = UIUtils.TextWidth(ctx, panel.label or id)

  state.ui_panel_rects = state.ui_panel_rects or {}
  state.ui_panel_rects[#state.ui_panel_rects + 1] = {
    id = id,
    label = panel.label or id,
    x = x,
    right = right,
    y = y,
    bottom = bottom,
    handle_x = x + UIUtils.HEADER_LABEL_X - 2,
    handle_right = x + UIUtils.HEADER_LABEL_X + label_w + 8,
    handle_y = y,
    handle_bottom = y + UIUtils.HEADER_HEIGHT,
  }
end

local function PointInHandle(px, py, rect)
  return rect
    and px and py
    and px >= rect.handle_x and px <= rect.handle_right
    and py >= rect.handle_y and py <= rect.handle_bottom
end

local function FindTargetRect(rects, mx, my, dragged_id)
  local best = nil
  local best_dist = math.huge
  local last = nil

  for _, rect in ipairs(rects or {}) do
    if rect.id ~= dragged_id then
      if not last or rect.bottom > last.bottom then
        last = rect
      end
      local inside_x = mx and mx >= rect.x and mx <= rect.right
      local center_y = (rect.y + rect.bottom) * 0.5
      local dist = my and math.abs(my - center_y) or math.huge
      if inside_x and dist < best_dist then
        best = rect
        best_dist = dist
      end
    end
  end

  if not best and last and mx and my and mx >= last.x and mx <= last.right and my > last.bottom then
    best = last
  end

  return best
end

local function DrawAppHeader(ctx, state, small_font, small_font_size)
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local width = reaper.ImGui_GetContentRegionAvail(ctx)
  local height = 24
  local right = x + width
  local bottom = y + height

  local title = "Room Control Center"
  local text_h = 14
  if reaper.ImGui_CalcTextSize then
    local _, measured_h = reaper.ImGui_CalcTextSize(ctx, title)
    text_h = measured_h or text_h
  end

  reaper.ImGui_DrawList_AddLine(draw_list, x, bottom - 1, right, bottom - 1, 0xFFFFFF22, 1.0)
  reaper.ImGui_DrawList_AddLine(draw_list, x, bottom, right, bottom, 0x00000066, 1.0)
  reaper.ImGui_DrawList_AddText(
    draw_list,
    x + 4,
    math.floor(y + (height - text_h) * 0.5 - 1 + 0.5),
    UIUtils.STYLE.text,
    title
  )

  local order_is_default = IsDefaultPanelOrder(state.ui_panel_order)
  if not order_is_default then
    local reset_w = 58
    local reset_h = UIUtils.METRIC.header_action_h
    local reset_x = right - reset_w - 7
    local reset_y = y + math.floor((height - reset_h) * 0.5 + 0.5)
    local reset_hovered = mx and my and mx >= reset_x and mx <= reset_x + reset_w and my >= reset_y and my <= reset_y + reset_h
    local title_hovered = mx and my and mx >= x and mx <= right and my >= y and my <= bottom
    local reveal = UIUtils.GetHoverReveal(state, "panel_default_order", title_hovered or reset_hovered or state.ui_panel_reset_hovered)
    if reveal > 0.01 then
      local clicked, button_hovered = UIUtils.HeaderActionButtonAlpha(
        ctx, "##reset_panel_order", "DEFAULT", reset_x, reset_y, reset_w, reset_h,
        reset_hovered, reveal, small_font, small_font_size)
      state.ui_panel_reset_hovered = button_hovered
      if clicked then
        ResetPanelOrder(state)
      end
    else
      state.ui_panel_reset_hovered = false
    end
  else
    state.ui_panel_reset_hovered = false
  end

  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  reaper.ImGui_Dummy(ctx, width, height)
end

local function DrawPanelDragOverlay(ctx, state)
  if not state.ui_panel_drag_id then
    return
  end

  local mx, my = GetMouse(ctx)
  if not mx or not my then
    return
  end

  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  local w = state.ui_panel_drag_w or 280
  local h = UIUtils.HEADER_HEIGHT
  local x = mx - (state.ui_panel_drag_offset_x or (w * 0.5))
  local y = my - (state.ui_panel_drag_offset_y or (UIUtils.HEADER_HEIGHT * 0.5))
  local right = x + w
  local bottom = y + h

  reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, right, bottom, UIUtils.STYLE.panel_bg, UIUtils.METRIC.radius)
  reaper.ImGui_DrawList_AddRectFilled(draw_list, x + 1, y + 1, right - 1, bottom - 1, UIUtils.STYLE.panel_header, UIUtils.METRIC.radius)
  reaper.ImGui_DrawList_AddRect(draw_list, x, y, right, bottom, 0x5CFFB6AA, UIUtils.METRIC.radius, nil, 1.2)
  reaper.ImGui_DrawList_AddText(draw_list, x + UIUtils.HEADER_LABEL_X, y + 5, 0x5CFFB6EE, state.ui_panel_drag_label or "")

  local target = state.ui_panel_drop_target_rect
  if target then
    local line_y = state.ui_panel_drop_after and target.bottom + 2 or target.y - 2
    reaper.ImGui_DrawList_AddLine(draw_list, target.x + 6, line_y, target.right - 6, line_y, 0x5CFFB6EE, 2.0)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, target.x + 8, line_y, 3.0, 0x5CFFB6FF)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, target.right - 8, line_y, 3.0, 0x5CFFB6FF)
  end
end

local function DrawPanelPlaceholder(ctx, x, y, right)
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  local line_y = y + UIUtils.HEADER_HEIGHT * 0.5
  reaper.ImGui_DrawList_AddLine(draw_list, x + 6, line_y, right - 6, line_y, UIUtils.STYLE.accent_dim, 2.0)
  reaper.ImGui_DrawList_AddCircleFilled(draw_list, x + 8, line_y, 3.0, 0x5CFFB6EE)
  reaper.ImGui_DrawList_AddCircleFilled(draw_list, right - 8, line_y, 3.0, 0x5CFFB6EE)
end

local function ProcessPanelReorder(ctx, state)
  local rects = state.ui_panel_rects_prev or {}
  local mx, my = GetMouse(ctx)
  local left_down = reaper.ImGui_IsMouseDown and reaper.ImGui_IsMouseDown(ctx, 0)
  local right_down = reaper.ImGui_IsMouseDown and reaper.ImGui_IsMouseDown(ctx, 1)
  local right_pressed = right_down and not state.ui_panel_right_down_prev

  local hovered_handle = nil
  for _, rect in ipairs(rects) do
    if PointInHandle(mx, my, rect) then
      hovered_handle = rect
      break
    end
  end

  if hovered_handle and not state.ui_panel_drag_id and right_pressed then
    state.ui_panel_drag_candidate = hovered_handle.id
    state.ui_panel_drag_start_x = mx
    state.ui_panel_drag_start_y = my
    state.ui_panel_drag_offset_x = mx - hovered_handle.x
    state.ui_panel_drag_offset_y = my - hovered_handle.y
    state.ui_panel_drag_w = hovered_handle.right - hovered_handle.x
    state.ui_panel_drag_label = hovered_handle.label
  end

  if state.ui_panel_drag_candidate and right_down and mx and my then
    local dx = mx - (state.ui_panel_drag_start_x or mx)
    local dy = my - (state.ui_panel_drag_start_y or my)
    if (dx * dx + dy * dy) >= 16 then
      state.ui_panel_drag_id = state.ui_panel_drag_candidate
    end
  end

  if state.ui_panel_drag_id and right_down then
    local target = FindTargetRect(rects, mx, my, state.ui_panel_drag_id)
    state.ui_panel_drop_target_rect = target
    state.ui_panel_drop_target_id = target and target.id or nil
    state.ui_panel_drop_after = target and my > ((target.y + target.bottom) * 0.5) or false
  end

  if hovered_handle and not state.ui_panel_drag_id and reaper.ImGui_SetMouseCursor and reaper.ImGui_MouseCursor_Hand then
    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
  end

  if not right_down then
    if state.ui_panel_drag_id and state.ui_panel_drop_target_id then
      if state.ui_panel_drop_after then
        UIUtils.MovePanelAfter(state, state.ui_panel_drag_id, state.ui_panel_drop_target_id)
      else
        UIUtils.MovePanelBefore(state, state.ui_panel_drag_id, state.ui_panel_drop_target_id)
      end
    end

    state.ui_panel_drag_candidate = nil
    state.ui_panel_drag_id = nil
    state.ui_panel_drop_target_id = nil
    state.ui_panel_drop_target_rect = nil
    state.ui_panel_drop_after = nil
    state.ui_panel_drag_start_x = nil
    state.ui_panel_drag_start_y = nil
    state.ui_panel_drag_offset_x = nil
    state.ui_panel_drag_offset_y = nil
    state.ui_panel_drag_w = nil
    state.ui_panel_drag_label = nil
  end

  state.ui_panel_mouse_down_prev = left_down == true
  state.ui_panel_right_down_prev = right_down == true
end

local function DrawPanelItem(ctx, state, id, active_analyzer, manager, small_font, small_font_size)
  local panel = PANEL_BY_ID[id]
  if not panel then
    return false
  end

  local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
  local width = reaper.ImGui_GetContentRegionAvail(ctx)
  local prev_rect = FindPanelRect(state.ui_panel_rects_prev, id)
  if state.ui_panel_drag_id == id and prev_rect then
    DrawPanelPlaceholder(ctx, x, y, x + width)
    reaper.ImGui_Dummy(ctx, width, UIUtils.HEADER_HEIGHT)
  else
    panel.draw(ctx, state, active_analyzer, manager, small_font, small_font_size)
  end

  local _, after_y = reaper.ImGui_GetCursorScreenPos(ctx)
  RegisterPanelRect(ctx, state, id, x, y, x + width, after_y)
  return true
end

local function DrawOrderedPanels(ctx, state, active_analyzer, manager, small_font, small_font_size, predicate, has_previous)
  for _, id in ipairs(state.ui_panel_order) do
    if predicate(id) then
      if has_previous then
        PanelGap(ctx)
      end
      if DrawPanelItem(ctx, state, id, active_analyzer, manager, small_font, small_font_size) then
        has_previous = true
      end
    end
  end
  return has_previous
end

local function DrawAnalyzerStack(ctx, state, active_analyzer, manager, small_font, small_font_size)
  EnsurePanelOrder(state)
  state.ui_panel_order_lookup = BuildPanelLookup(state.ui_panel_order)
  ProcessPanelReorder(ctx, state)
  state.ui_panel_rects = {}

  DrawOrderedPanels(
    ctx, state, active_analyzer, manager, small_font, small_font_size,
    function(id) return PANEL_BY_ID[id] ~= nil end,
    false
  )

  DrawPanelDragOverlay(ctx, state)
  SavePanelOrderIfNeeded(state)
  state.ui_panel_rects_prev = state.ui_panel_rects
end

local function DrawAnalyzer(ctx, state, manager, small_font, small_font_size)
  local analyzer = manager.ReadAnalyzer()
  
  -- Create a bulletproof fallback table if the REAPER audio engine is stopped/inactive
  local is_active = analyzer and analyzer.active
  local active_analyzer = is_active and analyzer or {
    active = false,
    spectrum = {},
    scope = {},
    peak_l = 0, peak_r = 0, rms_l = 0, rms_r = 0,
    true_peak_l = 0, true_peak_r = 0,
    lufs_m = -150, lufs_s = -150, lufs_i = -150,
    correlation = 0,
    waveform = {}, waveform_l = {}, waveform_r = {}
  }
  
  manager.UpdateAnalyzerMax(state, active_analyzer)

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Spacing(ctx)
  EnsurePanelOrder(state)
  DrawAppHeader(ctx, state, small_font, small_font_size)
  PanelGap(ctx)

  -- If stopped/inactive, show a compact setup prompt at the top, without hiding anything!
  if not is_active then
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF7E7EFF)
    reaper.ImGui_Text(ctx, "DAW Engine Stopped / Analyzer Tap Inactive")
    reaper.ImGui_PopStyleColor(ctx, 1)
    
    reaper.ImGui_Spacing(ctx)
    if UIUtils.StyledButton(ctx, "Install / Run Analyzer Tap", -1, 24, true) then
      manager.InstallAnalyzerTap(state)
    end
    reaper.ImGui_Spacing(ctx)
  elseif analyzer.version < 13 or not analyzer.waveform_supported or not analyzer.waveform_stereo_supported then
    reaper.ImGui_Text(ctx, "Analyzer Tap update required")
    if UIUtils.StyledButton(ctx, "Update Analyzer Tap", -1, 24, true) then
      manager.InstallAnalyzerTap(state)
    end
    reaper.ImGui_Spacing(ctx)
  end

  -- ALWAYS draw all visual meters to keep the console look unified and complete!
  DrawAnalyzerStack(ctx, state, active_analyzer, manager, small_font, small_font_size)

  if state.analyzer_error then
    PanelGap(ctx)
    reaper.ImGui_Text(ctx, state.analyzer_error)
  end

  PanelGap(ctx)
end

function MonitorPanel.Draw(ctx, state, manager, small_font, small_font_size)
  local _, available_height = reaper.ImGui_GetContentRegionAvail(ctx)
  local monitor_section_height = MonitorControlPanel.GetCurrentHeight()
  local child_h = available_height - monitor_section_height

  -- Ensure child height doesn't go below minimum usable size (dynamic to prevent clipping on small docks)
  local analyzer = manager.ReadAnalyzer()
  local min_child_h = (analyzer and analyzer.active) and 80 or 40
  if child_h < min_child_h then
    child_h = min_child_h
  end

  -- 1. Scrollable child container for all meters and analyzers
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0) -- Make child background transparent
  if reaper.ImGui_BeginChild(ctx, "##analyzer_scroll_area", 0, child_h, 0, 0) then
    DrawAnalyzer(ctx, state, manager, small_font, small_font_size)
    reaper.ImGui_EndChild(ctx)
  end
  reaper.ImGui_PopStyleColor(ctx, 1)

  -- 2. Pinned Monitoring Section at the bottom of the window
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)
  MonitorControlPanel.Draw(ctx, state, manager, small_font, small_font_size)
end

return MonitorPanel
