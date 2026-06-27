local HeadphoneCalibrationManager = {}

local MonitorFxChain = require("MonitorFxChain")

local REC_FX_OFFSET = 0x1000000
local EXT_SECTION = "RCC"
local EXT_PROVIDER_KEY = "headphone_cal_provider"

local PROVIDERS = {
  {
    id = "roof",
    label = "Roof Control",
    kind = "internal",
    matches = {"roof_control", "roof|control"},
  },
  {
    id = "realphones",
    label = "Realphones",
    kind = "external",
    matches = {"Realphones", "realphones", "dSONIQ"},
  },
  {
    id = "sonarworks",
    label = "Sonarworks",
    kind = "external",
    matches = {"Sonarworks", "SoundID Reference", "Reference 4"},
  },
}

local PROVIDER_BY_ID = {}
for _, provider in ipairs(PROVIDERS) do
  PROVIDER_BY_ID[provider.id] = provider
end

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

local function FindMonitoringFx(patterns)
  local master = reaper.GetMasterTrack(0)
  if not master then
    return nil
  end

  local count = reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(master) or 0
  for index = 0, count - 1 do
    local fx_index = REC_FX_OFFSET + index
    local _, name = reaper.TrackFX_GetFXName(master, fx_index)
    if NameMatches(name, patterns) then
      return fx_index, name
    end
  end

  return nil
end

local function GetSelectedProviderId()
  local saved = reaper.GetExtState and reaper.GetExtState(EXT_SECTION, EXT_PROVIDER_KEY) or ""
  if PROVIDER_BY_ID[saved] then
    return saved
  end
  return "roof"
end

function HeadphoneCalibrationManager.GetProviders()
  return PROVIDERS
end

function HeadphoneCalibrationManager.GetProvider(id)
  return PROVIDER_BY_ID[id or GetSelectedProviderId()] or PROVIDER_BY_ID.roof
end

function HeadphoneCalibrationManager.InitState(state)
  state.hp_cal_provider = state.hp_cal_provider or GetSelectedProviderId()
end

function HeadphoneCalibrationManager.SetProvider(state, provider_id)
  if not PROVIDER_BY_ID[provider_id] then
    return false
  end

  state.hp_cal_provider = provider_id
  state.hp_cal_external_fx_idx = nil
  state.hp_cal_external_fx_name = nil
  if reaper.SetExtState then
    reaper.SetExtState(EXT_SECTION, EXT_PROVIDER_KEY, provider_id, true)
  end

  if reaper.TrackFX_SetEnabled then
    local master = reaper.GetMasterTrack(0)
    if master then
      for _, provider in ipairs(PROVIDERS) do
        local fx_index = FindMonitoringFx(provider.matches)
        if fx_index then
          reaper.TrackFX_SetEnabled(master, fx_index, provider.id == provider_id)
        end
      end
    end
  end

  MonitorFxChain.EnsureOrder(true)
  return true
end

function HeadphoneCalibrationManager.FindExternalProviderFx(state)
  local provider = HeadphoneCalibrationManager.GetProvider(state and state.hp_cal_provider)
  if provider.kind ~= "external" then
    return nil
  end

  local fx_index, fx_name = FindMonitoringFx(provider.matches)
  if state then
    state.hp_cal_external_fx_idx = fx_index
    state.hp_cal_external_fx_name = fx_name
    state.hp_cal_external_found = fx_index ~= nil
    state.hp_cal_external_active = false
    if fx_index and reaper.TrackFX_GetEnabled then
      local master = reaper.GetMasterTrack(0)
      local enabled = reaper.TrackFX_GetEnabled(master, fx_index)
      state.hp_cal_external_active = enabled == true or enabled == 1
    end
  end
  return fx_index, fx_name
end

function HeadphoneCalibrationManager.SetExternalProviderActive(state, active)
  local fx_index = HeadphoneCalibrationManager.FindExternalProviderFx(state)
  if not fx_index then
    return false
  end

  local master = reaper.GetMasterTrack(0)
  if not master or not reaper.TrackFX_SetEnabled then
    return false
  end

  reaper.TrackFX_SetEnabled(master, fx_index, active == true)
  state.hp_cal_external_active = active == true
  return true
end

return HeadphoneCalibrationManager
