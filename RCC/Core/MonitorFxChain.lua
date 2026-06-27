local MonitorFxChain = {}

local REC_FX_OFFSET = 0x1000000
local last_order_check = 0

local FX_ORDER = {
  {
    id = "reference",
    matches = {"RCC_RefPlayer", "RCC Reference Player"},
  },
  {
    id = "matrix",
    matches = {"RCC_MonitorMatrix", "RCC Monitor Matrix"},
  },
  {
    id = "analyzer",
    matches = {"RCC_AnalyzerTap", "RCC Analyzer Tap"},
  },
  {
    id = "roof_control",
    matches = {"roof_control", "roof|control"},
  },
  {
    id = "headphone_calibration",
    matches = {"Realphones", "realphones", "dSONIQ", "Sonarworks", "SoundID Reference", "Reference 4"},
  },
  {
    id = "post_cal_meter",
    matches = {"RCC Post Correction Meter", "RCC_PostCalMeter"},
  },
}

local function NameMatches(name, patterns)
  if not name then
    return false
  end

  for _, pattern in ipairs(patterns) do
    if name:find(pattern, 1, true) then
      return true
    end
  end

  return false
end

local function FindFx(master, patterns)
  local count = reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(master) or 0
  for index = 0, count - 1 do
    local fx_index = REC_FX_OFFSET + index
    local _, name = reaper.TrackFX_GetFXName(master, fx_index)
    if NameMatches(name, patterns) then
      return fx_index
    end
  end

  return -1
end

function MonitorFxChain.EnsureOrder(force)
  if not reaper.TrackFX_CopyToTrack then
    return true
  end

  local now = reaper.time_precise and reaper.time_precise() or 0
  if not force and now - last_order_check < 0.35 then
    return true
  end
  last_order_check = now

  local master = reaper.GetMasterTrack(0)
  if not master then
    return false, "Master track unavailable"
  end

  local target_slot = 0
  for _, spec in ipairs(FX_ORDER) do
    local expected_fx_index = REC_FX_OFFSET + target_slot
    local current_fx_index = FindFx(master, spec.matches)
    if current_fx_index >= 0 then
      if current_fx_index ~= expected_fx_index then
        reaper.TrackFX_CopyToTrack(master, current_fx_index, master, expected_fx_index, true)
      end
      target_slot = target_slot + 1
    end
  end

  return true, nil
end

function MonitorFxChain.DescribeOrder()
  return "Reference Player -> Monitor Matrix -> Analyzer Tap -> Headphone Calibration -> Post Correction Meter"
end

return MonitorFxChain
