local MonitorManager = {}
local AnalyzerTap = require("AnalyzerTap")
local ReferencePlayer = require("ReferencePlayer")
local GmemRead = require("GmemRead")
local MonitorMatrix = require("MonitorMatrix")
local MonitorFxChain = require("MonitorFxChain")
local HeadphoneCalibrationManager = require("HeadphoneCalibrationManager")

local MONITORS = {
  A = {
    hardware_output = nil,
  },
  B = {
    hardware_output = nil,
  },
  C = {
    hardware_output = nil,
  },
}

local DIM_DB = -20.0
local MASTER_MONO_ACTION_NAME = "Master track: Toggle stereo/mono (L+R)"
local master_mono_action_id = nil

local function GetMaster()
  return reaper.GetMasterTrack(0)
end

local function HasFlag(value, flag)
  return value % (flag * 2) >= flag
end

local function DbToVolume(db)
  if db <= -150 then
    return 0.0
  end

  return 10 ^ (db / 20)
end

local function VolumeToDb(volume)
  if volume <= 0 then
    return -150.0
  end

  return 20 * (math.log(volume) / math.log(10))
end

local function GetHardwareOutput(track, output_index)
  for send_index = 0, reaper.GetTrackNumSends(track, 1) - 1 do
    local dest_channel = reaper.GetTrackSendInfo_Value(track, 1, send_index, "I_DSTCHAN")
    if dest_channel % 1024 == output_index then
      return send_index
    end
  end

  return nil
end

local function SetHardwareOutputsMuted(track, muted)
  for send_index = 0, reaper.GetTrackNumSends(track, 1) - 1 do
    reaper.SetTrackSendInfo_Value(track, 1, send_index, "B_MUTE", muted and 1 or 0)
  end
end

local function SetHardwareOutputsMono(track, mono)
  for send_index = 0, reaper.GetTrackNumSends(track, 1) - 1 do
    reaper.SetTrackSendInfo_Value(track, 1, send_index, "B_MONO", mono and 1 or 0)
  end
end

local function FindActionByName(action_name)
  if master_mono_action_id ~= nil then
    return master_mono_action_id
  end

  local section = reaper.SectionFromUniqueID and reaper.SectionFromUniqueID(0) or nil
  for index = 0, 100000 do
    local command_id, name = reaper.kbd_enumerateActions(section, index)
    if command_id == 0 then
      break
    end

    if name == action_name then
      master_mono_action_id = command_id
      return master_mono_action_id
    end
  end

  master_mono_action_id = false
  return nil
end

local function EnsureHardwareOutput(track, output_index)
  local send_index = GetHardwareOutput(track, output_index)
  if send_index == nil then
    send_index = reaper.CreateTrackSend(track, nil)
  end

  if send_index and send_index >= 0 then
    reaper.SetTrackSendInfo_Value(track, 1, send_index, "B_MUTE", 0)
    reaper.SetTrackSendInfo_Value(track, 1, send_index, "D_VOL", 1.0)
    reaper.SetTrackSendInfo_Value(track, 1, send_index, "I_SRCCHAN", 0)
    reaper.SetTrackSendInfo_Value(track, 1, send_index, "I_DSTCHAN", output_index)
  end

  return send_index
end

local function ApplyMasterState(state)
  local master = GetMaster()
  local volume = state.volume

  if state.dim then
    volume = volume + DIM_DB
  end

  reaper.SetMediaTrackInfo_Value(master, "B_MUTE", state.mute and 1 or 0)
  reaper.SetMediaTrackInfo_Value(master, "D_VOL", DbToVolume(volume))
  reaper.SetMediaTrackInfo_Value(master, "D_WIDTH", state.mono and 0 or 1)
  SetHardwareOutputsMono(master, state.mono)
end

local function ApplyMonitorSelection(state)
  local master = GetMaster()
  local active_config = MONITORS[state.active_monitor]

  if not active_config or active_config.hardware_output == nil then
    return
  end

  for _, config in pairs(MONITORS) do
    if config.hardware_output ~= nil then
      local send_index = EnsureHardwareOutput(master, config.hardware_output)
      if send_index and send_index >= 0 then
        local muted = config.hardware_output ~= active_config.hardware_output
        reaper.SetTrackSendInfo_Value(master, 1, send_index, "B_MUTE", muted and 1 or 0)
      end
    end
  end
end

function MonitorManager.CreateState()
  local master = GetMaster()
  local master_volume = reaper.GetMediaTrackInfo_Value(master, "D_VOL")
  local master_mute = reaper.GetMediaTrackInfo_Value(master, "B_MUTE")
  local master_flags = reaper.GetMasterMuteSoloFlags()

  local state = {
    active_monitor = "A",
    mute = master_mute == 1,
    dim = false,
    mono = HasFlag(master_flags, 4),
    volume = VolumeToDb(master_volume),
    listen_mode = "normal",
    band_mode = "full",
    analyzer_max = {
      peak_l = 0,
      peak_r = 0,
      rms_l = 0,
      rms_r = 0,
      true_peak_l = 0,
      true_peak_r = 0,
    },
    ref_slots = {
      { name = "No reference track", path = nil, preview = nil },
      { name = "No reference track", path = nil, preview = nil },
      { name = "No reference track", path = nil, preview = nil },
      { name = "No reference track", path = nil, preview = nil },
      { name = "No reference track", path = nil, preview = nil },
      { name = "No reference track", path = nil, preview = nil },
      { name = "No reference track", path = nil, preview = nil },
      { name = "No reference track", path = nil, preview = nil },
      { name = "No reference track", path = nil, preview = nil },
      { name = "No reference track", path = nil, preview = nil },
    },
    ref_active_slot = 1,
    auto_gain_match = false,
    ref_mono = false,
    mix_loudness = -18.0,
    ref_loudness = -14.0,
    ref_gain_db_manual = 0.0,
    roof_bypass = true,
    roof_emulation_bypass = false,
    roof_mode = 0,
    roof_crossfeed = false,
    roof_cf_cutoff = 800,
    roof_cf_sup = 6.1,
    roof_preset_idx = 0,
    roof_cf_delay = 0.23,
    roof_correction = false,
    roof_preamp = 0.0,
    roof_headroom = -7.0,
    roof_presets = {},
  }
  HeadphoneCalibrationManager.InitState(state)
  return state
end

function MonitorManager.InitializeRouting(state)
  reaper.Undo_BeginBlock()
  local master = GetMaster()

  if reaper.GetTrackNumSends(master, 1) == 0 then
    EnsureHardwareOutput(master, 0)
  end

  SetHardwareOutputsMuted(master, false)
  ApplyMasterState(state)
  ApplyMonitorSelection(state)
  reaper.TrackList_AdjustWindows(false)
  reaper.Undo_EndBlock("RCC: use master hardware output", -1)
end

function MonitorManager.SwitchMonitor(state, monitor)
  if not MONITORS[monitor] then
    return
  end

  state.active_monitor = monitor
  ApplyMonitorSelection(state)
end

function MonitorManager.ToggleMute(state)
  state.mute = not state.mute
  ApplyMasterState(state)
end

function MonitorManager.ToggleDim(state)
  state.dim = not state.dim
  ApplyMasterState(state)
end

function MonitorManager.ToggleMono(state)
  state.mono = not state.mono
  local master_flags = reaper.GetMasterMuteSoloFlags()
  local master_is_mono = HasFlag(master_flags, 4)

  if master_is_mono ~= state.mono then
    local command_id = FindActionByName(MASTER_MONO_ACTION_NAME)
    if command_id then
      reaper.Main_OnCommand(command_id, 0)
    end
  end

  ApplyMasterState(state)
end

function MonitorManager.SetVolume(state, volume)
  state.volume = volume
  ApplyMasterState(state)
end

function MonitorManager.InstallAnalyzerTap(state)
  local _, matrix_error = MonitorMatrix.ResetInstall()
  if matrix_error then
    state.analyzer_error = matrix_error
    return false
  end

  local ok, error_message = AnalyzerTap.Install()
  state.analyzer_error = error_message
  if ok then
    MonitorMatrix.SetMode(state.listen_mode or "normal")
    MonitorMatrix.SetBand(state.band_mode or "full")
    MonitorFxChain.EnsureOrder(true)
  end
  return ok
end

function MonitorManager.ToggleListenMode(state, mode)
  if not mode then
    return
  end

  local next_mode = state.listen_mode == mode and "normal" or mode
  local ok, error_message = MonitorMatrix.SetMode(next_mode)
  state.analyzer_error = error_message

  if ok then
    state.listen_mode = next_mode
    MonitorFxChain.EnsureOrder(true)
  end
end

function MonitorManager.ToggleBandMode(state, band)
  if not band then
    return
  end

  local next_band = state.band_mode == band and "full" or band
  local ok, error_message = MonitorMatrix.SetBand(next_band)
  state.analyzer_error = error_message

  if ok then
    state.band_mode = next_band
    MonitorFxChain.EnsureOrder(true)
  end
end

function MonitorManager.ReadAnalyzer()
  local current_ok, _, analyzer_reinstalled = AnalyzerTap.EnsureCurrent()
  if not current_ok then
    -- Keep the UI alive; the install/update button can still recover manually.
  elseif analyzer_reinstalled then
    MonitorFxChain.EnsureOrder(true)
  end

  local analyzer = GmemRead.ReadAnalyzer()
  local master = GetMaster()

  if not analyzer.active then
    analyzer.peak_l = reaper.Track_GetPeakInfo(master, 0)
    analyzer.peak_r = reaper.Track_GetPeakInfo(master, 1)
    analyzer.true_peak_l = math.max(analyzer.true_peak_l or 0, analyzer.peak_l or 0)
    analyzer.true_peak_r = math.max(analyzer.true_peak_r or 0, analyzer.peak_r or 0)
  end

  analyzer.peak = math.max(analyzer.peak_l or 0, analyzer.peak_r or 0)
  analyzer.rms = math.max(analyzer.rms_l or 0, analyzer.rms_r or 0)
  return analyzer
end

function MonitorManager.UpdateAnalyzerMax(state, analyzer)
  if not analyzer.active then
    return
  end

  state.analyzer_max.peak_l = math.max(state.analyzer_max.peak_l, analyzer.peak_l)
  state.analyzer_max.peak_r = math.max(state.analyzer_max.peak_r, analyzer.peak_r)
  state.analyzer_max.rms_l = math.max(state.analyzer_max.rms_l, analyzer.rms_l)
  state.analyzer_max.rms_r = math.max(state.analyzer_max.rms_r, analyzer.rms_r)
  state.analyzer_max.true_peak_l = math.max(state.analyzer_max.true_peak_l, analyzer.true_peak_l or 0)
  state.analyzer_max.true_peak_r = math.max(state.analyzer_max.true_peak_r, analyzer.true_peak_r or 0)
end

function MonitorManager.ResetAnalyzerMax(state)
  state.analyzer_max.peak_l = 0
  state.analyzer_max.peak_r = 0
  state.analyzer_max.rms_l = 0
  state.analyzer_max.rms_r = 0
  state.analyzer_max.true_peak_l = 0
  state.analyzer_max.true_peak_r = 0
end

function MonitorManager.ValidateRouting()
  local warnings = {}
  local master = GetMaster()

  if reaper.GetTrackNumSends(master, 1) == 0 then
    warnings[#warnings + 1] = "Master has no hardware output"
  end

  return {
    ok = #warnings == 0,
    warnings = warnings,
  }
end

function MonitorManager.GetMonitors()
  return MONITORS
end

function MonitorManager.EnsureRefPlayerInstalled(state)
  local master = reaper.GetMasterTrack(0)
  if not master then return nil end

  local file_ok, file_error, file_changed = ReferencePlayer.EnsureFile()
  if not file_ok then
    state.analyzer_error = file_error
    return nil
  end

  local now = reaper.time_precise and reaper.time_precise() or 0
  if state.ref_player_fx_idx and not file_changed and now - (state.ref_fx_last_scan or 0) < 0.75 then
    return state.ref_player_fx_idx
  end
  state.ref_fx_last_scan = now
  
  local count = reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(master) or 0
  local player_fx_idx = nil
  local analyzer_fx_idx = nil
  local needs_order = false
  for index = 0, count - 1 do
    local fx_index = 0x1000000 + index
    local _, name = reaper.TrackFX_GetFXName(master, fx_index)
    if name then
      if name:find("RCC_RefPlayer", 1, true) or name:find("RCC Reference Player", 1, true) then
        if not player_fx_idx then player_fx_idx = fx_index end
      elseif name:find("RCC_AnalyzerTap", 1, true) or name:find("RCC Analyzer Tap", 1, true) then
        if not analyzer_fx_idx then analyzer_fx_idx = fx_index end
      end
    end
  end

  if file_changed and player_fx_idx then
    reaper.TrackFX_Delete(master, player_fx_idx)
    player_fx_idx = nil
    state.ref_loaded_path = nil
    state.ref_last_load_retry = nil
    state.ref_player_fx_idx = nil
    needs_order = true
  end

  if not player_fx_idx then
    local ok, fx_index_or_err = ReferencePlayer.Install()
    if ok then
      player_fx_idx = 0x1000000 + fx_index_or_err
      needs_order = true
    else
      state.analyzer_error = fx_index_or_err
      return nil
    end
  end

  -- Force the player to be at index 0 of the Monitoring FX chain (0x1000000)
  if player_fx_idx and player_fx_idx > 0x1000000 then
    if reaper.TrackFX_CopyToTrack then
      reaper.TrackFX_CopyToTrack(master, player_fx_idx, master, 0x1000000, true)
      player_fx_idx = 0x1000000
      needs_order = true
      
      -- Recalculate analyzer index since positions shifted
      analyzer_fx_idx = nil
      for index = 0, count - 1 do
        local fx_index = 0x1000000 + index
        local _, name = reaper.TrackFX_GetFXName(master, fx_index)
        if name and (name:find("RCC_AnalyzerTap", 1, true) or name:find("RCC Analyzer Tap", 1, true)) then
          analyzer_fx_idx = fx_index
          break
        end
      end
    end
  end

  -- Force the analyzer tap to be positioned AFTER the player (index 1 or later)
  if player_fx_idx == 0x1000000 and analyzer_fx_idx and analyzer_fx_idx <= player_fx_idx then
    if reaper.TrackFX_CopyToTrack then
      reaper.TrackFX_CopyToTrack(master, analyzer_fx_idx, master, 0x1000001, true)
      needs_order = true
    end
  end

  MonitorFxChain.EnsureOrder(needs_order)
  state.ref_player_fx_idx = player_fx_idx
  return player_fx_idx
end

return MonitorManager
