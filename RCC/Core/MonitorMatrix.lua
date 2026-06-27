local MonitorMatrix = {}

local FX_DIR = "RCC"
local FX_FILE = "RCC_MonitorMatrix.jsfx"
local FX_NAMES = {
  "JS: RCC/RCC_MonitorMatrix",
  "JS: RCC Monitor Matrix",
  "RCC_MonitorMatrix",
  "RCC Monitor Matrix",
}
local REC_FX_OFFSET = 0x1000000
local jsfx_checked = false

local MODE_TO_INDEX = {
  normal = 0,
  left = 1,
  right = 2,
  mid = 3,
  side = 4,
}

local BAND_TO_INDEX = {
  full = 0,
  sub = 1,
  low = 2,
  mids = 3,
  high = 4,
}

local JSFX = [[desc:RCC Monitor Matrix
slider1:0<0,4,1{NORMAL,L,R,MID,SIDE}>Listen
slider2:0<0,4,1{FULL,SUB,LOW,MIDS,HIGH}>Band

@init
function make_lp(freq) local(w0 cosw sinw alpha a0) (
  w0 = 2 * $pi * freq / srate;
  cosw = cos(w0);
  sinw = sin(w0);
  alpha = sinw / 1.41421356237;
  lp_b0 = (1 - cosw) * 0.5;
  lp_b1 = 1 - cosw;
  lp_b2 = (1 - cosw) * 0.5;
  a0 = 1 + alpha;
  lp_a1 = -2 * cosw;
  lp_a2 = 1 - alpha;
  lp_b0 /= a0; lp_b1 /= a0; lp_b2 /= a0; lp_a1 /= a0; lp_a2 /= a0;
);

function make_hp(freq) local(w0 cosw sinw alpha a0) (
  w0 = 2 * $pi * freq / srate;
  cosw = cos(w0);
  sinw = sin(w0);
  alpha = sinw / 1.41421356237;
  hp_b0 = (1 + cosw) * 0.5;
  hp_b1 = -(1 + cosw);
  hp_b2 = (1 + cosw) * 0.5;
  a0 = 1 + alpha;
  hp_a1 = -2 * cosw;
  hp_a2 = 1 - alpha;
  hp_b0 /= a0; hp_b1 /= a0; hp_b2 /= a0; hp_a1 /= a0; hp_a2 /= a0;
);

function lp80_l(x) local(y) (y = lp80_b0*x + lp80_b1*lp80_l_x1 + lp80_b2*lp80_l_x2 - lp80_a1*lp80_l_y1 - lp80_a2*lp80_l_y2; lp80_l_x2=lp80_l_x1; lp80_l_x1=x; lp80_l_y2=lp80_l_y1; lp80_l_y1=y; y;);
function lp80_r(x) local(y) (y = lp80_b0*x + lp80_b1*lp80_r_x1 + lp80_b2*lp80_r_x2 - lp80_a1*lp80_r_y1 - lp80_a2*lp80_r_y2; lp80_r_x2=lp80_r_x1; lp80_r_x1=x; lp80_r_y2=lp80_r_y1; lp80_r_y1=y; y;);
function hp80_l(x) local(y) (y = hp80_b0*x + hp80_b1*hp80_l_x1 + hp80_b2*hp80_l_x2 - hp80_a1*hp80_l_y1 - hp80_a2*hp80_l_y2; hp80_l_x2=hp80_l_x1; hp80_l_x1=x; hp80_l_y2=hp80_l_y1; hp80_l_y1=y; y;);
function hp80_r(x) local(y) (y = hp80_b0*x + hp80_b1*hp80_r_x1 + hp80_b2*hp80_r_x2 - hp80_a1*hp80_r_y1 - hp80_a2*hp80_r_y2; hp80_r_x2=hp80_r_x1; hp80_r_x1=x; hp80_r_y2=hp80_r_y1; hp80_r_y1=y; y;);

function lp250_l(x) local(y) (y = lp250_b0*x + lp250_b1*lp250_l_x1 + lp250_b2*lp250_l_x2 - lp250_a1*lp250_l_y1 - lp250_a2*lp250_l_y2; lp250_l_x2=lp250_l_x1; lp250_l_x1=x; lp250_l_y2=lp250_l_y1; lp250_l_y1=y; y;);
function lp250_r(x) local(y) (y = lp250_b0*x + lp250_b1*lp250_r_x1 + lp250_b2*lp250_r_x2 - lp250_a1*lp250_r_y1 - lp250_a2*lp250_r_y2; lp250_r_x2=lp250_r_x1; lp250_r_x1=x; lp250_r_y2=lp250_r_y1; lp250_r_y1=y; y;);
function hp250_l(x) local(y) (y = hp250_b0*x + hp250_b1*hp250_l_x1 + hp250_b2*hp250_l_x2 - hp250_a1*hp250_l_y1 - hp250_a2*hp250_l_y2; hp250_l_x2=hp250_l_x1; hp250_l_x1=x; hp250_l_y2=hp250_l_y1; hp250_l_y1=y; y;);
function hp250_r(x) local(y) (y = hp250_b0*x + hp250_b1*hp250_r_x1 + hp250_b2*hp250_r_x2 - hp250_a1*hp250_r_y1 - hp250_a2*hp250_r_y2; hp250_r_x2=hp250_r_x1; hp250_r_x1=x; hp250_r_y2=hp250_r_y1; hp250_r_y1=y; y;);

function lp4k_l(x) local(y) (y = lp4k_b0*x + lp4k_b1*lp4k_l_x1 + lp4k_b2*lp4k_l_x2 - lp4k_a1*lp4k_l_y1 - lp4k_a2*lp4k_l_y2; lp4k_l_x2=lp4k_l_x1; lp4k_l_x1=x; lp4k_l_y2=lp4k_l_y1; lp4k_l_y1=y; y;);
function lp4k_r(x) local(y) (y = lp4k_b0*x + lp4k_b1*lp4k_r_x1 + lp4k_b2*lp4k_r_x2 - lp4k_a1*lp4k_r_y1 - lp4k_a2*lp4k_r_y2; lp4k_r_x2=lp4k_r_x1; lp4k_r_x1=x; lp4k_r_y2=lp4k_r_y1; lp4k_r_y1=y; y;);
function hp4k_l(x) local(y) (y = hp4k_b0*x + hp4k_b1*hp4k_l_x1 + hp4k_b2*hp4k_l_x2 - hp4k_a1*hp4k_l_y1 - hp4k_a2*hp4k_l_y2; hp4k_l_x2=hp4k_l_x1; hp4k_l_x1=x; hp4k_l_y2=hp4k_l_y1; hp4k_l_y1=y; y;);
function hp4k_r(x) local(y) (y = hp4k_b0*x + hp4k_b1*hp4k_r_x1 + hp4k_b2*hp4k_r_x2 - hp4k_a1*hp4k_r_y1 - hp4k_a2*hp4k_r_y2; hp4k_r_x2=hp4k_r_x1; hp4k_r_x1=x; hp4k_r_y2=hp4k_r_y1; hp4k_r_y1=y; y;);

make_lp(80); lp80_b0=lp_b0; lp80_b1=lp_b1; lp80_b2=lp_b2; lp80_a1=lp_a1; lp80_a2=lp_a2;
make_hp(80); hp80_b0=hp_b0; hp80_b1=hp_b1; hp80_b2=hp_b2; hp80_a1=hp_a1; hp80_a2=hp_a2;
make_lp(250); lp250_b0=lp_b0; lp250_b1=lp_b1; lp250_b2=lp_b2; lp250_a1=lp_a1; lp250_a2=lp_a2;
make_hp(250); hp250_b0=hp_b0; hp250_b1=hp_b1; hp250_b2=hp_b2; hp250_a1=hp_a1; hp250_a2=hp_a2;
make_lp(4000); lp4k_b0=lp_b0; lp4k_b1=lp_b1; lp4k_b2=lp_b2; lp4k_a1=lp_a1; lp4k_a2=lp_a2;
make_hp(4000); hp4k_b0=hp_b0; hp4k_b1=hp_b1; hp4k_b2=hp_b2; hp4k_a1=hp_a1; hp4k_a2=hp_a2;

@sample
l = spl0;
r = spl1;
mode = floor(slider1 + 0.5);
band = floor(slider2 + 0.5);

mode == 1 ? (
  spl0 = l;
  spl1 = 0;
) : mode == 2 ? (
  spl0 = 0;
  spl1 = r;
) : mode == 3 ? (
  mid = (l + r) * 0.5;
  spl0 = mid;
  spl1 = mid;
) : mode == 4 ? (
  side = (l - r) * 0.5;
  spl0 = side;
  spl1 = -side;
);

band == 1 ? (
  spl0 = lp80_l(spl0);
  spl1 = lp80_r(spl1);
) : band == 2 ? (
  spl0 = lp250_l(hp80_l(spl0));
  spl1 = lp250_r(hp80_r(spl1));
) : band == 3 ? (
  spl0 = lp4k_l(hp250_l(spl0));
  spl1 = lp4k_r(hp250_r(spl1));
) : band == 4 ? (
  spl0 = hp4k_l(spl0);
  spl1 = hp4k_r(spl1);
);
]]

local function PathJoin(left, right)
  if left:sub(-1) == "\\" or left:sub(-1) == "/" then
    return left .. right
  end

  return left .. "/" .. right
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

local function IsMatrixName(name)
  return name and (
    name:find("RCC Monitor Matrix", 1, true) ~= nil or
    name:find("RCC_MonitorMatrix", 1, true) ~= nil
  )
end

local function FindMatrixFx()
  local master = reaper.GetMasterTrack(0)
  local count = reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(master) or 0

  for index = 0, count - 1 do
    local fx_index = REC_FX_OFFSET + index
    local _, name = reaper.TrackFX_GetFXName(master, fx_index)
    if IsMatrixName(name) then
      return fx_index
    end
  end

  return -1
end

local function DeleteExistingMatrix()
  local master = reaper.GetMasterTrack(0)
  local count = reaper.TrackFX_GetRecCount and reaper.TrackFX_GetRecCount(master) or 0

  for index = count - 1, 0, -1 do
    local fx_index = REC_FX_OFFSET + index
    local _, name = reaper.TrackFX_GetFXName(master, fx_index)
    if IsMatrixName(name) then
      reaper.TrackFX_Delete(master, fx_index)
    end
  end
end

local function EnsureJsfxFile()
  if jsfx_checked then
    return true, nil, false
  end

  local effects_dir = PathJoin(reaper.GetResourcePath(), "Effects")
  local rcc_dir = PathJoin(effects_dir, FX_DIR)
  local fx_path = PathJoin(rcc_dir, FX_FILE)

  reaper.RecursiveCreateDirectory(rcc_dir, 0)

  local changed = ReadFile(fx_path) ~= JSFX
  if changed and not WriteFile(fx_path, JSFX) then
    return false, "Cannot write RCC Monitor Matrix JSFX"
  end

  jsfx_checked = true
  return true, nil, changed
end

function MonitorMatrix.EnsureInstalled()
  local ok, error_message, changed = EnsureJsfxFile()
  if not ok then
    return -1, error_message
  end

  local existing = FindMatrixFx()
  if existing >= 0 then
    if changed then
      DeleteExistingMatrix()
    else
      return existing, nil
    end
  end

  if not reaper.TrackFX_AddByName then
    return -1, "TrackFX_AddByName is unavailable"
  end

  local master = reaper.GetMasterTrack(0)
  local fx_index = -1

  for _, fx_name in ipairs(FX_NAMES) do
    fx_index = reaper.TrackFX_AddByName(master, fx_name, true, 1)
    if fx_index >= 0 then
      break
    end
  end

  if fx_index < 0 then
    return -1, "RCC Monitor Matrix was installed, but REAPER did not load it"
  end

  return REC_FX_OFFSET + fx_index, nil
end

function MonitorMatrix.ResetInstall()
  DeleteExistingMatrix()
  jsfx_checked = false
  return MonitorMatrix.EnsureInstalled()
end

function MonitorMatrix.SetMode(mode)
  local fx_index, error_message = MonitorMatrix.EnsureInstalled()
  if fx_index < 0 then
    return false, error_message
  end

  local value = MODE_TO_INDEX[mode] or 0
  if reaper.TrackFX_SetParamNormalized then
    reaper.TrackFX_SetParamNormalized(reaper.GetMasterTrack(0), fx_index, 0, value / 4)
  else
    reaper.TrackFX_SetParam(reaper.GetMasterTrack(0), fx_index, 0, value)
  end
  return true, nil
end

function MonitorMatrix.SetBand(band)
  local fx_index, error_message = MonitorMatrix.EnsureInstalled()
  if fx_index < 0 then
    return false, error_message
  end

  local value = BAND_TO_INDEX[band] or 0
  if reaper.TrackFX_SetParamNormalized then
    reaper.TrackFX_SetParamNormalized(reaper.GetMasterTrack(0), fx_index, 1, value / 4)
  else
    reaper.TrackFX_SetParam(reaper.GetMasterTrack(0), fx_index, 1, value)
  end
  return true, nil
end

return MonitorMatrix
