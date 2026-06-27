local RCCTheme = {}
local Config = require("RCCConfig")

local theme_cache = nil

function RCCTheme.Rgba(r, g, b, a)
  r = math.max(0, math.min(255, math.floor(r or 0)))
  g = math.max(0, math.min(255, math.floor(g or 0)))
  b = math.max(0, math.min(255, math.floor(b or 0)))
  a = math.max(0, math.min(255, math.floor(a or 255)))
  return (r << 24) | (g << 16) | (b << 8) | a
end

function RCCTheme.SplitRgba(color)
  return
    (color >> 24) & 0xFF,
    (color >> 16) & 0xFF,
    (color >> 8) & 0xFF,
    color & 0xFF
end

function RCCTheme.WithAlpha(color, alpha)
  return (color & 0xFFFFFF00) | math.max(0, math.min(255, math.floor(alpha or 255)))
end

function RCCTheme.MixColor(a, b, t, alpha)
  t = math.max(0.0, math.min(1.0, t or 0.0))
  local ar, ag, ab, aa = RCCTheme.SplitRgba(a)
  local br, bg, bb, ba = RCCTheme.SplitRgba(b)
  return RCCTheme.Rgba(
    ar + (br - ar) * t,
    ag + (bg - ag) * t,
    ab + (bb - ab) * t,
    alpha or (aa + (ba - aa) * t)
  )
end

function RCCTheme.Luma(color)
  local r, g, b = RCCTheme.SplitRgba(color)
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
end

function RCCTheme.EnsureMinLuma(color, min_luma, alpha)
  min_luma = min_luma or 0.0
  local current = RCCTheme.Luma(color)
  if current >= min_luma then
    return alpha and RCCTheme.WithAlpha(color, alpha) or color
  end

  local t = math.min(1.0, (min_luma - current) / math.max(0.001, 1.0 - current))
  return RCCTheme.MixColor(color, 0xFFFFFFFF, t, alpha or (color & 0xFF))
end

function RCCTheme.ThemeColor(keys, fallback)
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
        return RCCTheme.Rgba(r, g, b, 255)
      end
    end
  end

  return fallback
end

function RCCTheme.CurrentThemeId()
  if reaper.GetLastColorThemeFile then
    local ok, path = pcall(reaper.GetLastColorThemeFile)
    if ok and path then
      return tostring(path)
    end
  end

  return "default"
end

function RCCTheme.Refresh(force)
  local theme_id = RCCTheme.CurrentThemeId()
  if theme_cache and not force and theme_cache.id == theme_id then
    return theme_cache
  end

  local main_bg = RCCTheme.ThemeColor({
    "col_main_bg2",
    "col_main_bg",
    "col_arrangebg",
    "col_tracklistbg",
  }, 0x303030FF)
  local track_bg = RCCTheme.ThemeColor({
    "col_tcp_bg",
    "col_tracklistbg",
    "col_main_bg2",
  }, main_bg)

  local accent = 0x5CFFB6FF
  local panel_bg = 0x111318EE
  local readable_text = 0xD6DAE1FF

  theme_cache = {
    id = theme_id,
    main_bg = main_bg,
    window_bg = RCCTheme.MixColor(main_bg, track_bg, 0.18, 255),
    panel_bg = panel_bg,
    panel_header = 0x181B20AA,
    panel_border = 0x2A2D34AA,
    inner_border = 0x00000038,
    top_highlight = RCCTheme.MixColor(readable_text, 0xFFFFFFFF, 0.18, 22),
    panel_separator = 0xFFFFFF07,
    text = readable_text,
    text_dim = RCCTheme.EnsureMinLuma(RCCTheme.MixColor(readable_text, panel_bg, 0.34, 190), 0.46, 190),
    text_hover = RCCTheme.MixColor(readable_text, accent, 0.10, 255),
    text_muted = 0x8C94A08A,
    accent = accent,
    accent_dim = RCCTheme.WithAlpha(accent, 104),
    button = 0x15171CFF,
    button_hover = 0x1E2229FF,
    button_pressed = 0x101217FF,
    button_active = 0x163B2AFF,
    button_active_hover = 0x1D5138FF,
    button_active_pressed = 0x10291EFF,
    button_border = 0xFFFFFF16,
    button_active_border = RCCTheme.WithAlpha(accent, 112),
    header_action = 0x12151AFF,
    header_action_hover = 0x1A1E24FF,
  }

  return theme_cache
end

return RCCTheme
