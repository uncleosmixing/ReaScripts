local LevelBar = {}
local UIUtils = require("UIUtils")

local function WithAlpha(color, alpha)
  return (color & 0xFFFFFF00) | math.max(0, math.min(255, math.floor(alpha or 255)))
end

local function GetSegmentColor(norm, mode, cfg)
  local r, g, b
  if mode == "k14" or mode == "k12" or mode == "k20" then
    local dBr
    if mode == "k14" then dBr = -34.0 + norm * 38.0
    elseif mode == "k12" then dBr = -32.0 + norm * 36.0
    else dBr = -40.0 + norm * 44.0
    end
    
    if dBr <= 0.0 then -- Green zone
      local min_val = (mode == "k14" and -34.0 or (mode == "k12" and -32.0 or -40.0))
      local t = (dBr - min_val) / (0.0 - min_val)
      r = math.floor(0x1D + (0xE4 - 0x1D) * t)
      g = math.floor(0xA8 + (0xBD - 0xA8) * t)
      b = math.floor(0x52 + (0x13 - 0x52) * t)
    elseif dBr <= 2.0 then -- Amber zone (0 to +2 dBr)
      local t = dBr / 2.0
      r = math.floor(0xE4 + (0xD5 - 0xE4) * t)
      g = math.floor(0xBD + (0x53 - 0xBD) * t)
      b = math.floor(0x13 + (0x53 - 0x13) * t)
    else -- Red zone (+2 to +4 dBr)
      local t = math.min(1.0, (dBr - 2.0) / 2.0)
      r = math.floor(0xD5 + (0xFF - 0xD5) * t)
      g = math.floor(0x53 + (0x22 - 0x53) * t)
      b = math.floor(0x53 + (0x22 - 0x53) * t)
    end
  elseif mode == "ebu" or (cfg and cfg.target) then
    local target = (cfg and cfg.target) or -23.0
    local lufs = -40.0 + norm * 34.0
    if lufs <= target then
      local t = (lufs - (-40.0)) / math.max(1.0, target + 40.0)
      r = math.floor(0x1D + (0xE4 - 0x1D) * t)
      g = math.floor(0xA8 + (0xBD - 0xA8) * t)
      b = math.floor(0x52 + (0x13 - 0x52) * t)
    elseif lufs <= target + 3.0 then
      local t = (lufs - target) / 3.0
      r = math.floor(0xE4 + (0xD5 - 0xE4) * t)
      g = math.floor(0xBD + (0x53 - 0xBD) * t)
      b = math.floor(0x13 + (0x53 - 0x13) * t)
    else
      local t = math.min(1.0, (lufs - target - 3.0) / 8.0)
      r = math.floor(0xD5 + (0xFF - 0xD5) * t)
      g = math.floor(0x53 + (0x22 - 0x53) * t)
      b = math.floor(0x53 + (0x22 - 0x53) * t)
    end
  else -- standard dBFS mode
    if norm <= 0.762 then -- Green to Amber (-60 dB to -12 dB)
      local t = norm / 0.762
      r = math.floor(0x1D + (0xE4 - 0x1D) * t)
      g = math.floor(0xA8 + (0xBD - 0xA8) * t)
      b = math.floor(0x52 + (0x13 - 0x52) * t)
    elseif norm <= 0.905 then -- Amber to Red (-12 dB to -3 dB)
      local t = (norm - 0.762) / (0.905 - 0.762)
      r = math.floor(0xE4 + (0xD5 - 0xE4) * t)
      g = math.floor(0xBD + (0x53 - 0xBD) * t)
      b = math.floor(0x13 + (0x53 - 0x13) * t)
    else -- Red to Hot Red (-3 dB to +3 dB)
      local t = math.min(1.0, (norm - 0.905) / (1.0 - 0.905))
      r = math.floor(0xD5 + (0xFF - 0xD5) * t)
      g = math.floor(0x53 + (0x22 - 0x53) * t)
      b = math.floor(0x53 + (0x22 - 0x53) * t)
    end
  end
  return (r << 24) | (g << 16) | (b << 8)
end

function LevelBar.DrawSegmentedMeter(draw_list, draw_api, meter_x, y_top, meter_w, bar_h, rms_norm, peak_norm, hold_norm, mode, cfg)
  local N = math.floor(meter_w / 3)
  if N <= 0 then return end
  
  local seg_w = 2.0
  local gap_w = 1.0
  local total_w = N * 3 - 1
  local start_offset = math.floor((meter_w - total_w) * 0.5)
  
  -- Draw the background dark slot
  draw_api.rect_filled(draw_list, meter_x, y_top, meter_x + meter_w, y_top + bar_h, 0x0E0F12FF, 1.0)
  
  -- Calculate precise single-segment index for the Peak Hold Tick
  local hold_i = (hold_norm > 0) and (math.floor(hold_norm * (N - 1) + 0.5) + 1) or -1
  
  for i = 1, N do
    local norm = (i - 1) / math.max(1, N - 1)
    local seg_x = meter_x + start_offset + (i - 1) * 3
    
    -- Determine segment status
    local is_rms = norm <= (rms_norm or 0.0)
    local is_peak = norm <= (peak_norm or 0.0)
    local is_hold = (i == hold_i)
    
    local col = 0x1A1B20FF -- Unlit dark-slate segment
    
    if is_peak then
      col = GetSegmentColor(norm, mode, cfg) | 0xFF -- Peak layer: full-height, full brightness
    elseif is_rms then
      col = WithAlpha(GetSegmentColor(norm, mode, cfg), 0x72) -- RMS / short-term layer: dim underlay
    end
    
    -- Draw active or unlit segment (always uniform full height 8px)
    draw_api.rect_filled(draw_list, seg_x, y_top, seg_x + seg_w, y_top + bar_h, col, 0)

    if is_rms and not is_peak then
      draw_api.rect_filled(draw_list, seg_x, y_top + bar_h - 2, seg_x + seg_w, y_top + bar_h, WithAlpha(GetSegmentColor(norm, mode, cfg), 0xC8), 0)
    end
    
    -- Highlight the Peak Hold segment (sticks out by 1px on top and bottom)
    if is_hold then
      local tick_col = GetSegmentColor(hold_norm, mode, cfg) | 0xFF
      draw_api.rect_filled(draw_list, seg_x, y_top - 1, seg_x + seg_w, y_top + bar_h + 1, tick_col, 0)
    end
  end
end

return LevelBar
