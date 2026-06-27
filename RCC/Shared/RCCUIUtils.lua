local UIUtils = {}
local RCCTheme = require("RCCTheme")
local Config = require("RCCConfig")
local draw_api_cache = nil
local theme_cache = nil
local ImGui = nil

UIUtils.HEADER_HEIGHT = Config.METRICS.header_h
UIUtils.HEADER_LABEL_X = 9

UIUtils.METRIC = Config.METRICS

UIUtils.COLOR = Config.COLORS

UIUtils.STYLE = {}
for k, v in pairs(Config.STYLES) do
  UIUtils.STYLE[k] = v
end

function UIUtils.SetImGui(imgui)
  ImGui = imgui
end

local function Rgba(r, g, b, a)
  r = math.max(0, math.min(255, math.floor(r or 0)))
  g = math.max(0, math.min(255, math.floor(g or 0)))
  b = math.max(0, math.min(255, math.floor(b or 0)))
  a = math.max(0, math.min(255, math.floor(a or 255)))
  return (r << 24) | (g << 16) | (b << 8) | a
end

local function SplitRgba(color)
  return
    (color >> 24) & 0xFF,
    (color >> 16) & 0xFF,
    (color >> 8) & 0xFF,
    color & 0xFF
end

local function WithAlpha(color, alpha)
  return (color & 0xFFFFFF00) | math.max(0, math.min(255, math.floor(alpha or 255)))
end

local function MixColor(a, b, t, alpha)
  t = math.max(0.0, math.min(1.0, t or 0.0))
  local ar, ag, ab, aa = SplitRgba(a)
  local br, bg, bb, ba = SplitRgba(b)
  return Rgba(
    ar + (br - ar) * t,
    ag + (bg - ag) * t,
    ab + (bb - ab) * t,
    alpha or (aa + (ba - aa) * t)
  )
end

local function Luma(color)
  local r, g, b = SplitRgba(color)
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
end

local function EnsureMinLuma(color, min_luma, alpha)
  min_luma = min_luma or 0.0
  local current = Luma(color)
  if current >= min_luma then
    return alpha and WithAlpha(color, alpha) or color
  end

  local t = math.min(1.0, (min_luma - current) / math.max(0.001, 1.0 - current))
  return MixColor(color, 0xFFFFFFFF, t, alpha or (color & 0xFF))
end

local function ThemeColor(keys, fallback)
  if not reaper.GetThemeColor or not reaper.ColorFromNative then
    return fallback
  end

  if type(keys) == "string" then
    keys = { keys }
  end

  for _, key in ipairs(keys or {}) do
    local ok, native = pcall(reaper.GetThemeColor, key, 0)
    if ok and native and native >= 0 then
      local r, g, b = reaper.ColorFromNative(native)
      if r and g and b then
        return Rgba(r, g, b, 255)
      end
    end
  end

  return fallback
end

local function CurrentThemeId()
  if reaper.GetLastColorThemeFile then
    local ok, path = pcall(reaper.GetLastColorThemeFile)
    if ok and path then
      return tostring(path)
    end
  end

  return "default"
end

function UIUtils.RefreshTheme(force)
  theme_cache = RCCTheme.Refresh(force)

  -- Synchronize UIUtils.STYLE dynamically
  UIUtils.STYLE.panel_bg = theme_cache.panel_bg
  UIUtils.STYLE.panel_header = theme_cache.panel_header
  UIUtils.STYLE.panel_border = theme_cache.panel_border
  UIUtils.STYLE.panel_inner = theme_cache.inner_border
  UIUtils.STYLE.panel_highlight = theme_cache.top_highlight
  UIUtils.STYLE.panel_separator = theme_cache.panel_separator
  UIUtils.STYLE.text = theme_cache.text
  UIUtils.STYLE.text_dim = theme_cache.text_dim
  UIUtils.STYLE.text_hover = theme_cache.text_hover
  UIUtils.STYLE.accent = theme_cache.accent
  UIUtils.STYLE.accent_dim = theme_cache.accent_dim
  UIUtils.STYLE.button = theme_cache.button
  UIUtils.STYLE.button_hover = theme_cache.button_hover
  UIUtils.STYLE.button_pressed = theme_cache.button_pressed
  UIUtils.STYLE.button_active = theme_cache.button_active
  UIUtils.STYLE.button_active_hover = theme_cache.button_active_hover
  UIUtils.STYLE.button_active_pressed = theme_cache.button_active_pressed
  UIUtils.STYLE.button_border = theme_cache.button_border
  UIUtils.STYLE.button_active_border = theme_cache.button_active_border
  UIUtils.STYLE.header_action = theme_cache.header_action
  UIUtils.STYLE.header_action_hover = theme_cache.header_action_hover

  return theme_cache
end

function UIUtils.Theme()
  return UIUtils.RefreshTheme(false)
end

function UIUtils.ThemeColor(name, fallback)
  local theme = UIUtils.Theme()
  return theme[name] or fallback
end

function UIUtils.DbText(db)
  if db <= -149 then
    return "-inf"
  end

  return string.format("%.1f", db)
end

function UIUtils.Db(value)
  if value <= 0 then
    return -150.0
  end

  return 20 * (math.log(value) / math.log(10))
end

function UIUtils.TextWidth(ctx, text)
  local calc = ImGui and ImGui.CalcTextSize or reaper.ImGui_CalcTextSize
  if calc then
    local width = calc(ctx, text)
    if width then
      return width
    end
  end

  return #text * 7
end

function UIUtils.EaseSmooth(t)
  t = math.max(0.0, math.min(1.0, t or 0.0))
  return t * t * (3.0 - 2.0 * t)
end

function UIUtils.EaseOutCubic(t)
  t = math.max(0.0, math.min(1.0, t or 0.0))
  return 1.0 - (1.0 - t) ^ 3
end

function UIUtils.Approach(current, target, speed, dt)
  current = current or target or 0.0
  target = target or 0.0
  speed = speed or 10.0
  dt = math.max(0.0, math.min(0.05, dt or 0.0))
  return current + (target - current) * (1.0 - math.exp(-speed * dt))
end

function UIUtils.SliderDoubleReset(ctx, id, value, min_v, max_v, fmt, default)
  local slider = ImGui and ImGui.SliderDouble or reaper.ImGui_SliderDouble
  local is_hov = ImGui and ImGui.IsItemHovered or reaper.ImGui_IsItemHovered
  local is_mdc = ImGui and ImGui.IsMouseDoubleClicked or reaper.ImGui_IsMouseDoubleClicked

  local changed, new_value = slider(ctx, id, value, min_v, max_v, fmt or "%.2f")
  if is_hov and is_hov(ctx) and is_mdc and is_mdc(ctx, 0) then
    return true, default
  end
  return changed, new_value
end

function UIUtils.SliderIntReset(ctx, id, value, min_v, max_v, fmt, default)
  local slider = ImGui and ImGui.SliderInt or reaper.ImGui_SliderInt
  local is_hov = ImGui and ImGui.IsItemHovered or reaper.ImGui_IsItemHovered
  local is_mdc = ImGui and ImGui.IsMouseDoubleClicked or reaper.ImGui_IsMouseDoubleClicked

  local changed, new_value = slider(ctx, id, value, min_v, max_v, fmt or "%d")
  if is_hov and is_hov(ctx) and is_mdc and is_mdc(ctx, 0) then
    return true, default
  end
  return changed, new_value
end

function UIUtils.AnimateValue(state, key, target, speed)
  state.ui_anim_values = state.ui_anim_values or {}
  local now = reaper.time_precise and reaper.time_precise() or os.clock()
  local anim = state.ui_anim_values[key]
  if not anim then
    anim = { value = target or 0.0, last = now }
  end

  local dt = now - (anim.last or now)
  anim.last = now
  anim.value = UIUtils.Approach(anim.value, target or 0.0, speed or 10.0, dt)
  if math.abs(anim.value - (target or 0.0)) < 0.003 then
    anim.value = target or 0.0
  end
  state.ui_anim_values[key] = anim
  return anim.value
end

local function FitTextToWidth(ctx, text, max_w)
  text = tostring(text or "")
  max_w = math.max(0, max_w or 0)
  if UIUtils.TextWidth(ctx, text) <= max_w then
    return text
  end

  local ellipsis = "..."
  local ellipsis_w = UIUtils.TextWidth(ctx, ellipsis)
  if ellipsis_w > max_w then
    return ""
  end

  local lo, hi = 0, #text
  while lo < hi do
    local mid = math.ceil((lo + hi) * 0.5)
    if UIUtils.TextWidth(ctx, text:sub(1, mid)) + ellipsis_w <= max_w then
      lo = mid
    else
      hi = mid - 1
    end
  end

  return text:sub(1, lo) .. ellipsis
end

function UIUtils.CenterTextInRect(ctx, draw_list, x, y, w, h, text, color, font, font_size)
  text = tostring(text or "")
  local push_font = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
  local pop_font = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
  local calc_text = ImGui and ImGui.CalcTextSize or reaper.ImGui_CalcTextSize
  local add_text = ImGui and ImGui.DrawList_AddText or reaper.ImGui_DrawList_AddText

  if font then
    push_font(ctx, font, font_size)
  end

  local text_w = UIUtils.TextWidth(ctx, text)
  local text_h = font_size or 12
  if calc_text then
    local _, measured_h = calc_text(ctx, text)
    text_h = measured_h or text_h
  end

  add_text(
    draw_list,
    math.floor(x + (w - text_w) * 0.5 + 0.5),
    math.floor(y + (h - text_h) * 0.5 + 0.5),
    color or UIUtils.STYLE.text,
    text
  )

  if font then
    pop_font(ctx)
  end
end

function UIUtils.DrawButtonTextInRect(ctx, draw_list, x, y, w, h, text, color, font, font_size, pad_x, pad_y)
  pad_x = pad_x or 4
  pad_y = pad_y or 2

  local inner_x = x + pad_x
  local inner_y = y + pad_y
  local inner_w = math.max(1.0, (w or 1.0) - pad_x * 2)
  local inner_h = math.max(1.0, (h or 1.0) - pad_y * 2)

  if font then
    local push_font = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
    local pop_font = ImGui and ImGui.PopFont or reaper.ImGui_PopFont
    push_font(ctx, font, font_size)
    local fitted = FitTextToWidth(ctx, text, inner_w)
    pop_font(ctx)
    UIUtils.CenterTextInRect(ctx, draw_list, inner_x, inner_y, inner_w, inner_h, fitted, color, font, font_size)
  else
    UIUtils.CenterTextInRect(ctx, draw_list, inner_x, inner_y, inner_w, inner_h, FitTextToWidth(ctx, text, inner_w), color)
  end
end

function UIUtils.HeaderActionButton(ctx, id, label, x, y, w, h, active, small_font, small_font_size)
  h = h or UIUtils.METRIC.header_action_h
  local get_wdl = ImGui and ImGui.GetWindowDrawList or reaper.ImGui_GetWindowDrawList
  local set_csp = ImGui and ImGui.SetCursorScreenPos or reaper.ImGui_SetCursorScreenPos
  local inv_btn = ImGui and ImGui.InvisibleButton or reaper.ImGui_InvisibleButton
  local is_hov = ImGui and ImGui.IsItemHovered or reaper.ImGui_IsItemHovered
  local is_act = ImGui and ImGui.IsItemActive or reaper.ImGui_IsItemActive
  local add_rf = ImGui and ImGui.DrawList_AddRectFilled or reaper.ImGui_DrawList_AddRectFilled
  local add_r = ImGui and ImGui.DrawList_AddRect or reaper.ImGui_DrawList_AddRect

  local draw_list = get_wdl(ctx)

  set_csp(ctx, x, y)
  local clicked = inv_btn(ctx, id, w, h)
  local hovered = is_hov(ctx)
  local held = is_act(ctx)

  local bg
  if held then
    bg = UIUtils.STYLE.button_pressed
  elseif hovered or active then
    bg = UIUtils.STYLE.header_action_hover
  else
    bg = UIUtils.STYLE.header_action
  end

  local border = (hovered or active) and 0x5CFFB655 or 0xFFFFFF14
  local text = (hovered or active) and 0x5CFFB6DD or 0x8C94A0B0

  add_rf(draw_list, x, y, x + w, y + h, bg, UIUtils.METRIC.radius_small)
  add_r(draw_list, x, y, x + w, y + h, border, UIUtils.METRIC.radius_small, nil, 1.0)
  UIUtils.DrawButtonTextInRect(ctx, draw_list, x, y, w, h, label, text, small_font, small_font_size)

  return clicked, hovered
end

function UIUtils.HeaderActionButtonAlpha(ctx, id, label, x, y, w, h, active, alpha, small_font, small_font_size)
  alpha = math.max(0.0, math.min(1.0, alpha or 1.0))
  if alpha <= 0.01 then
    return false, false
  end

  local function fade(color)
    return WithAlpha(color, math.floor((color & 0xFF) * alpha + 0.5))
  end

  h = h or UIUtils.METRIC.header_action_h
  local get_wdl = ImGui and ImGui.GetWindowDrawList or reaper.ImGui_GetWindowDrawList
  local set_csp = ImGui and ImGui.SetCursorScreenPos or reaper.ImGui_SetCursorScreenPos
  local inv_btn = ImGui and ImGui.InvisibleButton or reaper.ImGui_InvisibleButton
  local is_hov = ImGui and ImGui.IsItemHovered or reaper.ImGui_IsItemHovered
  local is_act = ImGui and ImGui.IsItemActive or reaper.ImGui_IsItemActive
  local add_rf = ImGui and ImGui.DrawList_AddRectFilled or reaper.ImGui_DrawList_AddRectFilled
  local add_r = ImGui and ImGui.DrawList_AddRect or reaper.ImGui_DrawList_AddRect

  local draw_list = get_wdl(ctx)

  set_csp(ctx, x, y)
  local clicked = inv_btn(ctx, id, w, h)
  local hovered = is_hov(ctx)
  local held = is_act(ctx)

  local bg = held and UIUtils.STYLE.button_pressed
    or ((hovered or active) and UIUtils.STYLE.header_action_hover or UIUtils.STYLE.header_action)
  local border = (hovered or active) and 0x5CFFB655 or 0xFFFFFF14
  local text = (hovered or active) and 0x5CFFB6DD or 0x8C94A0B0

  add_rf(draw_list, x, y, x + w, y + h, fade(bg), UIUtils.METRIC.radius_small)
  add_r(draw_list, x, y, x + w, y + h, fade(border), UIUtils.METRIC.radius_small, nil, 1.0)
  UIUtils.DrawButtonTextInRect(ctx, draw_list, x, y, w, h, label, fade(text), small_font, small_font_size)

  return clicked, hovered
end

function UIUtils.GetHoverReveal(state, key, visible)
  local target = visible and 1.0 or 0.0
  return UIUtils.EaseOutCubic(UIUtils.AnimateValue(state, "hover_reveal_" .. tostring(key), target, 13.0))
end

local function PushNativeButtonTextAlign(ctx)
  local push_sv = ImGui and ImGui.PushStyleVar or reaper.ImGui_PushStyleVar
  local button_align = ImGui and ImGui.StyleVar_ButtonTextAlign or reaper.ImGui_StyleVar_ButtonTextAlign
  if not push_sv or not button_align then
    return 0
  end

  local ok = pcall(push_sv, ctx, button_align(), 0.5, 0.5)
  return ok and 1 or 0
end

local function PopNativeButtonTextAlign(ctx, count)
  if (count or 0) <= 0 then
    return
  end
  local pop_sv = ImGui and ImGui.PopStyleVar or reaper.ImGui_PopStyleVar
  if pop_sv then
    pop_sv(ctx, count)
  end
end

function UIUtils.StyledButton(ctx, label, width, height, selected)
  local btn = ImGui and ImGui.Button or reaper.ImGui_Button
  local push_sc = ImGui and ImGui.PushStyleColor or reaper.ImGui_PushStyleColor
  local pop_sc = ImGui and ImGui.PopStyleColor or reaper.ImGui_PopStyleColor
  local col_btn = ImGui and ImGui.Col_Button or reaper.ImGui_Col_Button
  local col_btn_h = ImGui and ImGui.Col_ButtonHovered or reaper.ImGui_Col_ButtonHovered
  local col_btn_a = ImGui and ImGui.Col_ButtonActive or reaper.ImGui_Col_ButtonActive

  if not selected then
    local align_count = PushNativeButtonTextAlign(ctx)
    local clicked = btn(ctx, label, width, height)
    PopNativeButtonTextAlign(ctx, align_count)
    return clicked
  end

  push_sc(ctx, col_btn(), UIUtils.COLOR.blue)
  push_sc(ctx, col_btn_h(), 0x1D5138FF)
  push_sc(ctx, col_btn_a(), UIUtils.COLOR.blue_dark)

  local align_count = PushNativeButtonTextAlign(ctx)
  local clicked = btn(ctx, label, width, height)
  PopNativeButtonTextAlign(ctx, align_count)

  pop_sc(ctx, 3)
  return clicked
end

function UIUtils.LightButton(ctx, label, width, height)
  local btn = ImGui and ImGui.Button or reaper.ImGui_Button
  local push_sc = ImGui and ImGui.PushStyleColor or reaper.ImGui_PushStyleColor
  local pop_sc = ImGui and ImGui.PopStyleColor or reaper.ImGui_PopStyleColor
  local col_btn = ImGui and ImGui.Col_Button or reaper.ImGui_Col_Button
  local col_btn_h = ImGui and ImGui.Col_ButtonHovered or reaper.ImGui_Col_ButtonHovered
  local col_btn_a = ImGui and ImGui.Col_ButtonActive or reaper.ImGui_Col_ButtonActive
  local col_txt = ImGui and ImGui.Col_Text or reaper.ImGui_Col_Text

  push_sc(ctx, col_btn(), 0x00000000)
  push_sc(ctx, col_btn_h(), 0xFFFFFF18)
  push_sc(ctx, col_btn_a(), 0xFFFFFF28)
  push_sc(ctx, col_txt(), 0xD8D8D8FF)

  local align_count = PushNativeButtonTextAlign(ctx)
  local clicked = btn(ctx, label, width, height)
  PopNativeButtonTextAlign(ctx, align_count)

  pop_sc(ctx, 4)
  return clicked
end

function UIUtils.PresetButton(ctx, label, width, height, active)
  local btn = ImGui and ImGui.Button or reaper.ImGui_Button
  local push_sc = ImGui and ImGui.PushStyleColor or reaper.ImGui_PushStyleColor
  local pop_sc = ImGui and ImGui.PopStyleColor or reaper.ImGui_PopStyleColor
  local col_btn = ImGui and ImGui.Col_Button or reaper.ImGui_Col_Button
  local col_btn_h = ImGui and ImGui.Col_ButtonHovered or reaper.ImGui_Col_ButtonHovered
  local col_btn_a = ImGui and ImGui.Col_ButtonActive or reaper.ImGui_Col_ButtonActive
  local col_txt = ImGui and ImGui.Col_Text or reaper.ImGui_Col_Text

  if active then
    push_sc(ctx, col_btn(), 0x163B2A66)
    push_sc(ctx, col_btn_h(), 0x1D5138AA)
    push_sc(ctx, col_btn_a(), 0x10291EFF)
    push_sc(ctx, col_txt(), 0x5CFFB6FF)
  else
    push_sc(ctx, col_btn(), 0x15171CFF)
    push_sc(ctx, col_btn_h(), 0x1E2229FF)
    push_sc(ctx, col_btn_a(), 0x101217FF)
    push_sc(ctx, col_txt(), 0x8C94A0FF)
  end

  local align_count = PushNativeButtonTextAlign(ctx)
  local clicked = btn(ctx, label, width, height)
  PopNativeButtonTextAlign(ctx, align_count)
  pop_sc(ctx, 4)
  return clicked
end

function UIUtils.PremiumMonitorButton(ctx, label, width, height, active)
  local base = active and UIUtils.STYLE.button_active or UIUtils.STYLE.button
  local hover = active and UIUtils.STYLE.button_active_hover or UIUtils.STYLE.button_hover
  local pressed = active and UIUtils.STYLE.button_active_pressed or UIUtils.STYLE.button_pressed
  local text = active and UIUtils.STYLE.accent or UIUtils.STYLE.text
  local border = active and UIUtils.STYLE.button_active_border or UIUtils.STYLE.button_border

  local get_csp = ImGui and ImGui.GetCursorScreenPos or reaper.ImGui_GetCursorScreenPos
  local get_wdl = ImGui and ImGui.GetWindowDrawList or reaper.ImGui_GetWindowDrawList
  local inv_btn = ImGui and ImGui.InvisibleButton or reaper.ImGui_InvisibleButton
  local is_hov = ImGui and ImGui.IsItemHovered or reaper.ImGui_IsItemHovered
  local is_act = ImGui and ImGui.IsItemActive or reaper.ImGui_IsItemActive
  local add_rf = ImGui and ImGui.DrawList_AddRectFilled or reaper.ImGui_DrawList_AddRectFilled
  local add_r = ImGui and ImGui.DrawList_AddRect or reaper.ImGui_DrawList_AddRect

  local x, y = get_csp(ctx)
  local draw_list = get_wdl(ctx)
  local id = tostring(label or "")
  local visible_label = id:gsub("##.*$", "")

  width = math.max(1.0, width or 1.0)
  height = math.max(1.0, height or 1.0)
  local clicked = inv_btn(ctx, id, width, height)
  local hovered = is_hov(ctx)
  local held = is_act(ctx)
  local bg = held and pressed or (hovered and hover or base)

  add_rf(draw_list, x, y, x + width, y + height, bg, UIUtils.METRIC.radius_small)
  add_r(draw_list, x, y, x + width, y + height, border, UIUtils.METRIC.radius_small, nil, 1.0)
  UIUtils.DrawButtonTextInRect(ctx, draw_list, x, y, width, height, visible_label, text)

  return clicked
end

function UIUtils.ThemeMonitorButton(ctx, label, width, height, active)
  local theme = UIUtils.Theme()
  local base = active and theme.button_active or theme.button
  local hover = active and theme.button_active_hover or theme.button_hover
  local pressed = active and theme.button_active_pressed or theme.button_pressed
  local text = active and theme.accent or theme.text
  local border = active and theme.button_active_border or theme.button_border

  local get_csp = ImGui and ImGui.GetCursorScreenPos or reaper.ImGui_GetCursorScreenPos
  local get_wdl = ImGui and ImGui.GetWindowDrawList or reaper.ImGui_GetWindowDrawList
  local inv_btn = ImGui and ImGui.InvisibleButton or reaper.ImGui_InvisibleButton
  local is_hov = ImGui and ImGui.IsItemHovered or reaper.ImGui_IsItemHovered
  local is_act = ImGui and ImGui.IsItemActive or reaper.ImGui_IsItemActive
  local add_rf = ImGui and ImGui.DrawList_AddRectFilled or reaper.ImGui_DrawList_AddRectFilled
  local add_r = ImGui and ImGui.DrawList_AddRect or reaper.ImGui_DrawList_AddRect
  local x, y = get_csp(ctx)
  local draw_list = get_wdl(ctx)
  local id = tostring(label or "")
  local visible_label = id:gsub("##.*$", "")

  width = math.max(1.0, width or 1.0)
  height = math.max(1.0, height or 1.0)
  local clicked = inv_btn(ctx, id, width, height)
  local hovered = is_hov(ctx)
  local held = is_act(ctx)
  local bg = held and pressed or (hovered and hover or base)

  add_rf(draw_list, x, y, x + width, y + height, bg, 4.0)
  add_r(draw_list, x, y, x + width, y + height, border, 4.0, nil, 1.0)
  UIUtils.DrawButtonTextInRect(ctx, draw_list, x, y, width, height, visible_label, text)

  return clicked
end

function UIUtils.GetDrawApi()
  if draw_api_cache then
    return draw_api_cache
  end

  local api = {}

  api.get_draw_list = ImGui and ImGui.GetWindowDrawList or reaper.ImGui_GetWindowDrawList
  api.get_cursor_pos = ImGui and ImGui.GetCursorScreenPos or reaper.ImGui_GetCursorScreenPos
  api.dummy = ImGui and ImGui.Dummy or reaper.ImGui_Dummy
  api.rect_filled = ImGui and ImGui.DrawList_AddRectFilled or reaper.ImGui_DrawList_AddRectFilled
  api.rect = ImGui and ImGui.DrawList_AddRect or reaper.ImGui_DrawList_AddRect
  api.line = ImGui and ImGui.DrawList_AddLine or reaper.ImGui_DrawList_AddLine
  api.circle_filled = ImGui and ImGui.DrawList_AddCircleFilled or reaper.ImGui_DrawList_AddCircleFilled
  api.circle = ImGui and ImGui.DrawList_AddCircle or reaper.ImGui_DrawList_AddCircle
  api.path_clear = ImGui and ImGui.DrawList_PathClear or reaper.ImGui_DrawList_PathClear
  api.path_arc_to = ImGui and ImGui.DrawList_PathArcTo or reaper.ImGui_DrawList_PathArcTo
  api.path_stroke = ImGui and ImGui.DrawList_PathStroke or reaper.ImGui_DrawList_PathStroke
  api.text = ImGui and ImGui.DrawList_AddText or reaper.ImGui_DrawList_AddText

  -- Validate that all required DrawList APIs are fully loaded to prevent nil-call crashes
  if api.get_draw_list and api.get_cursor_pos and api.dummy and
     api.rect_filled and api.rect and api.line and
     api.circle_filled and api.circle and api.text then
    draw_api_cache = api
    return draw_api_cache
  end

  return nil
end

function UIUtils.DrawVolumetricContainer(draw_list, draw_api, x, y, right, bottom, bg_color, border_color, rounding)
  -- 1. Soft, Deep Matte Drop Shadows
  draw_api.rect(draw_list, x - 3, y + 2, right + 3, bottom + 6, 0x0000000A, rounding + 1.5, nil, 3.0)
  draw_api.rect(draw_list, x - 1, y + 1, right + 1, bottom + 3, 0x0000001A, rounding + 0.5, nil, 1.5)
  draw_api.rect(draw_list, x, y + 1, right, bottom + 1, 0x0000002A, rounding, nil, 1.0)

  -- 2. Deep Obsidian Matte Background
  local rich_bg = (bg_color == 0x1A1A1AFF) and 0x121316FF or bg_color
  draw_api.rect_filled(draw_list, x, y, right, bottom, rich_bg, rounding)

  -- 3. Matte Edge Border
  local rich_border = (border_color == 0x333333FF) and 0x24252AFF or border_color
  draw_api.rect(draw_list, x, y, right, bottom, rich_border, rounding, nil, 1.0)

  -- 4. Premium Recessed Inner Shadow
  draw_api.line(draw_list, x + rounding, y + 1, right - rounding, y + 1, 0x00000055, 1.0)
  draw_api.line(draw_list, x + rounding + 2, y + 2, right - rounding - 2, y + 2, 0x00000022, 1.0)

  -- 5. Soft Matte Top Highlight
  draw_api.line(draw_list, x + rounding, y, right - rounding, y, 0xFFFFFF12, 1.0)
end

function UIUtils.DrawInstrumentPanel(draw_list, draw_api, x, y, right, bottom, rounding)
  rounding = rounding or UIUtils.METRIC.radius

  -- 1. Soft, Deep Matte Drop Shadows (matching ProInspector's design)
  draw_api.rect(draw_list, x - 3, y + 2, right + 3, bottom + 6, 0x0000000A, rounding + 1.5, nil, 3.0)
  draw_api.rect(draw_list, x - 1, y + 1, right + 1, bottom + 3, 0x0000001A, rounding + 0.5, nil, 1.5)
  draw_api.rect(draw_list, x, y + 1, right, bottom + 1, 0x0000002A, rounding, nil, 1.0)

  -- 2. Smoked-glass panel body, header, border, sheen
  draw_api.rect_filled(draw_list, x, y, right, bottom, UIUtils.STYLE.panel_bg, rounding)
  draw_api.rect_filled(draw_list, x + 1, y + 1, right - 1, y + 17, UIUtils.STYLE.panel_header, rounding)
  draw_api.line(draw_list, x + rounding, y + 1, right - rounding, y + 1, UIUtils.STYLE.panel_highlight, 1.0)
  draw_api.line(draw_list, x + rounding, y + 18, right - rounding, y + 18, UIUtils.STYLE.panel_separator, 1.0)
  draw_api.rect(draw_list, x, y, right, bottom, UIUtils.STYLE.panel_border, rounding, nil, 1.0)
  draw_api.rect(draw_list, x + 1, y + 1, right - 1, bottom - 1, UIUtils.STYLE.panel_inner, math.max(0, rounding - 1), nil, 1.0)
end

function UIUtils.HeaderTextY(ctx, panel_y, text, small_font, small_font_size)
  local header_top = panel_y
  local header_h = UIUtils.HEADER_HEIGHT
  local text_h = small_font_size or 10

  local calc_t = ImGui and ImGui.CalcTextSize or reaper.ImGui_CalcTextSize
  local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
  local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont

  if calc_t then
    if small_font then
      push_f(ctx, small_font, small_font_size)
    end
    local _, measured_h = calc_t(ctx, text or "")
    if small_font then
      pop_f(ctx)
    end
    if measured_h and measured_h > 0 then
      text_h = measured_h
    end
  end

  return math.floor(header_top + math.max(0, (header_h - text_h) * 0.5) + 0.5)
end

function UIUtils.DrawModuleLabel(ctx, draw_list, draw_api, x, y, label, small_font, small_font_size)
  if not draw_api.text then
    return
  end

  local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
  local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont

  if small_font then
    push_f(ctx, small_font, small_font_size)
  end
  draw_api.text(draw_list, x + UIUtils.HEADER_LABEL_X, UIUtils.HeaderTextY(ctx, y, label, small_font, small_font_size), UIUtils.STYLE.text_dim, label)
  if small_font then
    pop_f(ctx)
  end
end

function UIUtils.GetCollapseState(state, id)
  state.ui_collapsed_panels = state.ui_collapsed_panels or {}
  return state.ui_collapsed_panels[id] == true
end

function UIUtils.ToggleCollapseState(state, id)
  state.ui_collapsed_panels = state.ui_collapsed_panels or {}
  state.ui_collapsed_panels[id] = not state.ui_collapsed_panels[id]
end

local function PanelOrderIndex(order, id)
  for i, value in ipairs(order or {}) do
    if value == id then
      return i
    end
  end
  return nil
end

function UIUtils.MovePanelBefore(state, dragged_id, target_id)
  if not state or not state.ui_panel_order or dragged_id == target_id then
    return false
  end

  local from = PanelOrderIndex(state.ui_panel_order, dragged_id)
  local to = PanelOrderIndex(state.ui_panel_order, target_id)
  if not from or not to then
    return false
  end

  local item = table.remove(state.ui_panel_order, from)
  if from < to then
    to = to - 1
  end
  table.insert(state.ui_panel_order, to, item)
  state.ui_panel_order_dirty = true
  return true
end

function UIUtils.MovePanelAfter(state, dragged_id, target_id)
  if not state or not state.ui_panel_order or dragged_id == target_id then
    return false
  end

  local from = PanelOrderIndex(state.ui_panel_order, dragged_id)
  local to = PanelOrderIndex(state.ui_panel_order, target_id)
  if not from or not to then
    return false
  end

  local item = table.remove(state.ui_panel_order, from)
  if from < to then
    to = to - 1
  end
  table.insert(state.ui_panel_order, to + 1, item)
  state.ui_panel_order_dirty = true
  return true
end

function UIUtils.GetCollapsiblePanelHeight(state, id, full_height, collapsed_height)
  collapsed_height = collapsed_height or 22
  full_height = math.max(collapsed_height, full_height or collapsed_height)

  state.ui_collapse_anim = state.ui_collapse_anim or {}

  local collapsed = UIUtils.GetCollapseState(state, id)
  local target = collapsed and 0.0 or 1.0
  local now = reaper.time_precise and reaper.time_precise() or os.clock()
  local anim = state.ui_collapse_anim[id]

  if not anim then
    anim = {
      value = target,
      target = target,
      last = now,
    }
  end

  local dt = math.max(0.0, math.min(0.05, now - (anim.last or now)))
  anim.last = now
  anim.target = target

  local speed = target > anim.value and 9.5 or 12.0
  anim.value = anim.value + (target - anim.value) * (1.0 - math.exp(-speed * dt))
  if math.abs(anim.value - target) < 0.003 then
    anim.value = target
  end

  state.ui_collapse_anim[id] = anim

  local eased = UIUtils.EaseSmooth(anim.value)
  local height = math.floor(collapsed_height + (full_height - collapsed_height) * eased + 0.5)
  return height, collapsed, anim.value, eased
end

function UIUtils.BeginAnimatedPanelBodyClip(ctx, x, y, right, bottom, collapse_anim)
  if (collapse_anim or 0.0) <= 0.012 or bottom <= y + UIUtils.HEADER_HEIGHT + 1 then
    return false
  end

  local push_cr = ImGui and ImGui.PushClipRect or reaper.ImGui_PushClipRect
  if push_cr then
    push_cr(ctx, x, y + UIUtils.HEADER_HEIGHT, right, bottom, true)
    return true
  end

  return true
end

function UIUtils.EndAnimatedPanelBodyClip(ctx, active)
  local pop_cr = ImGui and ImGui.PopClipRect or reaper.ImGui_PopClipRect
  if active and pop_cr then
    pop_cr(ctx)
  end
end

function UIUtils.DrawCollapsibleModuleLabel(ctx, draw_list, draw_api, x, y, label, panel_id, state, small_font, small_font_size)
  local text_w = UIUtils.TextWidth(ctx, label or "")
  local hit_w = math.max(24, text_w + 8)
  local hit_h = UIUtils.HEADER_HEIGHT
  local label_x = x + UIUtils.HEADER_LABEL_X - 2
  local label_y = y

  local get_csp = ImGui and ImGui.GetCursorScreenPos or reaper.ImGui_GetCursorScreenPos
  local set_csp = ImGui and ImGui.SetCursorScreenPos or reaper.ImGui_SetCursorScreenPos
  local inv_btn = ImGui and ImGui.InvisibleButton or reaper.ImGui_InvisibleButton
  local is_hov = ImGui and ImGui.IsItemHovered or reaper.ImGui_IsItemHovered
  local set_mc = ImGui and ImGui.SetMouseCursor or reaper.ImGui_SetMouseCursor
  local mc_hand = ImGui and ImGui.MouseCursor_Hand or reaper.ImGui_MouseCursor_Hand
  local push_f = ImGui and ImGui.PushFont or reaper.ImGui_PushFont
  local pop_f = ImGui and ImGui.PopFont or reaper.ImGui_PopFont

  local saved_x, saved_y = get_csp(ctx)

  set_csp(ctx, label_x, label_y)
  local clicked = inv_btn(ctx, "##collapse_panel_" .. tostring(panel_id), hit_w, hit_h)

  local hovered = is_hov(ctx)
  if hovered and set_mc and mc_hand then
    set_mc(ctx, mc_hand())
  end

  if clicked then
    UIUtils.ToggleCollapseState(state, panel_id)
  end

  set_csp(ctx, saved_x, saved_y)

  if draw_api.text then
    if small_font then
      push_f(ctx, small_font, small_font_size)
    end
    draw_api.text(
      draw_list,
      x + UIUtils.HEADER_LABEL_X,
      UIUtils.HeaderTextY(ctx, y, label, small_font, small_font_size),
      (state and state.ui_panel_drag_id == panel_id) and 0x5CFFB6CC or (hovered and UIUtils.STYLE.text_hover or UIUtils.STYLE.text_dim),
      label
    )
    if small_font then
      pop_f(ctx)
    end
  end
end

return UIUtils
