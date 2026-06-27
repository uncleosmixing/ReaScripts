local Theme = require("RCCTheme")
local Config = require("RCCConfig")

local UI = {}

UI.C = {}

UI.M = Config.METRICS

function UI.Rgba(r, g, b, a)
  return Theme.Rgba(r, g, b, a)
end

function UI.SplitRgba(color)
  return Theme.SplitRgba(color)
end

function UI.MixColor(a, b, t, alpha)
  return Theme.MixColor(a, b, t, alpha)
end

function UI.Luma(color)
  return Theme.Luma(color)
end

function UI.EnsureMinLuma(color, min_luma, alpha)
  return Theme.EnsureMinLuma(color, min_luma, alpha)
end

function UI.ThemeColor(keys, fallback)
  return Theme.ThemeColor(keys, fallback)
end

function UI.UpdateTheme(C)
  C = C or UI.C

  local theme = Theme.Refresh(false)

  C.bg = theme.window_bg
  C.panel = theme.panel_bg
  C.header = theme.panel_header
  C.border = theme.panel_border
  C.panel_inner = theme.inner_border
  C.panel_highlight = theme.top_highlight
  C.panel_separator = theme.panel_separator
  C.accent = theme.accent
  C.accent_dim = theme.accent_dim
  C.text = theme.text
  C.text_dim = theme.text_dim
  C.text_hover = theme.text_hover

  C.button = theme.button
  C.button_hov = theme.button_hover
  C.button_act = theme.button_pressed
  C.button_active = theme.button_active
  C.button_active_hov = theme.button_active_hover
  C.button_border = theme.button_border
  C.button_active_border = theme.button_active_border
  C.header_action = theme.header_action
  C.header_action_hov = theme.header_action_hover

  C.mute = 0xD55353FF
  C.solo = 0xE4BD13FF
  C.arm = 0xD55353FF
  C.phase = 0x1E7B93FF
  C.read = 0x32A852FF
  C.write = 0xD55353FF
  return C
end

function UI.PushTheme(ImGui, ctx, C)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, C.bg)
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, 0x00000000)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, C.border)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.text)
  ImGui.PushStyleColor(ctx, ImGui.Col_TextDisabled, C.text_dim)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.button)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.button_hov)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C.button_act)
  ImGui.PushStyleColor(ctx, ImGui.Col_Header, C.header)
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, UI.MixColor(C.header, 0xFFFFFF00, 0.1, 255))
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, UI.MixColor(C.header, 0xFFFFFF00, 0.2, 255))
  ImGui.PushStyleColor(ctx, ImGui.Col_ScrollbarBg, 0x00000000)
  ImGui.PushStyleColor(ctx, ImGui.Col_ScrollbarGrab, 0x20242C88)
  ImGui.PushStyleColor(ctx, ImGui.Col_ScrollbarGrabHovered, 0x2C323EFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ScrollbarGrabActive, C.accent)

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildRounding, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 6, 6)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 0, 6)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ScrollbarRounding, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ScrollbarSize, 6)
end

function UI.PopTheme(ImGui, ctx)
  ImGui.PopStyleColor(ctx, 15)
  ImGui.PopStyleVar(ctx, 9)
end

function UI.DrawContainer(ImGui, C, dl, x, y, r, b, bg_color, border_color, rounding)
  rounding = rounding or 0
  if bg_color == C.panel then
    ImGui.DrawList_AddRect(dl, x, y + 2, r, b + 5, 0x0000000A, rounding + 1.5, 0, 2.0)
    ImGui.DrawList_AddRect(dl, x, y + 1, r, b + 2, 0x0000001A, rounding + 0.5, 0, 1.0)
    ImGui.DrawList_AddRect(dl, x, y + 1, r, b + 1, 0x0000002A, rounding, 0, 1.0)
    ImGui.DrawList_AddRectFilled(dl, x, y, r, b, C.panel, rounding)
    ImGui.DrawList_AddRectFilled(dl, x + 1, y + 1, r - 1, math.min(b - 1, y + 17), C.header, rounding, ImGui.DrawFlags_RoundCornersTop)
    ImGui.DrawList_AddLine(dl, x + rounding, y + 1, r - rounding, y + 1, C.panel_highlight, 1.0)
    ImGui.DrawList_AddLine(dl, x + rounding, y + 18, r - rounding, y + 18, C.panel_separator, 1.0)
    ImGui.DrawList_AddRect(dl, x, y, r, b, border_color or C.border, rounding, 0, 1.0)
    ImGui.DrawList_AddRect(dl, x + 1, y + 1, r - 1, b - 1, C.panel_inner, math.max(0, rounding - 1), 0, 1.0)
  else
    ImGui.DrawList_AddRectFilled(dl, x, y, r, b, bg_color, rounding)
    if border_color then
      ImGui.DrawList_AddRect(dl, x, y, r, b, border_color, rounding, 0, 1.0)
    end
  end
end

function UI.TruncateText(ImGui, ctx, text, max_w)
  local w = ImGui.CalcTextSize(ctx, text)
  if w <= max_w then return text end
  local dots = "..."
  local dots_w = ImGui.CalcTextSize(ctx, dots)
  if max_w <= dots_w then return "" end
  local current = text
  while #current > 0 do
    current = current:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
    if ImGui.CalcTextSize(ctx, current) + dots_w <= max_w then
      return current .. dots
    end
  end
  return dots
end

function UI.TrackColorToRgba(color)
  if color == 0 then return 0x333333FF end
  local r, g, b = reaper.ColorFromNative(color)
  return (r << 24) | (g << 16) | (b << 8) | 0xFF
end

function UI.DrawPanelHeader(ImGui, ctx, C, font_small, label, is_open)
  local dl = ImGui.GetWindowDrawList(ctx)
  local cx, cy = ImGui.GetCursorScreenPos(ctx)
  local w = ImGui.GetContentRegionAvail(ctx)
  local h = 22
  local clicked = ImGui.InvisibleButton(ctx, label, math.max(1.0, w), h)
  local hovered = ImGui.IsItemHovered(ctx)
  local bg = hovered and UI.MixColor(C.header, C.accent, 0.07, 210) or C.header
  local rounding_flags = is_open and ImGui.DrawFlags_RoundCornersTop or ImGui.DrawFlags_RoundCornersAll

  ImGui.DrawList_AddRectFilled(dl, cx, cy, cx + w, cy + h, bg, 4, rounding_flags)
  ImGui.DrawList_AddLine(dl, cx + 4, cy + h - 1, cx + w - 4, cy + h - 1, C.panel_separator, 1.0)

  local tx = cx + 10
  local ty = cy + h / 2
  local tc = hovered and C.accent_dim or C.text_dim
  if is_open then
    ImGui.DrawList_AddLine(dl, tx - 3, ty - 1, tx, ty + 2, tc, 1.5)
    ImGui.DrawList_AddLine(dl, tx, ty + 2, tx + 3, ty - 1, tc, 1.5)
  else
    ImGui.DrawList_AddLine(dl, tx - 1, ty - 3, tx + 2, ty, tc, 1.5)
    ImGui.DrawList_AddLine(dl, tx + 2, ty, tx - 1, ty + 3, tc, 1.5)
  end

  ImGui.PushFont(ctx, font_small)
  local fs_h = ImGui.GetFontSize(ctx)
  ImGui.DrawList_AddText(dl, cx + 22, cy + (h - fs_h) / 2, hovered and C.text_hover or C.text, label)
  ImGui.PopFont(ctx)
  return clicked
end

function UI.DrawHeaderPowerButton(ImGui, ctx, C, dl, id, x, y, active, disabled)
  local w, h = 18, 16
  ImGui.SetCursorScreenPos(ctx, x, y)
  local clicked = ImGui.InvisibleButton(ctx, id, w, h)
  local hovered = ImGui.IsItemHovered(ctx)
  local held = ImGui.IsItemActive(ctx)

  local bg = C.header_action
  local border = C.button_border
  local icon = disabled and 0x5A616B80 or C.text_dim
  if active then
    bg = held and 0x2F260EFF or (hovered and 0x4A3A12FF or 0x34290FFF)
    border = hovered and 0xE4BD13AA or 0xE4BD1366
    icon = C.solo
  elseif hovered and not disabled then
    bg = C.header_action_hov
    border = 0xFFFFFF24
    icon = C.text_hover
  end

  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 3)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, border, 3, 0, 1.0)
  ImGui.DrawList_AddLine(dl, x + 1, y + 1, x + w - 1, y + 1, 0xFFFFFF0D, 1.0)

  local cx = x + w * 0.5
  local cy = y + h * 0.55
  ImGui.DrawList_AddCircle(dl, cx, cy, 4.0, icon, 0, 1.1)
  ImGui.DrawList_AddLine(dl, cx, y + 3.8, cx, cy - 1.8, icon, 1.3)

  return clicked and not disabled
end

function UI.DrawMiniToggle(ImGui, ctx, C, font_small, id, x, y, w, h, label, active, accent, disabled, fill)
  w = math.max(1.0, w or 1.0)
  h = math.max(1.0, h or 1.0)
  ImGui.SetCursorScreenPos(ctx, x, y)
  local clicked = ImGui.InvisibleButton(ctx, id, w, h)
  local hovered = ImGui.IsItemHovered(ctx)
  local held = ImGui.IsItemActive(ctx)
  accent = accent or C.solo

  local bg = C.header_action
  local border = C.button_border
  local text = disabled and 0x5A616B80 or C.text_dim
  if active then
    bg = held and 0x2F260EFF or (hovered and 0x4A3A12FF or 0x34290FFF)
    border = hovered and (accent & 0xFFFFFFAA) or (accent & 0xFFFFFF66)
    text = accent
  elseif hovered and not disabled then
    bg = C.header_action_hov
    border = 0xFFFFFF24
    text = C.text_hover
  end

  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 3)
  if fill then
    fill = math.max(0.0, math.min(1.0, fill))
    local fill_w = math.floor((w - 4) * fill + 0.5)
    if fill_w > 0 then
      ImGui.DrawList_AddRectFilled(dl, x + 2, y + h - 3, x + 2 + fill_w, y + h - 1, accent, 1)
    end
  end
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, border, 3, 0, 1.0)
  ImGui.DrawList_AddLine(dl, x + 1, y + 1, x + w - 1, y + 1, 0xFFFFFF0D, 1.0)
  UI.CenterTextInRect(ImGui, ctx, dl, x, y, w, h, label, text, font_small)

  return clicked and not disabled, hovered and not disabled
end

function UI.DrawMiniKnob(ImGui, ctx, C, id, x, y, w, h, value, active, disabled)
  w = math.max(1.0, w or 1.0)
  h = math.max(1.0, h or 1.0)
  value = math.max(0.0, math.min(1.0, value or 0.0))
  ImGui.SetCursorScreenPos(ctx, x, y)
  local clicked = ImGui.InvisibleButton(ctx, id, w, h)
  local hovered = ImGui.IsItemHovered(ctx)
  local held = ImGui.IsItemActive(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)

  local border = active and 0x5CFFB666 or (hovered and 0xFFFFFF28 or C.button_border)
  local accent = disabled and 0x5A616B80 or C.accent
  local cx = x + w * 0.5
  local cy = y + h * 0.5
  local radius = math.min(w, h) * 0.5 - 2.0

  if held then
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, radius + 2.0, 0x00000033, 18)
  elseif hovered then
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, radius + 2.0, 0xFFFFFF12, 18)
  end
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, radius, disabled and 0x10121788 or 0x101419CC, 18)
  ImGui.DrawList_AddCircle(dl, cx, cy, radius, border, 18, 1.0)

  local start_a = math.rad(135)
  local end_a = math.rad(405)
  local active_a = start_a + (end_a - start_a) * value
  local last_x, last_y
  for s = 0, 18 do
    local t = s / 18
    local a = start_a + (active_a - start_a) * t
    local px = cx + math.cos(a) * (radius - 1.0)
    local py = cy + math.sin(a) * (radius - 1.0)
    if last_x then
      ImGui.DrawList_AddLine(dl, last_x, last_y, px, py, accent, 1.6)
    end
    last_x, last_y = px, py
  end

  local ix = cx + math.cos(active_a) * (radius - 4.0)
  local iy = cy + math.sin(active_a) * (radius - 4.0)
  ImGui.DrawList_AddLine(dl, cx, cy, ix, iy, disabled and 0x5A616B80 or C.text_hover, 1.3)
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, 1.2, disabled and 0x5A616B80 or C.text_dim)

  return clicked and not disabled, hovered and not disabled, held and not disabled
end

function UI.DrawTooltip(ImGui, ctx, C, font_small, text)
  if not text or text == "" or not ImGui.IsItemHovered(ctx) then return end
  ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, 0x0D1015F4)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0xFFFFFF18)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 7, 5)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 1)
  if ImGui.BeginTooltip(ctx) then
    if font_small then ImGui.PushFont(ctx, font_small) end
    ImGui.TextColored(ctx, C.text, text)
    if font_small then ImGui.PopFont(ctx) end
    ImGui.EndTooltip(ctx)
  end
  ImGui.PopStyleVar(ctx, 3)
  ImGui.PopStyleColor(ctx, 2)
end

function UI.DrawStatusButton(ImGui, ctx, C, font_small, label, active, active_color, force_w, force_h)
  local safe_label = tostring(label or "")
  local visible_label = safe_label:gsub("##.*$", "")
  local id = safe_label .. "##status_btn_" .. safe_label
  local w = math.max(1.0, force_w or 30.0)
  local h = math.max(1.0, force_h or 18.0)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local clicked = ImGui.InvisibleButton(ctx, id, w, h)
  local hovered = ImGui.IsItemHovered(ctx)
  local held = ImGui.IsItemActive(ctx)
  local bg, border_col, text_col

  if active then
    bg = UI.MixColor(C.button_active, active_color, 0.12, 255)
    if held then
      bg = UI.MixColor(C.button_act, active_color, 0.22, 255)
    elseif hovered then
      bg = UI.MixColor(C.button_active_hov, active_color, 0.16, 255)
    end
    border_col = UI.MixColor(C.button_active_border, active_color, 0.35, 180)
    text_col = active_color
  else
    bg = C.button
    if held then
      bg = C.button_act
    elseif hovered then
      bg = C.button_hov
    end
    border_col = C.button_border
    text_col = C.text_dim
  end

  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, 4)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, border_col, 4, 0, 1.0)
  UI.CenterTextInRect(ImGui, ctx, dl, x, y, w, h, visible_label, text_col, font_small)
  return clicked
end

function UI.CenterTextInRect(ImGui, ctx, dl, x, y, w, h, text, color, font)
  text = tostring(text or "")
  if font then ImGui.PushFont(ctx, font) end
  local text_w, text_h = ImGui.CalcTextSize(ctx, text)
  ImGui.DrawList_AddText(
    dl,
    math.floor(x + (w - text_w) * 0.5 + 0.5),
    math.floor(y + (h - text_h) * 0.5 + 0.5),
    color or UI.C.text,
    text
  )
  if font then ImGui.PopFont(ctx) end
end

function UI.DrawRccSlot(ImGui, ctx, C, dl, id, x, y, w, h, active, danger)
  w = math.max(1.0, w or 1.0)
  h = math.max(1.0, h or 1.0)
  ImGui.SetCursorScreenPos(ctx, x, y)
  local clicked = ImGui.InvisibleButton(ctx, id, w, h)
  local hovered = ImGui.IsItemHovered(ctx)
  local held = ImGui.IsItemActive(ctx)

  local bg = C.button
  local border = C.button_border
  if active then
    bg = held and C.button_act or (hovered and C.button_active_hov or C.button_active)
    border = C.button_active_border
  elseif danger then
    bg = hovered and 0x4A1C23FF or 0x221319FF
    border = hovered and 0xD5535378 or 0xD5535338
  elseif held then
    bg = C.button_act
  elseif hovered then
    bg = C.button_hov
    border = 0x5CFFB633
  end

  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, UI.M.radius_small)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, border, UI.M.radius_small, 0, 1.0)
  ImGui.DrawList_AddLine(dl, x + 1, y + 1, x + w - 1, y + 1, active and 0xFFFFFF18 or 0xFFFFFF0A, 1.0)

  return clicked, hovered, held
end

function UI.DrawValueBadge(ImGui, ctx, C, dl, x, y, w, h, text, active, font)
  local bg = active and 0x10291EFF or 0x0B0E12AA
  local border = active and 0x5CFFB655 or 0xFFFFFF12
  local text_col = active and C.accent or C.text_dim
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, UI.M.radius_small)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, border, UI.M.radius_small, 0, 1.0)
  UI.CenterTextInRect(ImGui, ctx, dl, x, y, w, h, text, text_col, font)
end

function UI.DrawAmountRail(ImGui, C, dl, x, y, w, h, norm, active)
  norm = math.max(0.0, math.min(1.0, norm or 0.0))
  local fill_w = math.floor(w * norm + 0.5)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x0E0F12FF, 2)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, 0xFFFFFF10, 2, 0, 1.0)
  if fill_w > 0 then
    ImGui.DrawList_AddRectFilled(dl, x + 1, y + 1, x + math.max(1, fill_w), y + h - 1, active and 0x7CFFC7FF or C.accent, 2)
  end
end

UI.UpdateTheme(UI.C)

return UI
