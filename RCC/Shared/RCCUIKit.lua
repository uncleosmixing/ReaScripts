local UIKit = {}
local UIUtils = require("RCCUIUtils")
local ImGui = nil

function UIKit.SetImGui(imgui)
  ImGui = imgui
  UIUtils.SetImGui(imgui)
end

function UIKit.Panel(ctx, draw_list, draw_api, x, y, right, bottom, label, small_font, small_font_size)
  UIUtils.DrawInstrumentPanel(draw_list, draw_api, x, y, right, bottom, 6.0)
  if label then
    UIUtils.DrawModuleLabel(ctx, draw_list, draw_api, x, y, label, small_font, small_font_size)
  end
end

function UIKit.CollapsiblePanel(ctx, state, panel_id, draw_list, draw_api, x, y, right, bottom, label, small_font, small_font_size)
  UIUtils.DrawInstrumentPanel(draw_list, draw_api, x, y, right, bottom, 6.0)
  if label then
    UIUtils.DrawCollapsibleModuleLabel(ctx, draw_list, draw_api, x, y, label, panel_id, state, small_font, small_font_size)
  end
end

function UIKit.HeaderRightText(ctx, draw_list, draw_api, x, y, right, text, color, small_font, small_font_size)
  if not draw_api.text or not text then
    return
  end

  local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
  local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont

  if small_font then
    push_f(ctx, small_font, small_font_size)
  end

  local text_w = UIUtils.TextWidth(ctx, text)
  local text_y = UIUtils.HeaderTextY(ctx, y, text, small_font, small_font_size)
  draw_api.text(draw_list, math.floor(right - text_w), text_y, color or 0xD7DAE0FF, text)

  if small_font then
    pop_f(ctx)
  end
end

function UIKit.TinyButton(ctx, label, width, height, active)
  return UIUtils.PremiumMonitorButton(ctx, label, width, height, active)
end

function UIKit.SegmentedSelector(ctx, items, active_id, width, height, id_suffix)
  local count = #items
  if count == 0 then
    return nil
  end

  local spacing = 6
  local button_w = math.floor((width - spacing * (count - 1)) / count)
  local clicked_id = nil
  local same_line = ImGui and ImGui.SameLine or reaper.ImGui_SameLine

  for index, item in ipairs(items) do
    if index > 1 then
      same_line(ctx, nil, spacing)
    end

    local id = item.id or item.mode or item.label
    local label = item.label or tostring(id)
    if UIKit.TinyButton(ctx, label .. "##" .. (id_suffix or "seg") .. tostring(id), button_w, height, active_id == id) then
      clicked_id = id
    end
  end

  return clicked_id
end

function UIKit.ThemeSegmentedSelector(ctx, items, active_id, width, height, id_suffix)
  local count = #items
  if count == 0 then
    return nil
  end

  local spacing = 6
  local button_w = math.floor((width - spacing * (count - 1)) / count)
  local clicked_id = nil
  local same_line = ImGui and ImGui.SameLine or reaper.ImGui_SameLine

  for index, item in ipairs(items) do
    if index > 1 then
      same_line(ctx, nil, spacing)
    end

    local id = item.id or item.mode or item.label
    local label = item.label or tostring(id)
    if UIUtils.ThemeMonitorButton(ctx, label .. "##" .. (id_suffix or "theme_seg") .. tostring(id), button_w, height, active_id == id) then
      clicked_id = id
    end
  end

  return clicked_id
end

function UIKit.Readout(draw_list, draw_api, x, y, right, text, color)
  if not draw_api.text then
    return
  end

  local text_w = #tostring(text or "") * 6
  draw_api.text(draw_list, math.floor(right - text_w), y, color or 0x5CFFB6FF, tostring(text or ""))
end

return UIKit
