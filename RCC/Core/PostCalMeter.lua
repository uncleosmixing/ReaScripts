local PostCalMeter = {}

local GMEM_NAME = "RCC_POST_CAL_METER"
local FX_DIR = "RCC"
local FX_FILE = "RCC_PostCalMeter_v2.jsfx"
local REC_FX_OFFSET = 0x1000000
local FX_NAMES = {
  "JS: RCC/RCC_PostCalMeter_v2",
  "JS: RCC Post Correction Meter v2",
  "RCC_PostCalMeter_v2",
  "RCC Post Correction Meter v2",
  "JS: RCC/RCC_PostCalMeter_v1",
  "JS: RCC Post Correction Meter v1",
  "RCC_PostCalMeter_v1",
  "RCC Post Correction Meter v1",
}

local JSFX = [[desc:RCC Post Correction Meter v2
options:gmem=RCC_POST_CAL_METER

@init
magic = 822032;
version = 2;
counter = 0;
peak_l = 0;
peak_r = 0;
rms_l = 0;
rms_r = 0;
hold_l = 0;
hold_r = 0;
reset_seen = gmem[20];

@sample
abs_l = abs(spl0);
abs_r = abs(spl1);
peak_l = max(abs_l, peak_l * 0.9985);
peak_r = max(abs_r, peak_r * 0.9985);
hold_l = max(hold_l, abs_l);
hold_r = max(hold_r, abs_r);
rms_l = rms_l * 0.995 + spl0 * spl0 * 0.005;
rms_r = rms_r * 0.995 + spl1 * spl1 * 0.005;

@block
gmem[20] != reset_seen ? (
  reset_seen = gmem[20];
  hold_l = peak_l;
  hold_r = peak_r;
);
counter += 1;
gmem[0] = magic;
gmem[1] = version;
gmem[2] = counter;
gmem[3] = peak_l;
gmem[4] = peak_r;
gmem[5] = sqrt(rms_l);
gmem[6] = sqrt(rms_r);
gmem[7] = hold_l;
gmem[8] = hold_r;
]]

local last_ensure = 0

local function PathJoin(a, b)
  if not a or a == "" then return b end
  local sep = package.config:sub(1, 1)
  if a:sub(-1) == "\\" or a:sub(-1) == "/" then return a .. b end
  return a .. sep .. b
end

local function ReadFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local function WriteFile(path, content)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(content)
  f:close()
  return true
end

local function IsPostMeterName(name)
  return name and (
    name:find("RCC Post Correction Meter", 1, true) ~= nil or
    name:find("RCC_PostCalMeter", 1, true) ~= nil
  )
end

local function IsCurrentPostMeterName(name)
  return name and (
    name:find("RCC Post Correction Meter v2", 1, true) ~= nil or
    name:find("RCC_PostCalMeter_v2", 1, true) ~= nil
  )
end

local function EnsureAttached()
  reaper.gmem_attach(GMEM_NAME)
end

local function EnsureFile()
  local effects_dir = PathJoin(reaper.GetResourcePath(), "Effects")
  local rcc_dir = PathJoin(effects_dir, FX_DIR)
  local fx_path = PathJoin(rcc_dir, FX_FILE)
  reaper.RecursiveCreateDirectory(rcc_dir, 0)
  if ReadFile(fx_path) ~= JSFX and not WriteFile(fx_path, JSFX) then
    return false, "Cannot write RCC Post Correction Meter JSFX"
  end
  return true, nil
end

local function FindFx(master)
  local count = reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(master) or 0
  for index = 0, count - 1 do
    local fx_index = REC_FX_OFFSET + index
    local _, name = reaper.TrackFX_GetFXName(master, fx_index)
    if IsPostMeterName(name) then
      return fx_index, name
    end
  end
  return -1
end

local function RemoveExistingPostMeters(master)
  local count = reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(master) or 0
  for index = count - 1, 0, -1 do
    local fx_index = REC_FX_OFFSET + index
    local _, name = reaper.TrackFX_GetFXName(master, fx_index)
    if IsPostMeterName(name) then
      reaper.TrackFX_Delete(master, fx_index)
    end
  end
end

function PostCalMeter.EnsureInstalled()
  local now = reaper.time_precise and reaper.time_precise() or 0
  if now - last_ensure < 0.75 then return true, nil end
  last_ensure = now

  local ok, err = EnsureFile()
  if not ok then return false, err end
  local master = reaper.GetMasterTrack(0)
  if not master then return false, "Master track unavailable" end
  local existing_fx, existing_name = FindFx(master)
  if existing_fx >= 0 and IsCurrentPostMeterName(existing_name) then return true, nil end
  if not reaper.TrackFX_AddByName then return false, "TrackFX_AddByName is unavailable" end
  if existing_fx >= 0 and reaper.TrackFX_Delete then
    RemoveExistingPostMeters(master)
  end

  local fx_index = -1
  for _, fx_name in ipairs(FX_NAMES) do
    fx_index = reaper.TrackFX_AddByName(master, fx_name, true, 1)
    if fx_index >= 0 then break end
  end
  if fx_index < 0 then
    return false, "RCC Post Correction Meter was installed, but REAPER did not load it"
  end
  return true, nil
end

function PostCalMeter.Read()
  EnsureAttached()
  local magic = reaper.gmem_read(0)
  local active = magic == 822032 and (reaper.gmem_read(2) or 0) > 0
  return {
    active = active,
    peak_l = active and (reaper.gmem_read(3) or 0) or 0,
    peak_r = active and (reaper.gmem_read(4) or 0) or 0,
    rms_l = active and (reaper.gmem_read(5) or 0) or 0,
    rms_r = active and (reaper.gmem_read(6) or 0) or 0,
    hold_l = active and (reaper.gmem_read(7) or 0) or 0,
    hold_r = active and (reaper.gmem_read(8) or 0) or 0,
  }
end

function PostCalMeter.ResetHold()
  EnsureAttached()
  local current = reaper.gmem_read(20) or 0
  reaper.gmem_write(20, current + 1)
end

return PostCalMeter
