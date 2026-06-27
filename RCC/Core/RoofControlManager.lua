local RoofControlManager = {}
local RoofControlInstaller = require("RoofControlInstaller")
local MonitorFxChain = require("MonitorFxChain")

local sep = package.config:sub(1, 1)
local install_checked = false
local install_ok = false
local install_error = nil
local backend_last_check = 0
local fx_last_scan = 0

local PARAM_BYPASS = 0
local PARAM_HEADROOM = 1
local PARAM_MODE = 2
local PARAM_EMULATION_BYPASS = 3
local PARAM_CROSSFEED = 4
local PARAM_CF_CUTOFF = 5
local PARAM_CF_SUPPRESSION = 6
local PARAM_PRESET_INDEX = 7
local PARAM_CF_DELAY = 8
local PARAM_PHONES_CORRECTION = 9
local PARAM_PREAMP = 10
local EXPECTED_PARAM_COUNT = 11

local function SetParam(master, fx_index, param_index, value)
  if param_index == PARAM_BYPASS
    or param_index == PARAM_MODE
    or param_index == PARAM_EMULATION_BYPASS
    or param_index == PARAM_CROSSFEED
    or param_index == PARAM_PHONES_CORRECTION then
    if reaper.TrackFX_SetParamNormalized then
      reaper.TrackFX_SetParamNormalized(master, fx_index, param_index, value)
      return
    end
  end

  if param_index == PARAM_MODE then
    reaper.TrackFX_SetParam(master, fx_index, param_index, value * 6)
  else
    reaper.TrackFX_SetParam(master, fx_index, param_index, value)
  end
end

local function PathJoin(...)
  local parts = {...}
  local result = ""
  for i, part in ipairs(parts) do
    if part ~= "" then
      if result == "" then
        result = part
      else
        local ends_with_sep = result:sub(-1) == sep
        local starts_with_sep = part:sub(1, 1) == sep
        if ends_with_sep and starts_with_sep then
          result = result .. part:sub(2)
        elseif not ends_with_sep and not starts_with_sep then
          result = result .. sep .. part
        else
          result = result .. part
        end
      end
    end
  end
  return result
end

local function Trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function FileExists(path)
  local file = io.open(path, "rb")
  if file then
    file:close()
    return true
  end
  return false
end

local function ReadFile(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function WriteFile(path, content)
  local file = io.open(path, "wb")
  if not file then
    return false
  end
  file:write(content)
  file:close()
  return true
end

local function AppendLine(path, line)
  local existing = ReadFile(path) or ""
  local file = io.open(path, "a")
  if not file then
    return false
  end
  if existing ~= "" and not existing:match("\n$") then
    file:write("\n")
  end
  file:write(line, "\n")
  file:close()
  return true
end

local DEMO_PROFILE_NAMES = {
  ["Audio-Technica ATH-M50x.txt"] = true,
  ["Beyerdynamic DT 990 Pro.txt"] = true,
  ["Sennheiser HD 600.txt"] = true,
}

local function IsDemoProfile(file_name)
  return DEMO_PROFILE_NAMES[Trim(file_name)] == true
end

local function ListProfileFiles(profile_dir)
  local files = {}
  if not reaper.EnumerateFiles then
    return files
  end

  local index = 0
  while true do
    local file_name = reaper.EnumerateFiles(profile_dir, index)
    if not file_name then
      break
    end
    if file_name:lower():match("%.txt$") and not IsDemoProfile(file_name) then
      files[#files + 1] = file_name
    end
    index = index + 1
  end
  table.sort(files)
  return files
end

local function WriteProfileDatabase(db_path, files)
  local file = io.open(db_path, "w")
  if not file then
    return false
  end
  for _, file_name in ipairs(files) do
    file:write(file_name, "\n")
  end
  file:close()
  return true
end

local function SanitizeFileName(name)
  local cleaned = Trim(name):gsub("[\\/:*?\"<>|]", "_"):gsub("%s+", " ")
  cleaned = cleaned:gsub("^%.+", ""):gsub("%.+$", "")
  if cleaned == "" then
    cleaned = "AutoEq Profile"
  end
  return cleaned
end

local function Stem(path)
  local name = tostring(path or ""):match("([^\\/]+)$") or "AutoEq Profile"
  return (name:gsub("%.[^%.]+$", ""))
end

local function ParentName(path)
  local parent = tostring(path or ""):match("^(.*)[\\/][^\\/]+$")
  if not parent then
    return nil
  end
  return parent:match("([^\\/]+)$")
end

local function MakeUniqueFileName(dir, base)
  local root = SanitizeFileName(base)
  local candidate = root .. ".txt"
  local index = 2
  while FileExists(PathJoin(dir, candidate)) do
    candidate = string.format("%s (%d).txt", root, index)
    index = index + 1
  end
  return candidate
end

local function HasCurrentRoofControlLayout(master, fx_index)
  if reaper.TrackFX_GetNumParams then
    local param_count = reaper.TrackFX_GetNumParams(master, fx_index)
    if param_count and param_count < EXPECTED_PARAM_COUNT then
      return false
    end
  end

  if reaper.TrackFX_GetParamName then
    local _, name = reaper.TrackFX_GetParamName(master, fx_index, PARAM_PHONES_CORRECTION)
    name = tostring(name or ""):lower()
    if name ~= "" and not name:find("phones", 1, true) and not name:find("correction", 1, true) then
      return false
    end
  end

  return true
end

local function ParseAutoEqProfile(path)
  local content = ReadFile(path)
  if not content then
    return nil, "Cannot read selected AutoEq file"
  end

  local output = {}
  local filter_count = 0
  local preamp = content:match("[Pp]reamp:%s*([%+%-%.%d]+)%s*dB")
  if preamp then
    output[#output + 1] = string.format("Preamp: %.1f dB", tonumber(preamp) or 0)
  else
    output[#output + 1] = "Preamp: 0.0 dB"
  end

  for line in content:gmatch("[^\r\n]+") do
    local filter_type, freq, gain, q = line:match("ON%s+([A-Z]+)%s+Fc%s+([%+%-%.%d]+)%s+Hz%s+Gain%s+([%+%-%.%d]+)%s+dB%s+Q%s+([%+%-%.%d]+)")
    if filter_type == "LS" then
      filter_type = "LSC"
    elseif filter_type == "HS" then
      filter_type = "HSC"
    end

    if filter_type == "PK" or filter_type == "LSC" or filter_type == "HSC" then
      filter_count = filter_count + 1
      output[#output + 1] = string.format(
        "Filter %d: ON %s Fc %.3f Hz Gain %.3f dB Q %.3f",
        filter_count,
        filter_type,
        tonumber(freq) or 0,
        tonumber(gain) or 0,
        tonumber(q) or 1
      )
    end
  end

  if filter_count == 0 then
    return nil, "No supported AutoEq filters found"
  end

  return table.concat(output, "\n") .. "\n", nil
end

function RoofControlManager.EnsureInstalled(state)
  if not install_checked then
    install_checked = true
    local ok, err = RoofControlInstaller.Install()
    install_ok = ok
    install_error = err
    if not ok then
      state.analyzer_error = "Installation failed: " .. tostring(err)
      return false
    end
  end

  if not install_ok then
    state.analyzer_error = "Installation failed: " .. tostring(install_error)
    return false
  end

  local now = reaper.time_precise and reaper.time_precise() or 0
  if now - backend_last_check > 1.0 then
    backend_last_check = now
    reaper.gmem_attach("roof_mem")
    if reaper.gmem_read(5) ~= 1.0 then
      local ok = RoofControlInstaller.RunBackend()
      if not ok then
        state.analyzer_error = "Failed to launch roof_bubrik backend"
      end
    end
  end

  return true
end

function RoofControlManager.EnsureFxInstalled(state)
  local master = reaper.GetMasterTrack(0)
  if not master then return nil end

  -- 1. Ensure core components are in place
  if not RoofControlManager.EnsureInstalled(state) then
    return nil
  end

  local now = reaper.time_precise and reaper.time_precise() or 0
  if state.roof_fx_idx and now - fx_last_scan < 0.75 then
    if HasCurrentRoofControlLayout(master, state.roof_fx_idx) then
      return state.roof_fx_idx
    end
    state.roof_fx_idx = nil
  end
  fx_last_scan = now

  -- 2. Search for the plugin in Monitoring FX chain
  local count = reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(master) or 0
  local fx_index = nil
  for index = 0, count - 1 do
    local idx = 0x1000000 + index
    local _, name = reaper.TrackFX_GetFXName(master, idx)
    if name and (name:find("roof_control", 1, true) or name:find("roof|control", 1, true)) then
      fx_index = idx
      break
    end
  end

  if fx_index and not HasCurrentRoofControlLayout(master, fx_index) then
    reaper.TrackFX_Delete(master, fx_index)
    fx_index = nil
    state.roof_fx_idx = nil
  end

  -- 3. Install if not found
  if not fx_index then
    local installed_idx = reaper.TrackFX_AddByName(master, "roof_control", true, 1)
    if installed_idx and installed_idx >= 0 then
      fx_index = 0x1000000 + installed_idx
      MonitorFxChain.EnsureOrder(true)
    else
      state.analyzer_error = "Cannot load roof_control JSFX"
      return nil
    end
  end

  -- 4. Apply strict Post-Analyzer ordering.
  MonitorFxChain.EnsureOrder()

  -- Recalculate index after potential reordering
  count = reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(master) or 0
  for index = 0, count - 1 do
    local idx = 0x1000000 + index
    local _, name = reaper.TrackFX_GetFXName(master, idx)
    if name and (name:find("roof_control", 1, true) or name:find("roof|control", 1, true)) then
      fx_index = idx
      break
    end
  end

  state.roof_fx_idx = fx_index
  return fx_index
end

function RoofControlManager.LoadPresets(state)
  state.roof_presets = {}
  state.roof_presets_loaded = true
  local db_path = PathJoin(reaper.GetResourcePath(), "Data", "roof_control", "hp.db")
  local profile_dir = PathJoin(reaper.GetResourcePath(), "Data", "roof_control", "phones_eq")
  
  local file = io.open(db_path, "r")
  if not file then
    local files = ListProfileFiles(profile_dir)
    WriteProfileDatabase(db_path, files)
    file = io.open(db_path, "r")
  end
  if not file then
    return
  end

  local loaded_count = 0
  local db_files = {}
  local db_changed = false
  for line in file:lines() do
    local clean = Trim(line)
    if clean ~= "" then
      if IsDemoProfile(clean) then
        db_changed = true
      else
      -- Get display name (remove .txt extension)
      local name = clean
      local dot_pos = clean:find("%.txt$")
      if dot_pos then
        name = clean:sub(1, dot_pos - 1)
      end
      
      table.insert(state.roof_presets, {
        file_name = clean,
        display_name = name
      })
      db_files[#db_files + 1] = clean
      loaded_count = loaded_count + 1
      end
    end
  end
  file:close()

  if db_changed then
    WriteProfileDatabase(db_path, db_files)
  end

  if loaded_count == 0 then
    local files = ListProfileFiles(profile_dir)
    if #files > 0 and WriteProfileDatabase(db_path, files) then
      RoofControlManager.LoadPresets(state)
    end
  end
end

function RoofControlManager.ImportAutoEqProfileFromPath(state, source_path)
  if not source_path or source_path == "" then
    return false
  end

  local normalized, parse_error = ParseAutoEqProfile(source_path)
  if not normalized then
    state.analyzer_error = parse_error
    return false
  end

  local dst_root = reaper.GetResourcePath()
  local profile_dir = PathJoin(dst_root, "Data", "roof_control", "phones_eq")
  local db_path = PathJoin(dst_root, "Data", "roof_control", "hp.db")
  reaper.RecursiveCreateDirectory(profile_dir, 0)

  local source_stem = Stem(source_path)
  if source_stem:lower() == "parametriceq" or source_stem:lower() == "parametric eq" then
    source_stem = ParentName(source_path) or source_stem
  end

  local file_name = MakeUniqueFileName(profile_dir, source_stem)
  if not WriteFile(PathJoin(profile_dir, file_name), normalized) then
    state.analyzer_error = "Cannot write imported AutoEq profile"
    return false
  end

  if not AppendLine(db_path, file_name) then
    state.analyzer_error = "Cannot update headphone profile database"
    return false
  end

  RoofControlManager.LoadPresets(state)
  for idx, preset in ipairs(state.roof_presets or {}) do
    if preset.file_name == file_name then
      state.roof_preset_idx = idx - 1
      local fx_index = state.roof_fx_idx
      if fx_index then
        RoofControlManager.SetPresetIndex(state, idx - 1, fx_index)
      end
      break
    end
  end

  if reaper.gmem_attach and reaper.gmem_write then
    reaper.gmem_attach("roof_mem")
    reaper.gmem_write(2, 2)
  end

  state.analyzer_error = nil
  return true
end

function RoofControlManager.ImportAutoEqProfile(state)
  if not reaper.GetUserFileNameForRead then
    state.analyzer_error = "File picker is unavailable"
    return false
  end

  local ok, source_path = reaper.GetUserFileNameForRead("", "Import AutoEq ParametricEQ.txt", ".txt")
  if not ok then
    return false
  end

  return RoofControlManager.ImportAutoEqProfileFromPath(state, source_path)
end

function RoofControlManager.UpdateStateFromFx(state, fx_index)
  if not fx_index then return end
  local master = reaper.GetMasterTrack(0)
  if not master then return end
  local now = reaper.time_precise and reaper.time_precise() or 0
  if now - (state.roof_state_last_read or 0) < 0.05 then
    return
  end
  state.roof_state_last_read = now

  -- Load sliders (parameters)
  local bypass = reaper.TrackFX_GetParam(master, fx_index, PARAM_BYPASS)
  state.roof_bypass = (bypass == 1.0)
  
  local headroom = reaper.TrackFX_GetParam(master, fx_index, PARAM_HEADROOM)
  state.roof_headroom = headroom or -7.0

  local mode = reaper.TrackFX_GetParam(master, fx_index, PARAM_MODE)
  state.roof_mode = math.floor(mode or 0)

  local emulation_bypass = reaper.TrackFX_GetParam(master, fx_index, PARAM_EMULATION_BYPASS)
  state.roof_emulation_bypass = (emulation_bypass == 1.0)

  local cf_active = reaper.TrackFX_GetParam(master, fx_index, PARAM_CROSSFEED)
  state.roof_crossfeed = (cf_active == 0.0) -- 0: on, 1: off

  local cf_cutoff = reaper.TrackFX_GetParam(master, fx_index, PARAM_CF_CUTOFF)
  state.roof_cf_cutoff = cf_cutoff or 800

  local cf_sup = reaper.TrackFX_GetParam(master, fx_index, PARAM_CF_SUPPRESSION)
  state.roof_cf_sup = cf_sup or 6.1

  local hp_idx = reaper.TrackFX_GetParam(master, fx_index, PARAM_PRESET_INDEX)
  state.roof_preset_idx = math.floor(hp_idx or 0)

  local cf_delay = reaper.TrackFX_GetParam(master, fx_index, PARAM_CF_DELAY)
  state.roof_cf_delay = cf_delay or 0.23

  local phones_corr = reaper.TrackFX_GetParam(master, fx_index, PARAM_PHONES_CORRECTION)
  state.roof_correction = (phones_corr == 0.0) -- 0: on, 1: off

  local preamp = reaper.TrackFX_GetParam(master, fx_index, PARAM_PREAMP)
  state.roof_preamp = preamp or 0.0
end

function RoofControlManager.SetTargetCurve(state, curve_idx, fx_index)
  state.roof_mode = curve_idx
  state.roof_emulation_bypass = false
  reaper.gmem_attach("roof_mem")
  reaper.gmem_write(3, curve_idx) -- Write to shared memory for toolbar sync
  reaper.gmem_write(4, 1)         -- Mark as manual switch
  
  if fx_index then
    local master = reaper.GetMasterTrack(0)
    SetParam(master, fx_index, PARAM_EMULATION_BYPASS, 0.0)
    SetParam(master, fx_index, PARAM_MODE, curve_idx / 6)
  end
end

function RoofControlManager.SetBypass(state, active, fx_index)
  state.roof_bypass = active
  reaper.gmem_attach("roof_mem")
  reaper.gmem_write(6, active and 1.0 or 0.0)
  
  if fx_index then
    local master = reaper.GetMasterTrack(0)
    SetParam(master, fx_index, PARAM_BYPASS, active and 1.0 or 0.0)
  end
end

function RoofControlManager.SetEmulationBypass(state, active, fx_index)
  state.roof_emulation_bypass = active
  if fx_index then
    local master = reaper.GetMasterTrack(0)
    SetParam(master, fx_index, PARAM_EMULATION_BYPASS, active and 1.0 or 0.0)
  end
end

function RoofControlManager.SetPhonesCorrection(state, active, fx_index)
  state.roof_correction = active
  if fx_index then
    local master = reaper.GetMasterTrack(0)
    SetParam(master, fx_index, PARAM_PHONES_CORRECTION, active and 0.0 or 1.0) -- 0: on, 1: off
  end
end

function RoofControlManager.SetCrossfeed(state, active, fx_index)
  state.roof_crossfeed = active
  if not active then
    state.roof_emulation_bypass = true
  end
  if fx_index then
    local master = reaper.GetMasterTrack(0)
    SetParam(master, fx_index, PARAM_CROSSFEED, active and 0.0 or 1.0) -- 0: on, 1: off
    if not active then
      SetParam(master, fx_index, PARAM_EMULATION_BYPASS, 1.0)
    end
  end
end

function RoofControlManager.SetPresetIndex(state, idx, fx_index)
  state.roof_preset_idx = idx
  if fx_index then
    local master = reaper.GetMasterTrack(0)
    reaper.TrackFX_SetParam(master, fx_index, PARAM_PRESET_INDEX, idx)
  end
end

function RoofControlManager.SetPreamp(state, val, fx_index)
  state.roof_preamp = val
  if fx_index then
    local master = reaper.GetMasterTrack(0)
    reaper.TrackFX_SetParam(master, fx_index, PARAM_PREAMP, val)
  end
end

function RoofControlManager.SetHeadroom(state, val, fx_index)
  state.roof_headroom = val
  if fx_index then
    local master = reaper.GetMasterTrack(0)
    reaper.TrackFX_SetParam(master, fx_index, PARAM_HEADROOM, val)
  end
end

return RoofControlManager
