local RCCConfig = {}

RCCConfig.METRICS = {
  radius = 6,
  radius_small = 4,
  gap_tiny = 3,
  gap = 6,
  pad_x = 8,
  pad_y = 8,
  header_h = 18,
  row_h = 22,
  button_h = 18,
  button_h_large = 22,
  header_action_h = 16,
}

RCCConfig.COLORS = {
  accent = 0x5CFFB6FF,
  accent_dim = 0x5CFFB688,
  mute = 0xD55353FF,
  solo = 0xE4BD13FF,
  arm = 0xD55353FF,
  phase = 0x1E7B93FF,
  read = 0x32A852FF,
  write = 0xD55353FF,
  text_dim = 0xA9AFBBFF,
  blue = 0x163B2AFF,
  blue_dark = 0x10291EFF,
  green = 0x32A852FF,
  amber = 0xE4BD13FF,
  red = 0xD55353FF,
}

RCCConfig.STYLES = {
  panel_bg = 0x111318EE,
  panel_header = 0x181B20AA,
  panel_border = 0x2A2D34AA,
  panel_inner = 0x00000038,
  panel_highlight = 0xFFFFFF13,
  panel_separator = 0xFFFFFF07,
  text = 0xD6DAE1FF,
  text_dim = 0x8C94A08A,
  text_hover = 0xC2CAD6B8,
  button = 0x15171CFF,
  button_hover = 0x1E2229FF,
  button_pressed = 0x101217FF,
  button_active = 0x163B2AFF,
  button_active_hover = 0x1D5138FF,
  button_active_pressed = 0x10291EFF,
  button_border = 0xFFFFFF16,
  button_active_border = 0x5CFFB666,
  header_action = 0x12151AFF,
  header_action_hover = 0x1A1E24FF,
}

RCCConfig.UI = {
  font_family = "Segoe UI",
  font_size_main = 14,
  font_size_large = 16,
  font_size_small = 11,
  font_size_small_bold = 11,
  font_family_bold = "Segoe UI Bold",
  animation_speed_collapse = 9.5,
  animation_speed_expand = 12.0,
  animation_speed_hover = 13.0,
}

return RCCConfig
