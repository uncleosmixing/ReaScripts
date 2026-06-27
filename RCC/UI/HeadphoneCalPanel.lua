local HeadphoneCalPanel = {}

local UIUtils                    = require("UIUtils")
local RoofControlManager         = require("RoofControlManager")
local HeadphoneCalibrationManager = require("HeadphoneCalibrationManager")
local MonitorFxChain             = require("MonitorFxChain")
local PostCalMeter               = require("PostCalMeter")

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local AUTOEQ_URL    = "https://autoeq.app"

local BODY_V_PAD    = 8      -- vertical padding inside the animated body
local ANIM_DURATION = 0.26   -- body open/close animation duration (s)
local ROOF_BODY_H   = 80     -- pre-measured full height of the Roof body
local EXT_BODY_H    = 62     -- pre-measured full height of a compact external body
local MISSING_BODY_H = 44     -- compact missing-plugin prompt
local REAL_BODY_H   = 182    -- pre-measured full height of the Realphones body
local SONAR_BODY_H  = 106    -- pre-measured full height of the Sonarworks body

---------------------------------------------------------------------------
-- Module-level animation state  (persists across frames)
---------------------------------------------------------------------------
local hp_anim = {
  expanded         = false,
  t                = 0.0,   -- 0 = fully closed, 1 = fully open
  last_time        = nil,
  showing_provider = nil,   -- provider id whose body is currently shown
}

local realphones_debug_auto_dump = false
local realphones_last_auto_dump = 0

---------------------------------------------------------------------------
-- Easing & tick
---------------------------------------------------------------------------
local function Ease(t)
  t = math.max(0, math.min(1, t))
  return t < 0.5 and (4 * t * t * t) or (1 - (-2 * t + 2) ^ 3 / 2)
end

local function TickAnim()
  local now = reaper.time_precise and reaper.time_precise() or 0
  if hp_anim.last_time then
    local dt  = now - hp_anim.last_time
    local dir = hp_anim.expanded and 1 or -1
    hp_anim.t = math.max(0, math.min(1, hp_anim.t + dir * dt / ANIM_DURATION))
  end
  hp_anim.last_time = now
  return Ease(hp_anim.t)
end

---------------------------------------------------------------------------
-- Colour helpers
---------------------------------------------------------------------------
local function WithAlpha(color, alpha)
  return (color & 0xFFFFFF00) | (math.floor((color & 0xFF) * alpha) & 0xFF)
end

---------------------------------------------------------------------------
-- Shell helpers
---------------------------------------------------------------------------
local function OpenUrl(url)
  if reaper.CF_ShellExecute then reaper.CF_ShellExecute(url); return end
  local osn = reaper.GetOS and reaper.GetOS() or ""
  if     osn:find("Win") then os.execute('start "" "' .. url .. '"')
  elseif osn:find("OSX") then os.execute('open "' .. url .. '"')
  else                         os.execute('xdg-open "' .. url .. '"') end
end

local function OpenAutoEq() OpenUrl(AUTOEQ_URL) end

local function OpenProfilesFolder()
  local sep    = package.config:sub(1, 1)
  local folder = table.concat({reaper.GetResourcePath(), "Data", "roof_control", "phones_eq"}, sep)
  if reaper.RecursiveCreateDirectory then reaper.RecursiveCreateDirectory(folder, 0) end
  OpenUrl(folder)
end

---------------------------------------------------------------------------
-- Text utilities
---------------------------------------------------------------------------
local function Ellipsize(ctx, text, max_w)
  text = tostring(text or "")
  if UIUtils.TextWidth(ctx, text) <= max_w then return text end
  local ew  = UIUtils.TextWidth(ctx, "...")
  local out = ""
  for i = 1, #text do
    if UIUtils.TextWidth(ctx, text:sub(1, i)) + ew > max_w then break end
    out = text:sub(1, i)
  end
  return out .. "..."
end

local function BuildProviderHeaderLayout(ctx, x, right, sf, sfs)
  local title = "HP CORRECTION"
  local title_right = x + UIUtils.HEADER_LABEL_X + UIUtils.TextWidth(ctx, title) + 12
  local max_right = right - 9
  local available = math.max(0, max_right - title_right)
  local variants = {
    {
      gap = 14,
      items = {
        { id = "roof",       label = "ROOF" },
        { id = "sonarworks", label = "SONARWORKS" },
        { id = "realphones", label = "REALPHONES" },
      },
    },
    {
      gap = 10,
      items = {
        { id = "roof",       label = "ROOF" },
        { id = "sonarworks", label = "SONAR" },
        { id = "realphones", label = "REAL" },
      },
    },
    {
      gap = 8,
      items = {
        { id = "roof",       label = "RF" },
        { id = "sonarworks", label = "SW" },
        { id = "realphones", label = "RP" },
      },
    },
  }

  local function measure(items, gap)
    local total = 0
    for idx, item in ipairs(items) do
      item.w = UIUtils.TextWidth(ctx, item.label)
      total = total + item.w
      if idx > 1 then total = total + gap end
    end
    return total
  end

  for _, variant in ipairs(variants) do
    local total = measure(variant.items, variant.gap)
    if total <= available then
      local start_x = max_right - total
      local cursor_x = start_x
      for idx, item in ipairs(variant.items) do
        item.x = cursor_x
        cursor_x = cursor_x + item.w + variant.gap
      end
      return variant.items
    end
  end

  return {}
end

---------------------------------------------------------------------------
-- Drag-and-drop helpers
---------------------------------------------------------------------------
local function GetDroppedFile(ctx, idx)
  if not reaper.ImGui_GetDragDropPayloadFile then return nil end
  local ok, rv, fn = pcall(reaper.ImGui_GetDragDropPayloadFile, ctx, idx)
  if not ok then return nil end
  if type(rv) == "string" then return rv end
  if rv and type(fn) == "string" and fn ~= "" then return fn end
  return nil
end

local function AcceptDroppedProfile(ctx, state)
  if not (reaper.ImGui_BeginDragDropTarget
      and reaper.ImGui_AcceptDragDropPayloadFiles
      and reaper.ImGui_EndDragDropTarget) then return false end
  local accepted = false
  if reaper.ImGui_BeginDragDropTarget(ctx) then
    local ok, rv = pcall(reaper.ImGui_AcceptDragDropPayloadFiles, ctx, 8)
    if ok and rv then
      for i = 0, 7 do
        local path = GetDroppedFile(ctx, i)
        if path and path:lower():match("%.txt$") then
          accepted = RoofControlManager.ImportAutoEqProfileFromPath(state, path) or accepted
          break
        end
      end
      if not accepted then
        state.analyzer_error = "Drop an AutoEq .txt parametric EQ profile"
      end
    end
    reaper.ImGui_EndDragDropTarget(ctx)
  end
  return accepted
end



---------------------------------------------------------------------------
-- Reusable tiny text button
---------------------------------------------------------------------------
local function DrawTinyTextButton(ctx, dl, draw_api, id, label, x, y, w, h,
    active, sf, sfs, enabled)
  enabled = enabled ~= false
  w = math.max(1.0, w or 1.0)
  h = math.max(1.0, h or 1.0)
  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = reaper.ImGui_InvisibleButton(ctx, id, w, h)
  local hov     = reaper.ImGui_IsItemHovered(ctx)

  local bg  = active and 0x163B2AFF or (hov and enabled and 0x1B1F25FF or 0x12151AFF)
  local brd = active and 0x5CFFB666 or (hov and enabled and 0x5CFFB633 or 0xFFFFFF14)
  local tc  = active and 0x5CFFB6FF or (enabled and 0xD6DAE1E8 or 0x6C737CE0)

  draw_api.rect_filled(dl, x, y, x + w, y + h, bg,  4.0)
  draw_api.rect(dl,        x, y, x + w, y + h, brd, 4.0, nil, 1.0)

  UIUtils.DrawButtonTextInRect(ctx, dl, x, y, w, h, label, tc, sf, sfs)

  return clicked and enabled
end

local function DrawPowerIconButton(ctx, dl, draw_api, id, x, y, w, h, active, enabled)
  enabled = enabled ~= false
  w = math.max(1.0, w or 1.0)
  h = math.max(1.0, h or 1.0)
  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = reaper.ImGui_InvisibleButton(ctx, id, w, h)
  local hov = reaper.ImGui_IsItemHovered(ctx)

  local bg = hov and enabled and 0x201A1033 or 0x00000000
  local col = active and 0xFFC45CFF or (enabled and 0xB98A48DD or 0x6C737CE0)

  if hov and enabled then
    draw_api.rect_filled(dl, x, y, x + w, y + h, bg, 4.0)
  end

  local cx = math.floor(x + w * 0.5 + 0.5)
  local cy = math.floor(y + h * 0.58 + 0.5)
  local r = math.max(3.0, math.floor(math.min(w, h) * 0.24 + 0.5))
  local top_y = math.floor(cy - r - 1)
  local stem_bottom = math.floor(cy - r * 0.18)
  local thickness = 1.6

  if draw_api.path_clear and draw_api.path_arc_to and draw_api.path_stroke then
    draw_api.path_clear(dl)
    draw_api.path_arc_to(dl, cx, cy, r, math.rad(138), math.rad(402), 24)
    draw_api.path_stroke(dl, col, 0, thickness)
  else
    draw_api.circle(dl, cx, cy, r, col, 24, thickness)
    draw_api.line(dl, cx - r * 0.48, cy - r * 0.62, cx - r * 0.16, cy - r * 0.98, 0x0C0F12FF, 2.4)
    draw_api.line(dl, cx + r * 0.48, cy - r * 0.62, cx + r * 0.16, cy - r * 0.98, 0x0C0F12FF, 2.4)
  end
  draw_api.line(dl, cx, top_y, cx, stem_bottom, col, thickness)

  return clicked and enabled
end

---------------------------------------------------------------------------
-- AutoEq profile selector drop-down
---------------------------------------------------------------------------
local function DrawProfileSelector(ctx, state, rfx, dl, draw_api, x, y, w, h, sf, sfs)
  local has_presets = #(state.roof_presets or {}) > 0
  local name        = has_presets and "Select Profile" or "Drop / import AutoEq profile"
  if has_presets and state.roof_preset_idx then
    local ai = state.roof_preset_idx + 1
    if state.roof_presets[ai] then name = state.roof_presets[ai].display_name end
  end

  w = math.max(1.0, w or 1.0)
  h = math.max(1.0, h or 1.0)
  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  reaper.ImGui_InvisibleButton(ctx, "##roof_profile_select", w, h)
  local hov = reaper.ImGui_IsItemHovered(ctx)
  if reaper.ImGui_IsItemClicked(ctx, 0) then reaper.ImGui_OpenPopup(ctx, "##roof_profile_popup") end
  AcceptDroppedProfile(ctx, state)

  draw_api.rect_filled(dl, x, y, x + w, y + h, hov and 0x171B22FF or 0x12151AFF, 4.0)
  draw_api.rect(dl,        x, y, x + w, y + h, hov and 0x2B5F48CC or 0x272B33CC, 4.0, nil, 1.0)
  if hov then draw_api.rect_filled(dl, x + 1, y + h - 2, x + w - 1, y + h - 1, 0x5CFFB655, 2.0) end

  UIUtils.DrawButtonTextInRect(ctx, dl, x, y, w, h, name, has_presets and 0xE8EAF0EE or 0x8C94A0EE, sf, sfs, 7, 2)

  -- Drop-down popup
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(),      0x111216FA)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),       0x2B5F4877)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(),       0x183A2BFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(),0x245C42FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x10291EFF)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(), 5.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 6, 6)
  local cond_app = reaper.ImGui_Cond_Appearing and reaper.ImGui_Cond_Appearing() or 0
  reaper.ImGui_SetNextWindowSize(ctx, math.max(180, w), 0, cond_app)
  if reaper.ImGui_BeginPopup(ctx, "##roof_profile_popup") then
    if has_presets then
      if reaper.ImGui_Selectable(ctx, "Import AutoEq profile...##imp") then
        RoofControlManager.ImportAutoEqProfile(state)
      end
      reaper.ImGui_Separator(ctx)
      for idx, preset in ipairs(state.roof_presets or {}) do
        local sel = (state.roof_preset_idx == idx - 1)
        if reaper.ImGui_Selectable(ctx,
            (preset.display_name or "Preset " .. idx) .. "##rp_" .. idx, sel) then
          RoofControlManager.SetPresetIndex(state, idx - 1, rfx)
        end
      end
    else
      reaper.ImGui_TextWrapped(ctx,
        "No headphone profiles. Download a parametric EQ profile from AutoEq, then drop it here.")
      reaper.ImGui_Spacing(ctx)
      if reaper.ImGui_Selectable(ctx, "Import AutoEq profile...##imp2") then
        RoofControlManager.ImportAutoEqProfile(state)
      end
      if reaper.ImGui_Selectable(ctx, "Open autoeq.app##openaq") then
        OpenAutoEq()
      end
    end
    reaper.ImGui_EndPopup(ctx)
  end
  reaper.ImGui_PopStyleVar(ctx, 2)
  reaper.ImGui_PopStyleColor(ctx, 5)
end

---------------------------------------------------------------------------
-- Target-curve buttons (MAIN / SUB / CUBES / …)
---------------------------------------------------------------------------
local ROOF_TARGETS = {
  {{ label="MAIN",  id=0 }, { label="SUB",  id=1 }, { label="CUBES", id=3 }, { label="PHONE", id=4 }},
  {{ label="VINYL", id=5 }, { label="FULL", id=6 }, { label="SLEW",  id=2 }},
}

local function DrawTargetCurveButtons(ctx, state, rfx, dl, draw_api, width, sf, sfs)
  local spacing = 5
  local btn_h   = 16
  local row_gap = 4
  local sx, sy  = reaper.ImGui_GetCursorScreenPos(ctx)

  for ri, row in ipairs(ROOF_TARGETS) do
    local btn_w = math.floor(math.min(58, math.max(48, (width - spacing * 3) / 4)))
    local row_w = btn_w * #row + spacing * (#row - 1)
    local rx    = sx + math.floor((width - row_w) * 0.5 + 0.5)
    local ry    = sy + (ri - 1) * (btn_h + row_gap)
    for ci, item in ipairs(row) do
      local en  = (state.roof_crossfeed == true)
      local act = en
               and (not state.roof_bypass)
               and (not state.roof_emulation_bypass)
               and state.roof_mode == item.id
      if DrawTinyTextButton(ctx, dl, draw_api,
          item.label .. "##tgt_" .. item.id, item.label,
          rx + (ci - 1) * (btn_w + spacing), ry,
          btn_w, btn_h, act, sf, sfs, en) then
        if act then
          RoofControlManager.SetEmulationBypass(state, true, rfx)
        else
          if state.roof_bypass          then RoofControlManager.SetBypass(state, false, rfx) end
          if state.roof_emulation_bypass then RoofControlManager.SetEmulationBypass(state, false, rfx) end
          RoofControlManager.SetTargetCurve(state, item.id, rfx)
        end
      end
    end
  end

  reaper.ImGui_SetCursorScreenPos(ctx, sx, sy + btn_h * 2 + row_gap)
end

---------------------------------------------------------------------------
-- Body: Roof Control
---------------------------------------------------------------------------
local function DrawRoofBody(ctx, state, dl, draw_api, x, y, width, sf, sfs)
  local rfx = RoofControlManager.EnsureFxInstalled(state)
  if rfx then RoofControlManager.UpdateStateFromFx(state, rfx) end
  if not state.roof_presets_loaded then RoofControlManager.LoadPresets(state) end

  local has_presets = #(state.roof_presets or {}) > 0
  if state.roof_correction and not has_presets then
    RoofControlManager.SetPhonesCorrection(state, false, rfx)
  end

  local pad       = 8
  local cw        = width - pad * 2
  local lx        = x + pad
  local sp        = 6
  local folder_w  = 24
  local gui_w     = 28
  local hp_eq_w   = 48
  local ts_w      = 54
  local profile_w = math.max(70, cw - hp_eq_w - sp - ts_w - sp - folder_w - sp - gui_w - sp)

  local row_y = y + BODY_V_PAD
  local btn_h = 20

  -- HP EQ
  local cal_act = state.roof_correction and has_presets
  if DrawTinyTextButton(ctx, dl, draw_api, "##hp_eq_btn", "HP EQ",
      lx, row_y, hp_eq_w, btn_h, cal_act, sf, sfs) then
    local next_act = not (state.roof_correction and has_presets)
    if next_act and not has_presets then
      state.analyzer_error = "Import an AutoEq headphone profile before enabling HP EQ"
      next_act = false
    end
    if next_act and state.roof_bypass then RoofControlManager.SetBypass(state, false, rfx) end
    RoofControlManager.SetPhonesCorrection(state, next_act, rfx)
  end

  -- TRUE ST
  local ts_x = lx + hp_eq_w + sp
  if DrawTinyTextButton(ctx, dl, draw_api, "##true_st_btn", "TRUE ST",
      ts_x, row_y, ts_w, btn_h, state.roof_crossfeed, sf, sfs) then
    if state.roof_bypass then RoofControlManager.SetBypass(state, false, rfx) end
    local next_cf = not state.roof_crossfeed
    if next_cf and state.roof_emulation_bypass then
      RoofControlManager.SetEmulationBypass(state, false, rfx)
    end
    RoofControlManager.SetCrossfeed(state, next_cf, rfx)
  end

  -- Profile selector
  local prof_x = ts_x + ts_w + sp
  DrawProfileSelector(ctx, state, rfx, dl, draw_api,
    prof_x, row_y, profile_w, btn_h, sf, sfs)

  -- Folder button
  local fold_x = prof_x + profile_w + sp
  if DrawTinyTextButton(ctx, dl, draw_api, "##folder_btn", "...",
      fold_x, row_y, folder_w, btn_h, false, sf, sfs) then
    OpenProfilesFolder()
  end

  -- GUI toggle
  local gui_x = fold_x + folder_w + sp
  local gui_open = false
  if rfx and reaper.TrackFX_GetOpen then
    gui_open = (reaper.TrackFX_GetOpen(reaper.GetMasterTrack(0), rfx) == true)
  end
  if DrawTinyTextButton(ctx, dl, draw_api, "##roof_gui_btn", "GUI",
      gui_x, row_y, gui_w, btn_h, gui_open, sf, sfs, rfx ~= nil) then
    reaper.TrackFX_Show(reaper.GetMasterTrack(0), rfx, gui_open and 2 or 3)
  end

  -- Target-curve buttons
  reaper.ImGui_SetCursorScreenPos(ctx, lx, row_y + btn_h + sp)
  DrawTargetCurveButtons(ctx, state, rfx, dl, draw_api, cw, sf, sfs)
end

---------------------------------------------------------------------------
-- Body: External provider (Sonarworks / Realphones)
---------------------------------------------------------------------------
local function ShortenPreset(name, max_char)
  name = tostring(name or "")
  if #name <= max_char then return name end
  return name:sub(1, max_char - 1) .. ".."
end

local REALPHONES_LIMITER_PARAM = 31
local REALPHONES_PROGRAM_PARAM = 39
local REALPHONES_CORRECTION_ENABLED_PARAM = 0
local REALPHONES_CORRECTION_AMOUNT_PARAM = 7
local REALPHONES_EASY_CORRECTION_AMOUNT_PARAM = 34
local REALPHONES_ENVIRONMENT_PARAM = 35
local REALPHONES_BRIGHTNESS_PARAM = 36
local REALPHONES_ROOM_ENABLED_PARAM = 37
local REALPHONES_LISTEN_TYPE_PARAM = 25
local REALPHONES_OUTPUT_PARAM = 29
local REALPHONES_OUTPUT_UNITY = 0.833333313
local REALPHONES_PEAK_PARAM = 32

local SONAR_CALIBRATION_PARAM = 0
local SONAR_MONO_PARAM = 1
local SONAR_MUTE_PARAM = 2
local SONAR_LR_SWAP_PARAM = 3
local SONAR_SAFE_HEADROOM_PARAM = 4
local SONAR_GAIN_PARAM = 5
local SONAR_DRY_WET_PARAM = 6

local ReadRealphonesFormattedNumber
local ReadPostCalOverload

local function SplitRealphonesProgramName(name)
  local normalized = tostring(name or "")
  normalized = normalized:gsub("%s+%-%s+", "|")
  normalized = normalized:gsub("%s+[^%w%s%-]+%s+", "|")
  normalized = normalized:gsub("%s+•%s+", "|")

  local parts = {}
  for part in normalized:gmatch("[^|]+") do
    local clean = part:gsub("^%s+", ""):gsub("%s+$", "")
    if clean ~= "" then parts[#parts + 1] = clean end
  end

  if #parts <= 1 then
    return tostring(name or "Program"), tostring(name or "Program")
  end

  local slot = parts[#parts]
  parts[#parts] = nil
  return table.concat(parts, " • "), slot
end

local function ReadRealphonesHostPresetName(master, fx_idx)
  if reaper.TrackFX_GetPreset then
    local ok, preset_name = reaper.TrackFX_GetPreset(master, fx_idx, "")
    if ok and preset_name and preset_name ~= "" then
      return tostring(preset_name)
    end
  end
  return ""
end

local function ReadRealphonesProgramName(master, fx_idx)
  if not reaper.TrackFX_GetFormattedParamValue then
    return ReadRealphonesHostPresetName(master, fx_idx)
  end
  local _, formatted = reaper.TrackFX_GetFormattedParamValue(master, fx_idx, REALPHONES_PROGRAM_PARAM)
  formatted = tostring(formatted or "")
  return formatted ~= "" and formatted or ReadRealphonesHostPresetName(master, fx_idx)
end

local function DumpExternalFxParams(master, fx_idx, provider_id, tag)
  provider_id = tostring(provider_id or "external"):lower():gsub("[^%w_%-]", "_")
  local path = (reaper.GetResourcePath and reaper.GetResourcePath() or ".") .. "/RCC_" .. provider_id .. "_params.txt"
  local f = io.open(path, "a")
  if not f then return end

  local function checksum(text)
    text = tostring(text or "")
    local sum = 0
    for i = 1, #text do
      sum = (sum + text:byte(i) * i) % 4294967296
    end
    return sum
  end

  local _, fx_name = reaper.TrackFX_GetFXName(master, fx_idx, "")
  local preset_ok, preset_name = false, ""
  if reaper.TrackFX_GetPreset then
    preset_ok, preset_name = reaper.TrackFX_GetPreset(master, fx_idx, "")
  end

  local preset_idx, preset_count = nil, nil
  if reaper.TrackFX_GetPresetIndex then
    preset_idx, preset_count = reaper.TrackFX_GetPresetIndex(master, fx_idx)
  end

  f:write("\n==== ", os.date("%Y-%m-%d %H:%M:%S"), " | ", tostring(tag or "dump"), " ====\n")
  f:write("FX: ", tostring(fx_name or ""), "\n")
  f:write("FX index: ", tostring(fx_idx), "\n")
  f:write("Enabled: ", tostring(reaper.TrackFX_GetEnabled and reaper.TrackFX_GetEnabled(master, fx_idx)), "\n")
  f:write("Open: ", tostring(reaper.TrackFX_GetOpen and reaper.TrackFX_GetOpen(master, fx_idx)), "\n")
  f:write("Host preset ok/name: ", tostring(preset_ok), " / ", tostring(preset_name or ""), "\n")
  f:write("Host preset index/count: ", tostring(preset_idx), " / ", tostring(preset_count), "\n")
  if reaper.TrackFX_GetNamedConfigParm then
    local keys = {
      "vst_chunk",
      "vst_chunk_program",
      "preset_name",
      "original_name",
      "fx_name",
      "container_item.0",
    }
    for _, key in ipairs(keys) do
      local ok, value = reaper.TrackFX_GetNamedConfigParm(master, fx_idx, key)
      value = tostring(value or "")
      f:write(string.format("Config %s: ok=%s len=%d checksum=%u\n",
        key, tostring(ok), #value, checksum(value)))
    end
  end

  local param_count = reaper.TrackFX_GetNumParams(master, fx_idx) or 0
  f:write("Param count: ", tostring(param_count), "\n")
  for i = 0, param_count - 1 do
    local _, name = reaper.TrackFX_GetParamName(master, fx_idx, i, "")
    local value = reaper.TrackFX_GetParam(master, fx_idx, i)
    local _, formatted = reaper.TrackFX_GetFormattedParamValue(master, fx_idx, i, "")
    local minv, maxv, midv = nil, nil, nil
    if reaper.TrackFX_GetParamEx then
      local ok, rv, mn, mx, md = pcall(reaper.TrackFX_GetParamEx, master, fx_idx, i)
      if ok then
        value = rv
        minv, maxv, midv = mn, mx, md
      end
    end
    f:write(string.format("[%03d] %-34s raw=% .9f fmt=%-18s min=%s max=%s mid=%s\n",
      i,
      tostring(name or ""),
      tonumber(value or 0) or 0,
      tostring(formatted or ""),
      tostring(minv),
      tostring(maxv),
      tostring(midv)))
  end
  f:close()
end

local function DumpRealphonesParams(master, fx_idx, tag)
  local path = (reaper.GetResourcePath and reaper.GetResourcePath() or ".") .. "/RCC_realphones_params.txt"
  local f = io.open(path, "a")
  if not f then return end

  local function checksum(text)
    text = tostring(text or "")
    local sum = 0
    for i = 1, #text do
      sum = (sum + text:byte(i) * i) % 4294967296
    end
    return sum
  end

  local param_count = reaper.TrackFX_GetNumParams(master, fx_idx)
  param_count = param_count or 0
  f:write("\n==== ", os.date("%Y-%m-%d %H:%M:%S"), " | ", tostring(tag or "dump"), " ====\n")
  f:write("Host preset: ", ReadRealphonesHostPresetName(master, fx_idx), "\n")
  f:write("Program param: ", ReadRealphonesProgramName(master, fx_idx), "\n")

  if reaper.TrackFX_GetNamedConfigParm then
    local keys = { "vst_chunk", "vst_chunk_program", "preset_name", "original_name" }
    for _, key in ipairs(keys) do
      local ok, value = reaper.TrackFX_GetNamedConfigParm(master, fx_idx, key)
      value = tostring(value or "")
      f:write(string.format("Config %s: ok=%s len=%d checksum=%u\n",
        key, tostring(ok), #value, checksum(value)))
    end
  end

  for i = 0, param_count - 1 do
    local _, name = reaper.TrackFX_GetParamName(master, fx_idx, i, "")
    local value = reaper.TrackFX_GetParam(master, fx_idx, i)
    local _, formatted = reaper.TrackFX_GetFormattedParamValue(master, fx_idx, i, "")
    f:write(string.format("[%02d] %s = %.9f (%s)\n",
      i, tostring(name or ""), tonumber(value or 0) or 0, tostring(formatted or "")))
  end
  f:close()
end

local function DumpRealphonesOutputDiagnostics(master, fx_idx, state, tag)
  DumpRealphonesParams(master, fx_idx, tag or "output diagnostics")

  local path = (reaper.GetResourcePath and reaper.GetResourcePath() or ".") .. "/RCC_realphones_params.txt"
  local f = io.open(path, "a")
  if not f then return end

  local meter = state and state.realphones_post_meter or nil
  f:write("RCC post meter active: ", tostring(meter and meter.active), "\n")
  f:write(string.format("RCC post peak L/R: %.9f / %.9f | overload %.3f dB\n",
    tonumber(meter and meter.peak_l or 0) or 0,
    tonumber(meter and meter.peak_r or 0) or 0,
    ReadPostCalOverload(meter)))

  f:write("Small positive formatted/raw candidates:\n")
  local count = reaper.TrackFX_GetNumParams(master, fx_idx) or 0
  for i = 0, count - 1 do
    local _, name = reaper.TrackFX_GetParamName(master, fx_idx, i, "")
    local raw = reaper.TrackFX_GetParam(master, fx_idx, i) or 0
    local formatted = ReadRealphonesFormattedNumber(master, fx_idx, i)
    if (formatted > 0 and formatted < 12) or (raw > 0 and raw < 0.2) then
      f:write(string.format("[%02d] %s raw=%.9f formatted=%.3f\n",
        i, tostring(name or ""), tonumber(raw) or 0, tonumber(formatted) or 0))
    end
  end
  f:close()
end

local function DumpRealphonesDiffDiagnostics(master, fx_idx, state, tag)
  local path = (reaper.GetResourcePath and reaper.GetResourcePath() or ".") .. "/RCC_realphones_diff.txt"
  local f = io.open(path, "a")
  if not f then return end

  local function checksum(text)
    text = tostring(text or "")
    local sum = 0
    for i = 1, #text do
      sum = (sum + text:byte(i) * i) % 4294967296
    end
    return sum
  end

  f:write("\n==== ", os.date("%Y-%m-%d %H:%M:%S"), " | ", tostring(tag or "diff"), " ====\n")
  f:write("Host preset: ", ReadRealphonesHostPresetName(master, fx_idx), "\n")
  f:write("Program param: ", ReadRealphonesProgramName(master, fx_idx), "\n")

  if reaper.TrackFX_GetNamedConfigParm then
    for _, key in ipairs({ "vst_chunk", "vst_chunk_program" }) do
      local ok, value = reaper.TrackFX_GetNamedConfigParm(master, fx_idx, key)
      value = tostring(value or "")
      f:write(string.format("%s ok=%s len=%d checksum=%u\n", key, tostring(ok), #value, checksum(value)))
    end
  end

  local meter = state and state.realphones_post_meter or nil
  f:write(string.format("RCC post peak L/R %.9f %.9f overload %.3f\n",
    tonumber(meter and meter.peak_l or 0) or 0,
    tonumber(meter and meter.peak_r or 0) or 0,
    ReadPostCalOverload(meter)))

  local count = reaper.TrackFX_GetNumParams(master, fx_idx) or 0
  local names = {}
  for i = 0, count - 1 do
    local _, name = reaper.TrackFX_GetParamName(master, fx_idx, i, "")
    names[i] = tostring(name or "")
  end

  for i = 0, count - 1 do
    local raw = reaper.TrackFX_GetParam(master, fx_idx, i) or 0
    local formatted = ""
    if reaper.TrackFX_GetFormattedParamValue then
      local _, fmt = reaper.TrackFX_GetFormattedParamValue(master, fx_idx, i, "")
      formatted = tostring(fmt or "")
    end
    f:write(string.format("[%02d] %-20s raw=% .9f fmt=%s\n", i, names[i], tonumber(raw) or 0, formatted))
  end

  f:close()
end

local function SetRealphonesProgram(master, fx_idx, slot)
  if not slot then return end

  if slot.full_name and slot.full_name ~= "" and reaper.TrackFX_SetPreset then
    if reaper.TrackFX_SetPreset(master, fx_idx, slot.full_name) then
      return
    end
  end

  if slot.preset_idx and reaper.TrackFX_SetPresetByIndex then
    reaper.TrackFX_SetPresetByIndex(master, fx_idx, slot.preset_idx)
    return
  end
end

local function AddRealphonesProgramGroup(groups, group_by_name, seen, full_name, slot_data)
  if full_name == "" or seen[full_name] then return end
  seen[full_name] = true

  local group_name, slot_name = SplitRealphonesProgramName(full_name)
  local group = group_by_name[group_name]
  if not group then
    group = { name = group_name, slots = {} }
    group_by_name[group_name] = group
    groups[#groups + 1] = group
  end

  slot_data = slot_data or {}
  slot_data.label = slot_name
  slot_data.full_name = full_name
  group.slots[#group.slots + 1] = slot_data
end

local function LoadRealphonesBuiltinProgramMap()
  local resource_path = reaper.GetResourcePath and reaper.GetResourcePath() or ""
  if resource_path == "" then return nil end

  local path = resource_path .. "/presets/vst3-Realphones x64-builtin.ini"
  local f = io.open(path, "r")
  if not f then return nil end

  local groups, group_by_name, seen = {}, {}, {}
  local entries = {}
  local in_factory = false

  for line in f:lines() do
    if line == "[factory]" then
      in_factory = true
    elseif line:match("^%[") then
      in_factory = false
    elseif in_factory then
      local id, name = line:match("^(%d+)=(.+)$")
      if id and name then
        entries[#entries + 1] = { idx = tonumber(id) - 1, name = name }
      end
    end
  end
  f:close()

  local preset_count = #entries
  for _, entry in ipairs(entries) do
    AddRealphonesProgramGroup(groups, group_by_name, seen, entry.name, {
      preset_idx = entry.idx,
      preset_count = preset_count,
    })
  end

  return #groups > 0 and groups or nil
end

local function BuildRealphonesProgramMap(state, master, fx_idx)
  if state.realphones_program_fx_idx == fx_idx and state.realphones_program_groups then
    return state.realphones_program_groups
  end

  local groups, group_by_name, seen = {}, {}, {}

  local function add_slot(full_name, value)
    AddRealphonesProgramGroup(groups, group_by_name, seen, full_name, { value = value })
  end

  local builtin_groups = LoadRealphonesBuiltinProgramMap()
  if builtin_groups then
    state.realphones_program_fx_idx = fx_idx
    state.realphones_program_groups = builtin_groups
    return builtin_groups
  end

  if reaper.TrackFX_GetPresetIndex and reaper.TrackFX_SetPresetByIndex then
    local old_idx, preset_count = reaper.TrackFX_GetPresetIndex(master, fx_idx)
    old_idx = old_idx or 0
    preset_count = preset_count or 0

    for preset_idx = 0, preset_count - 1 do
      reaper.TrackFX_SetPresetByIndex(master, fx_idx, preset_idx)
      local full_name = ReadRealphonesHostPresetName(master, fx_idx)
      if full_name ~= "" and not seen[full_name] then
        seen[full_name] = true
        local group_name, slot_name = SplitRealphonesProgramName(full_name)
        local group = group_by_name[group_name]
        if not group then
          group = { name = group_name, slots = {} }
          group_by_name[group_name] = group
          groups[#groups + 1] = group
        end
        group.slots[#group.slots + 1] = {
          label = slot_name,
          full_name = full_name,
          preset_idx = preset_idx,
          preset_count = preset_count,
        }
      end
    end

    reaper.TrackFX_SetPresetByIndex(master, fx_idx, old_idx)
  else
    local old_value = reaper.TrackFX_GetParam(master, fx_idx, REALPHONES_PROGRAM_PARAM) or 0
    for step = 0, 512 do
      local value = step / 512
      reaper.TrackFX_SetParam(master, fx_idx, REALPHONES_PROGRAM_PARAM, value)
      add_slot(ReadRealphonesProgramName(master, fx_idx), value)
    end
    reaper.TrackFX_SetParam(master, fx_idx, REALPHONES_PROGRAM_PARAM, old_value)
  end

  state.realphones_program_fx_idx = fx_idx
  state.realphones_program_groups = groups
  return groups
end

local function SyncRealphonesSelection(state, groups, current_name)
  for group_idx, group in ipairs(groups or {}) do
    for slot_idx, slot in ipairs(group.slots or {}) do
      if slot.full_name == current_name then
        state.realphones_cat_idx = group_idx
        state.realphones_slot_idx = slot_idx
        return group, slot
      end
    end
  end
  return groups and groups[state.realphones_cat_idx], nil
end

local function DrawVstPresetSelector(ctx, state, master, fx_idx, dl, draw_api, x, y, w, h, sf, sfs, categories, active_cat)
  local name = "Select Setup / Preset"
  if active_cat then
    name = active_cat.name
  else
    local current_idx, num_presets = 0, 0
    if reaper.TrackFX_GetPresetIndex then
      current_idx, num_presets = reaper.TrackFX_GetPresetIndex(master, fx_idx)
    end
    local ok, p_name = false, ""
    if current_idx >= 0 and reaper.TrackFX_GetPreset then
      ok, p_name = reaper.TrackFX_GetPreset(master, fx_idx, "")
    end
    if ok and p_name and p_name ~= "" then name = p_name end
  end

  w = math.max(1.0, w or 1.0)
  h = math.max(1.0, h or 1.0)
  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  reaper.ImGui_InvisibleButton(ctx, "##vst_preset_select", w, h)
  local hov = reaper.ImGui_IsItemHovered(ctx)
  if reaper.ImGui_IsItemClicked(ctx, 0) then reaper.ImGui_OpenPopup(ctx, "##vst_preset_popup") end

  draw_api.rect_filled(dl, x, y, x + w, y + h, hov and 0x171B22FF or 0x12151AFF, 4.0)
  draw_api.rect(dl,        x, y, x + w, y + h, hov and 0x2B5F48CC or 0x272B33CC, 4.0, nil, 1.0)
  if hov then draw_api.rect_filled(dl, x + 1, y + h - 2, x + w - 1, y + h - 1, 0x5CFFB655, 2.0) end

  UIUtils.DrawButtonTextInRect(ctx, dl, x, y, w, h, name, 0xE8EAF0EE, sf, sfs, 7, 2)

  -- Drop-down popup
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(),      0x111216FA)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),       0x2B5F4877)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(),       0x183A2BFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(),0x245C42FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x10291EFF)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(), 5.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 6, 6)
  
  local cond_app = reaper.ImGui_Cond_Appearing and reaper.ImGui_Cond_Appearing() or 0
  reaper.ImGui_SetNextWindowSize(ctx, math.max(180, w), 0, cond_app)
  if reaper.ImGui_BeginPopup(ctx, "##vst_preset_popup") then
    for idx, cat in ipairs(categories or {}) do
      local is_sel = active_cat and (active_cat.name == cat.name)
      if reaper.ImGui_Selectable(ctx, cat.name .. "##vst_cat_" .. idx, is_sel) then
        state.realphones_cat_idx = idx
        state.realphones_slot_idx = 1 -- Reset to first slot when category changes
        if cat.slots and cat.slots[1] then
          SetRealphonesProgram(master, fx_idx, cat.slots[1])
        end
      end
    end
    reaper.ImGui_EndPopup(ctx)
  end
  reaper.ImGui_PopStyleVar(ctx, 2)
  reaper.ImGui_PopStyleColor(ctx, 5)
end

local function ReadRealphonesCorrectionAmount(master, fx_idx)
  local amount = reaper.TrackFX_GetParam(master, fx_idx, REALPHONES_EASY_CORRECTION_AMOUNT_PARAM)
  if amount == nil then
    amount = reaper.TrackFX_GetParam(master, fx_idx, REALPHONES_CORRECTION_AMOUNT_PARAM)
  end
  return math.max(0.0, math.min(1.0, amount or 0))
end

local function SetRealphonesCorrectionAmount(master, fx_idx, amount)
  amount = math.max(0.0, math.min(1.0, amount or 0))
  reaper.TrackFX_SetParam(master, fx_idx, REALPHONES_EASY_CORRECTION_AMOUNT_PARAM, amount)
  reaper.TrackFX_SetParam(master, fx_idx, REALPHONES_CORRECTION_AMOUNT_PARAM, amount)
end

local realphones_reset_locks = {}

local function HandleDoubleClickReset(ctx, id, default_value, setter)
  if realphones_reset_locks[id] then
    local mouse_down = reaper.ImGui_IsMouseDown and reaper.ImGui_IsMouseDown(ctx, 0)
    if mouse_down then return true end
    realphones_reset_locks[id] = nil
  end

  if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
    setter(default_value)
    realphones_reset_locks[id] = true
    return true
  end
  return false
end

local function DrawRealphonesMiniSlider(ctx, master, fx_idx, param_idx, id, label, value_text, default_value, x, y, w, h, label_w, value_w, dl, draw_api, sf, sfs, enabled)
  enabled = enabled ~= false
  local gap = 6
  local slider_x = x + label_w
  local slider_w = math.max(42, w - label_w - value_w - gap * 2)
  local slider_y = y + math.floor(h * 0.5) + 1
  local value = math.max(0.0, math.min(1.0, reaper.TrackFX_GetParam(master, fx_idx, param_idx) or 0))

  if sf then reaper.ImGui_PushFont(ctx, sf, sfs) end
  local alpha_col = enabled and 0xFFFFFFFF or 0xFFFFFF66
  draw_api.text(dl, x, y + 3, 0xB8BEC8EE & alpha_col, label)
  local vt = value_text(value)
  draw_api.text(dl, slider_x + slider_w + gap, y + 3, 0xE8EAF0EE & alpha_col, vt)
  if sf then reaper.ImGui_PopFont(ctx) end

  reaper.ImGui_SetCursorScreenPos(ctx, slider_x, y)
  reaper.ImGui_InvisibleButton(ctx, id, slider_w, h)
  local hovered = reaper.ImGui_IsItemHovered(ctx)
  local reset = enabled and HandleDoubleClickReset(ctx, id, default_value, function(v) reaper.TrackFX_SetParam(master, fx_idx, param_idx, v) end)
  if reset then
    value = default_value
  end
  if enabled and (not reset) and reaper.ImGui_IsItemActive(ctx) then
    local mouse_x = ({ reaper.ImGui_GetMousePos(ctx) })[1] or slider_x
    value = math.max(0.0, math.min(1.0, (mouse_x - slider_x) / math.max(1.0, slider_w)))
    reaper.TrackFX_SetParam(master, fx_idx, param_idx, value)
  end

  draw_api.line(dl, slider_x, slider_y, slider_x + slider_w, slider_y, (hovered and enabled) and 0x3A414DFF or 0x272D35FF, 2.0)
  draw_api.line(dl, slider_x, slider_y, slider_x + slider_w * value, slider_y, 0x5CFFB6CC & alpha_col, 2.0)
  draw_api.circle_filled(dl, slider_x + slider_w * value, slider_y, 4.0, enabled and 0xFFC45CFF or 0x8C94A0AA)
end

local function DrawRealphonesCorrectionStrip(ctx, master, fx_idx, dl, draw_api, x, y, w, h, sf, sfs)
  local enabled = (reaper.TrackFX_GetParam(master, fx_idx, REALPHONES_CORRECTION_ENABLED_PARAM) or 0) > 0.5
  local amount = ReadRealphonesCorrectionAmount(master, fx_idx)

  local gap = 6
  local label_w = 66
  local value_w = 42
  local icon_w = 18
  local slider_w = math.max(42, w - label_w - value_w - icon_w - gap * 3)

  local alpha_col = enabled and 0xFFFFFFFF or 0xFFFFFF77

  local label_x = x
  if sf then reaper.ImGui_PushFont(ctx, sf, sfs) end
  draw_api.text(dl, label_x, y + 4, 0xB8BEC8EE & alpha_col, "Correction")
  if sf then reaper.ImGui_PopFont(ctx) end

  local slider_x = x + label_w
  local slider_y = y + math.floor(h * 0.5) + 1
  local slider_h = h
  reaper.ImGui_SetCursorScreenPos(ctx, slider_x, y)
  reaper.ImGui_InvisibleButton(ctx, "##realphones_corr_slider", slider_w, slider_h)
  local hovered = reaper.ImGui_IsItemHovered(ctx)
  local active = reaper.ImGui_IsItemActive(ctx)
  local reset = HandleDoubleClickReset(ctx, "##realphones_corr_slider", 1.0, function(v) SetRealphonesCorrectionAmount(master, fx_idx, v) end)
  if reset then
    amount = 1.0
  end
  if (not reset) and active then
    local mouse_x = ({ reaper.ImGui_GetMousePos(ctx) })[1] or slider_x
    local next_amount = math.max(0.0, math.min(1.0, (mouse_x - slider_x) / math.max(1.0, slider_w)))
    SetRealphonesCorrectionAmount(master, fx_idx, next_amount)
    amount = next_amount
  end

  local track_col = hovered and 0x3A414DFF or 0x272D35FF
  draw_api.line(dl, slider_x, slider_y, slider_x + slider_w, slider_y, track_col & alpha_col, 2.0)
  draw_api.line(dl, slider_x, slider_y, slider_x + slider_w * amount, slider_y, 0x5CFFB6CC & alpha_col, 2.0)
  draw_api.circle_filled(dl, slider_x + slider_w * amount, slider_y, 4.0, enabled and 0xFFC45CFF or 0x8C94A0CC)

  local pct = tostring(math.floor(amount * 100 + 0.5)) .. "%"
  if sf then reaper.ImGui_PushFont(ctx, sf, sfs) end
  draw_api.text(dl, slider_x + slider_w + gap, y + 4, enabled and 0xE8EAF0FF or 0x8C94A0DD, pct)
  if sf then reaper.ImGui_PopFont(ctx) end

  if DrawPowerIconButton(ctx, dl, draw_api, "##realphones_corr_power",
      x + w - icon_w, y, icon_w, h, enabled, true) then
    reaper.TrackFX_SetParam(master, fx_idx, REALPHONES_CORRECTION_ENABLED_PARAM, enabled and 0.0 or 1.0)
  end
end

local function DrawRealphonesRoomStrip(ctx, master, fx_idx, dl, draw_api, x, y, w, h, sf, sfs, enabled)
  enabled = enabled ~= false
  local gap = 6
  local label_w = 66
  local value_w = 42
  local icon_w = 18
  local btn_w = 28
  local right_w = btn_w * 2 + gap
  local sliders_w = math.max(120, w - right_w - gap)
  local row_h = math.floor((h - 4) / 2)
  local room_enabled = (reaper.TrackFX_GetParam(master, fx_idx, REALPHONES_ROOM_ENABLED_PARAM) or 0) > 0.5

  DrawRealphonesMiniSlider(ctx, master, fx_idx, REALPHONES_ENVIRONMENT_PARAM,
    "##real_env_slider", "Environment", function(v) return tostring(math.floor(v * 100 + 0.5)) .. "%" end,
    1.0, x, y, sliders_w, row_h, label_w, value_w, dl, draw_api, sf, sfs, enabled)
  DrawRealphonesMiniSlider(ctx, master, fx_idx, REALPHONES_BRIGHTNESS_PARAM,
    "##real_bright_slider", "Brightness", function(v) return string.format("%.1fdB", (v * 14.0) - 7.0) end,
    0.5, x, y + row_h + 4, sliders_w, row_h, label_w, value_w, dl, draw_api, sf, sfs, enabled)

  local bx = x + sliders_w + gap
  local power_x = bx + math.floor((right_w - icon_w) * 0.5)
  if DrawPowerIconButton(ctx, dl, draw_api, "##real_room_power",
      power_x, y, icon_w, row_h, room_enabled and enabled, enabled) then
    reaper.TrackFX_SetParam(master, fx_idx, REALPHONES_ROOM_ENABLED_PARAM, room_enabled and 0.0 or 1.0)
  end

  local listen_val = reaper.TrackFX_GetParam(master, fx_idx, REALPHONES_LISTEN_TYPE_PARAM) or 0.0
  local m_active = listen_val >= 0.15 and listen_val < 0.40
  local s_active = listen_val >= 0.40 and listen_val < 0.65
  if DrawTinyTextButton(ctx, dl, draw_api, "##real_room_m", "M", bx, y + row_h + 4, btn_w, row_h, m_active, sf, sfs, true) then
    reaper.TrackFX_SetParam(master, fx_idx, REALPHONES_LISTEN_TYPE_PARAM, m_active and 0.0 or 0.25)
  end
  if DrawTinyTextButton(ctx, dl, draw_api, "##real_room_s", "S", bx + btn_w + gap, y + row_h + 4, btn_w, row_h, s_active, sf, sfs, true) then
    reaper.TrackFX_SetParam(master, fx_idx, REALPHONES_LISTEN_TYPE_PARAM, s_active and 0.0 or 0.50)
  end
end

local function SonarworksGainText(value)
  return string.format("%.1fdB", (math.max(0.0, math.min(1.0, value or 0.0)) * 90.0) - 90.0)
end

local function SonarworksPercentText(value)
  return tostring(math.floor((math.max(0.0, math.min(1.0, value or 0.0)) * 100.0) + 0.5)) .. "%"
end

local function ToggleFxParam(master, fx_idx, param_idx)
  local value = reaper.TrackFX_GetParam(master, fx_idx, param_idx) or 0.0
  reaper.TrackFX_SetParam(master, fx_idx, param_idx, value > 0.5 and 0.0 or 1.0)
end

local function DrawSonarworksControlStrip(ctx, master, fx_idx, dl, draw_api, x, y, w, h, sf, sfs)
  local gap = 6
  local row_h = 18
  local label_w = 66
  local value_w = 50
  local btn_w = math.floor((w - gap * 4) / 5)
  local slider_w = w

  DrawRealphonesMiniSlider(ctx, master, fx_idx, SONAR_GAIN_PARAM,
    "##sonar_gain_slider", "Gain", SonarworksGainText,
    1.0, x, y, slider_w, row_h, label_w, value_w, dl, draw_api, sf, sfs, true)

  local mix_y = y + row_h + 5
  DrawRealphonesMiniSlider(ctx, master, fx_idx, SONAR_DRY_WET_PARAM,
    "##sonar_mix_slider", "Mix", SonarworksPercentText,
    1.0, x, mix_y, slider_w, row_h, label_w, value_w, dl, draw_api, sf, sfs, true)

  local btn_y = mix_y + row_h + 7
  local cal = (reaper.TrackFX_GetParam(master, fx_idx, SONAR_CALIBRATION_PARAM) or 0.0) > 0.5
  local safe = (reaper.TrackFX_GetParam(master, fx_idx, SONAR_SAFE_HEADROOM_PARAM) or 0.0) > 0.5
  local mono = (reaper.TrackFX_GetParam(master, fx_idx, SONAR_MONO_PARAM) or 0.0) > 0.5
  local mute = (reaper.TrackFX_GetParam(master, fx_idx, SONAR_MUTE_PARAM) or 0.0) > 0.5
  local lr = (reaper.TrackFX_GetParam(master, fx_idx, SONAR_LR_SWAP_PARAM) or 0.0) > 0.5

  local labels = {
    { id = "##sonar_cal", label = "CAL", active = cal, param = SONAR_CALIBRATION_PARAM },
    { id = "##sonar_safe", label = "SAFE", active = safe, param = SONAR_SAFE_HEADROOM_PARAM },
    { id = "##sonar_mono", label = "MONO", active = mono, param = SONAR_MONO_PARAM },
    { id = "##sonar_mute", label = "MUTE", active = mute, param = SONAR_MUTE_PARAM },
    { id = "##sonar_lr", label = "L/R", active = lr, param = SONAR_LR_SWAP_PARAM },
  }

  for i, item in ipairs(labels) do
    local bx = x + (i - 1) * (btn_w + gap)
    if DrawTinyTextButton(ctx, dl, draw_api, item.id, item.label, bx, btn_y, btn_w, row_h, item.active, sf, sfs, true) then
      ToggleFxParam(master, fx_idx, item.param)
    end
  end
end

local function FormatRealphonesOutputDb(value)
  return string.format("%.1fdB", (math.max(0.0, math.min(1.0, value or 0.0)) * 36.0) - 30.0)
end

ReadRealphonesFormattedNumber = function(master, fx_idx, param_idx)
  if not reaper.TrackFX_GetFormattedParamValue then return 0.0 end
  local _, formatted = reaper.TrackFX_GetFormattedParamValue(master, fx_idx, param_idx, "")
  formatted = tostring(formatted or ""):gsub(",", ".")
  local num = formatted:match("[-+]?%d+%.?%d*")
  return tonumber(num) or 0.0
end

local function ReadRealphonesOverload(master, fx_idx)
  local formatted = ReadRealphonesFormattedNumber(master, fx_idx, REALPHONES_PEAK_PARAM)
  if math.abs(formatted) > 0.0001 then
    return math.max(0.0, formatted)
  end

  local raw = reaper.TrackFX_GetParam(master, fx_idx, REALPHONES_PEAK_PARAM) or 0.0
  if raw <= 0.0001 then
    return 0.0
  end

  -- Some Realphones builds expose the indicator as normalized host data but
  -- keep the display formatter at zero until the GUI refreshes.
  return math.max(0.0, raw * 100.0)
end

local function LinearToDb(value)
  local amp = math.max(0.0, value or 0.0)
  if amp <= 0.000001 then return -150.0 end
  return 20.0 * math.log(amp) / math.log(10)
end

ReadPostCalOverload = function(meter)
  if not meter or not meter.active then return 0.0 end
  local peak = math.max(meter.hold_l or 0.0, meter.hold_r or 0.0)
  return math.max(0.0, LinearToDb(peak))
end

local function RealphonesOutputNormToDb(value)
  return (math.max(0.0, math.min(1.0, value or 0.0)) * 36.0) - 30.0
end

local function RealphonesOutputDbToNorm(db)
  return math.max(0.0, math.min(1.0, ((db or 0.0) + 30.0) / 36.0))
end

local function DrawTrimLeftButton(ctx, dl, draw_api, id, x, y, w, h, active, enabled)
  enabled = enabled ~= false
  w = math.max(1.0, w or 1.0)
  h = math.max(1.0, h or 1.0)
  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = reaper.ImGui_InvisibleButton(ctx, id, w, h)
  local hov = reaper.ImGui_IsItemHovered(ctx)

  local bg = active and 0x2B2112FF or (hov and enabled and 0x201A1033 or 0x12151AFF)
  local brd = active and 0xFFC45C99 or (hov and enabled and 0xFFC45C55 or 0xFFFFFF14)
  local col = enabled and 0xFFC45CFF or 0x6C737CE0
  draw_api.rect_filled(dl, x, y, x + w, y + h, bg, 4.0)
  draw_api.rect(dl, x, y, x + w, y + h, brd, 4.0, nil, 1.0)

  local mid_y = math.floor(y + h * 0.5 + 0.5)
  local left = math.floor(x + w * 0.30 + 0.5)
  local right = math.floor(x + w * 0.72 + 0.5)
  local wing = math.floor(math.min(w, h) * 0.22 + 0.5)
  draw_api.line(dl, right, mid_y, left, mid_y, col, 1.6)
  draw_api.line(dl, left, mid_y, left + wing, mid_y - wing, col, 1.6)
  draw_api.line(dl, left, mid_y, left + wing, mid_y + wing, col, 1.6)

  return clicked and enabled
end

local function DrawRealphonesPeakIndicator(ctx, dl, draw_api, id, x, y, w, h, peak, sf, sfs, enabled)
  enabled = enabled ~= false
  local has_value = peak ~= nil
  peak = math.max(0.0, peak or 0.0)
  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = reaper.ImGui_InvisibleButton(ctx, id, w, h)
  local hov = reaper.ImGui_IsItemHovered(ctx)

  local hot = has_value and peak > 0.05
  local bg = hot and 0x3A1414DD or 0x12151AFF
  local brd = hot and 0xFF5C5C99 or (hov and enabled and 0xFFC45C55 or 0xFFFFFF14)
  draw_api.rect_filled(dl, x, y, x + w, y + h, bg, 4.0)
  draw_api.rect(dl, x, y, x + w, y + h, brd, 4.0, nil, 1.0)

  local txt = has_value and (hot and string.format("%.1f", peak) or "0.0") or "--"
  UIUtils.DrawButtonTextInRect(ctx, dl, x, y, w, h, txt,
    hot and (enabled and 0xFF5C5CFF or 0x8C94A0DD) or 0x6C737CAA, sf, sfs)

  return peak
end

local function LinearToMeterNorm(value)
  local db = LinearToDb(value)
  return math.max(0.0, math.min(1.0, (db + 60.0) / 60.0))
end

local function DrawPostCalMeters(state, dl, draw_api, x, y, w, h, enabled)
  local meter = PostCalMeter.Read()
  state.realphones_post_meter = meter
  state.realphones_post_meter_l = math.max(meter.peak_l or 0.0, (state.realphones_post_meter_l or 0.0) * 0.86)
  state.realphones_post_meter_r = math.max(meter.peak_r or 0.0, (state.realphones_post_meter_r or 0.0) * 0.86)

  local gap = 3
  local bar_w = math.max(2, math.floor((w - gap) * 0.5))
  local function draw_one(index, value)
    local bx = x + index * (bar_w + gap)
    local norm = enabled and meter.active and LinearToMeterNorm(value) or 0.0
    local fill_h = math.floor(h * norm + 0.5)
    draw_api.rect_filled(dl, bx, y, bx + bar_w, y + h, 0x0A0D10FF, 1.0)
    if fill_h > 0 then
      local col = norm > 0.92 and 0xFF5C5CFF or (norm > 0.78 and 0xFFC45CFF or 0x35D56EFF)
      draw_api.rect_filled(dl, bx, y + h - fill_h, bx + bar_w, y + h, col, 1.0)
    end
    draw_api.rect(dl, bx, y, bx + bar_w, y + h, enabled and 0xFFFFFF18 or 0xFFFFFF0C, 1.0, nil, 1.0)
  end

  draw_one(0, state.realphones_post_meter_l)
  draw_one(1, state.realphones_post_meter_r)
end

local function DrawRealphonesOutputStrip(ctx, state, master, fx_idx, dl, draw_api, x, y, w, h, sf, sfs, enabled)
  enabled = enabled ~= false
  local gap = 6
  local row_h = 18
  local label_w = 66
  local value_w = 50
  local trim_w = 24
  local peak_w = 30
  local meter_w = 16
  local control_w = trim_w + gap + peak_w
  local meter_x = x + w - meter_w
  local slider_w = math.max(120, w - meter_w - control_w - gap * 2)
  local control_x = x + slider_w + gap
  local trim_x = control_x
  local peak_x = trim_x + trim_w + gap
  DrawRealphonesMiniSlider(ctx, master, fx_idx, REALPHONES_OUTPUT_PARAM,
    "##real_output_slider", "Output", FormatRealphonesOutputDb,
    REALPHONES_OUTPUT_UNITY, x, y, slider_w, row_h, label_w, value_w,
    dl, draw_api, sf, sfs, enabled)
  DrawPostCalMeters(state, dl, draw_api, meter_x, y + 1, meter_w, row_h * 2 + 3, enabled)

  local row2_y = y + row_h + 4
  local meter_peak = ReadPostCalOverload(state.realphones_post_meter)
  local peak = meter_peak
  local has_overload = peak > 0.05
  if DrawTrimLeftButton(ctx, dl, draw_api, "##real_overload_trim",
      trim_x, y, trim_w, row_h, has_overload, enabled and has_overload) then
    local current = reaper.TrackFX_GetParam(master, fx_idx, REALPHONES_OUTPUT_PARAM) or REALPHONES_OUTPUT_UNITY
    if has_overload then
      local next_db = RealphonesOutputNormToDb(current) - peak
      reaper.TrackFX_SetParam(master, fx_idx, REALPHONES_OUTPUT_PARAM, RealphonesOutputDbToNorm(next_db))
      reaper.TrackFX_SetParam(master, fx_idx, REALPHONES_PEAK_PARAM, 0.0)
      PostCalMeter.ResetHold()
    end
  end
  DrawRealphonesPeakIndicator(ctx, dl, draw_api,
    "##real_peak_indicator", peak_x, y, peak_w, row_h,
    has_overload and peak or nil, sf, sfs, enabled)
  if reaper.ImGui_IsItemClicked(ctx, 1) then
    DumpRealphonesOutputDiagnostics(master, fx_idx, state, "right-click overload field")
    DumpRealphonesDiffDiagnostics(master, fx_idx, state, "right-click overload field")
  end

  local lim_val = reaper.TrackFX_GetParam(master, fx_idx, REALPHONES_LIMITER_PARAM)
  local lim_act = (lim_val and lim_val > 0.5)
  if DrawTinyTextButton(ctx, dl, draw_api, "##real_lim_btn", "LIMITER",
      control_x, row2_y, control_w, row_h, lim_act and enabled, sf, sfs, enabled) then
    reaper.TrackFX_SetParam(master, fx_idx, REALPHONES_LIMITER_PARAM, lim_act and 0.0 or 1.0)
  end
end

---------------------------------------------------------------------------
-- Body: External provider (Sonarworks / Realphones)
---------------------------------------------------------------------------
local function DrawExternalBody(ctx, state, dl, draw_api, x, y, width, sf, sfs)
  HeadphoneCalibrationManager.FindExternalProviderFx(state)
  local provider = HeadphoneCalibrationManager.GetProvider(state.hp_cal_provider)

  local pad   = 8
  local cw    = width - pad * 2
  local lx    = x + pad
  local row_y = y + BODY_V_PAD
  local btn_h = 20

  local found  = (state.hp_cal_external_found  == true)
  local active = (state.hp_cal_external_active == true)
  local master = reaper.GetMasterTrack(0)
  local is_realphones = (state.hp_cal_provider == "realphones")
  local is_sonarworks = (state.hp_cal_provider == "sonarworks")

  if not found or not master then
    local st_txt = "ADD " .. (provider.label or "PLUGIN"):upper() .. " TO MONITORING FX"
    if sf then reaper.ImGui_PushFont(ctx, sf, sfs) end
    local sw = UIUtils.TextWidth(ctx, st_txt)
    draw_api.text(dl,
      math.floor(lx + (cw - sw) * 0.5),
      math.floor(row_y + 9),
      0xD55353BB, st_txt)
    if sf then reaper.ImGui_PopFont(ctx) end
    return
  end

  if is_realphones then
    local ok, err = PostCalMeter.EnsureInstalled()
    if ok then
      MonitorFxChain.EnsureOrder(true)
      HeadphoneCalibrationManager.FindExternalProviderFx(state)
      found = (state.hp_cal_external_found == true)
      active = (state.hp_cal_external_active == true)
    elseif err then
      state.analyzer_error = err
    end
  end

  local fx_idx = state.hp_cal_external_fx_idx
  if not found or not fx_idx then
    return
  end

  if is_realphones and realphones_debug_auto_dump then
    local now = reaper.time_precise and reaper.time_precise() or 0
    if now - realphones_last_auto_dump > 1.0 then
      realphones_last_auto_dump = now
      DumpRealphonesDiffDiagnostics(master, fx_idx, state, "auto")
    end
  end

  -- Find active Category / Slot with State-Based Category Tracking
  local active_preset_idx = 0
  local realphones_groups = nil
  local active_cat = nil
  if is_realphones then
    realphones_groups = BuildRealphonesProgramMap(state, master, fx_idx)
    local current_program_name = ReadRealphonesHostPresetName(master, fx_idx)
    state.realphones_last_program_name = current_program_name
    active_cat = SyncRealphonesSelection(state, realphones_groups, current_program_name)
  elseif reaper.TrackFX_GetPresetIndex then
    active_preset_idx = reaper.TrackFX_GetPresetIndex(master, fx_idx) or 0
  end

  -- Default fallback if state is still uninitialized
  if is_realphones and not state.realphones_cat_idx then
    state.realphones_cat_idx = 1
    state.realphones_slot_idx = 1
  end

  active_cat = is_realphones and (active_cat or (realphones_groups and realphones_groups[state.realphones_cat_idx])) or nil

  local realphones_correction_enabled = true
  if is_realphones then
    realphones_correction_enabled = (reaper.TrackFX_GetParam(master, fx_idx, REALPHONES_CORRECTION_ENABLED_PARAM) or 0) > 0.5
    DrawRealphonesCorrectionStrip(ctx, master, fx_idx, dl, draw_api, lx, row_y, cw, btn_h, sf, sfs)
    row_y = row_y + btn_h + 6
    DrawRealphonesRoomStrip(ctx, master, fx_idx, dl, draw_api, lx, row_y, cw, 44, sf, sfs, realphones_correction_enabled)
    row_y = row_y + 44 + 6
    DrawRealphonesOutputStrip(ctx, state, master, fx_idx, dl, draw_api, lx, row_y, cw, 40, sf, sfs, realphones_correction_enabled)
    row_y = row_y + 40 + 6
  elseif is_sonarworks then
    DrawSonarworksControlStrip(ctx, master, fx_idx, dl, draw_api, lx, row_y, cw, 66, sf, sfs)
    row_y = row_y + 66 + 6
  end

  -- ── ROW 1: CAL TOGGLE + PRESETS DROPDOWN + OPEN GUI BUTTON ──────────────────
  local power_w = 48
  local gui_w   = 28
  local drop_w  = cw - power_w - gui_w - 12 -- 6px gap * 2
  
  -- Power (Cal) Toggle
  if DrawTinyTextButton(ctx, dl, draw_api, "##ext_cal_btn", "POWER",
      lx, row_y, power_w, btn_h, active, sf, sfs, not (is_realphones and not realphones_correction_enabled)) then
    HeadphoneCalibrationManager.SetExternalProviderActive(state, not active)
  end

  -- Dropdown preset selector
  if is_realphones then
    if realphones_correction_enabled then
      DrawVstPresetSelector(ctx, state, master, fx_idx, dl, draw_api,
        lx + power_w + 6, row_y, drop_w, btn_h, sf, sfs, realphones_groups, active_cat)
    else
      DrawTinyTextButton(ctx, dl, draw_api, "##vst_preset_disabled", active_cat and active_cat.name or "Preset",
        lx + power_w + 6, row_y, drop_w, btn_h, false, sf, sfs, false)
    end
  elseif is_sonarworks then
    -- SoundID speaker and target modes are only available in the plugin GUI.
  else
    -- Fallback: Sonarworks or others (simple preset selector)
    local name = "Select Setup"
    local cur_idx = 0
    if reaper.TrackFX_GetPresetIndex then cur_idx = reaper.TrackFX_GetPresetIndex(master, fx_idx) or 0 end
    local ok, p_name = false, ""
    if reaper.TrackFX_GetPreset then ok, p_name = reaper.TrackFX_GetPreset(master, fx_idx, "") end
    if ok and p_name and p_name ~= "" then name = p_name end

    reaper.ImGui_SetCursorScreenPos(ctx, lx + power_w + 6, row_y)
    reaper.ImGui_InvisibleButton(ctx, "##vst_preset_select", drop_w, btn_h)
    local hov = reaper.ImGui_IsItemHovered(ctx)
    if reaper.ImGui_IsItemClicked(ctx, 0) then reaper.ImGui_OpenPopup(ctx, "##vst_preset_popup_simple") end
    draw_api.rect_filled(dl, lx + power_w + 6, row_y, lx + power_w + 6 + drop_w, row_y + btn_h, hov and 0x171B22FF or 0x12151AFF, 4.0)
    draw_api.rect(dl,        lx + power_w + 6, row_y, lx + power_w + 6 + drop_w, row_y + btn_h, hov and 0x2B5F48CC or 0x272B33CC, 4.0, nil, 1.0)
    local lbl = Ellipsize(ctx, name, math.max(8, drop_w - 14))
    UIUtils.DrawButtonTextInRect(ctx, dl, lx + power_w + 6, row_y, drop_w, btn_h, lbl, 0xE8EAF0EE, sf, sfs, 7, 2)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x111216FA)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),  0x2B5F4877)
    if reaper.ImGui_BeginPopup(ctx, "##vst_preset_popup_simple") then
      local _, preset_count = 0, 0
      if reaper.TrackFX_GetPresetIndex then _, preset_count = reaper.TrackFX_GetPresetIndex(master, fx_idx) end
      if (preset_count or 0) > 0 then
        for idx = 0, preset_count - 1 do
          if reaper.ImGui_Selectable(ctx, "Preset " .. (idx + 1) .. "##vstp_s_" .. idx, cur_idx == idx) then
            if reaper.TrackFX_SetPresetByIndex then reaper.TrackFX_SetPresetByIndex(master, fx_idx, idx) end
          end
        end
      else
        reaper.ImGui_TextDisabled(ctx, "No VST presets")
      end
      reaper.ImGui_EndPopup(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx, 2)
  end

  -- GUI Open Button
  local gui_open = false
  if reaper.TrackFX_GetOpen then
    gui_open = (reaper.TrackFX_GetOpen(master, fx_idx) == true)
  end
  local gui_x = is_sonarworks and (lx + cw - gui_w) or (lx + power_w + drop_w + 12)
  local gui_clicked = DrawTinyTextButton(ctx, dl, draw_api, "##ext_gui_btn", "GUI",
      gui_x, row_y, gui_w, btn_h, gui_open, sf, sfs, true)
  if reaper.ImGui_IsItemClicked(ctx, 1) then
    if is_realphones then
      DumpRealphonesParams(master, fx_idx, "right-click GUI")
      DumpRealphonesDiffDiagnostics(master, fx_idx, state, "right-click GUI")
    else
      DumpExternalFxParams(master, fx_idx, state.hp_cal_provider, "right-click GUI")
    end
  end
  if gui_clicked then
    if gui_open then
      reaper.TrackFX_Show(master, fx_idx, 2) -- hide VST GUI
    else
      reaper.TrackFX_Show(master, fx_idx, 3) -- float VST GUI
    end
  end

  -- ── ROW 2: THREE PRESET QUICK BUTTONS + LIMITER ────────────────────────────
  if is_sonarworks then
    return
  end

  local row2_y = row_y + btn_h + 6
  
  local slots_total_w = cw
  local slot_w = math.floor((slots_total_w - 12) / 3)

  -- Draw 3 Quick Presets Buttons (switching VST internal Programs of active category)
  if is_realphones and active_cat then
    local slot_count = math.max(1, math.min(3, #(active_cat.slots or {})))
    slot_w = math.floor((slots_total_w - 6 * (slot_count - 1)) / slot_count)
    for i = 1, slot_count do
      local slot = active_cat.slots[i]
      local label = ShortenPreset(slot and slot.label or "", 10)
      local active_btn = realphones_correction_enabled and (state.realphones_slot_idx == i)
      
      local btn_x = lx + (i - 1) * (slot_w + 6)
      local slot_clicked = DrawTinyTextButton(ctx, dl, draw_api, "##vstp_quick_" .. i, label,
          btn_x, row2_y, slot_w, btn_h, active_btn, sf, sfs, realphones_correction_enabled)
      if realphones_correction_enabled and reaper.ImGui_IsItemClicked(ctx, 1) then
        DumpRealphonesParams(master, fx_idx, "button " .. tostring(slot and slot.full_name or label))
      end
      if realphones_correction_enabled and slot_clicked then
        state.realphones_slot_idx = i
        SetRealphonesProgram(master, fx_idx, slot)
      end
    end
  else
    -- Fallback for Sonarworks / others
    for i = 0, 2 do
      local label = "P" .. (i + 1)
      local active_btn = (active_preset_idx == i)
      local btn_x = lx + i * (slot_w + 6)
      if DrawTinyTextButton(ctx, dl, draw_api, "##vstp_quick_" .. i, label,
          btn_x, row2_y, slot_w, btn_h, active_btn, sf, sfs, true) then
        if reaper.TrackFX_SetPresetByIndex then
          reaper.TrackFX_SetPresetByIndex(master, fx_idx, i)
        end
      end
    end
  end
end



---------------------------------------------------------------------------
-- Animated body container
---------------------------------------------------------------------------
local function DrawProviderBody(ctx, state, parent_dl, draw_api, x, y, width, vis_h, sf, sfs)
  local pid   = hp_anim.showing_provider
  if not pid or vis_h < 2 then return 0 end

  -- Background on the parent draw list (renders behind child content)
  draw_api.rect_filled(parent_dl, x, y, x + width, y + vis_h, 0x0C0F12CC, 5.0)

  -- Child window: automatically clips both drawing and hit-regions to vis_h
  local flags = 0
  if reaper.ImGui_WindowFlags_NoScrollbar       then flags = flags | reaper.ImGui_WindowFlags_NoScrollbar()       end
  if reaper.ImGui_WindowFlags_NoScrollWithMouse  then flags = flags | reaper.ImGui_WindowFlags_NoScrollWithMouse() end

  reaper.ImGui_PushStyleVar(ctx,   reaper.ImGui_StyleVar_WindowPadding(), 0, 0)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x00000000)
  reaper.ImGui_SetCursorScreenPos(ctx, x, y)

  if reaper.ImGui_BeginChild(ctx, "##hp_body_child", width, vis_h, 0, flags) then
    local cdl    = reaper.ImGui_GetWindowDrawList(ctx)
    local bx, by = reaper.ImGui_GetCursorScreenPos(ctx)
    if pid == "roof" then
      DrawRoofBody(ctx, state, cdl, draw_api, bx, by, width, sf, sfs)
    else
      DrawExternalBody(ctx, state, cdl, draw_api, bx, by, width, sf, sfs)
    end
    reaper.ImGui_EndChild(ctx)
  end

  reaper.ImGui_PopStyleColor(ctx, 1)
  reaper.ImGui_PopStyleVar(ctx, 1)

  -- Border drawn AFTER EndChild so it sits on top of child content
  draw_api.rect(parent_dl, x, y, x + width, y + vis_h, 0x22252ABB, 5.0, nil, 1.0)

  return vis_h
end

---------------------------------------------------------------------------
-- Main Draw
---------------------------------------------------------------------------
function HeadphoneCalPanel.Draw(ctx, state, sf, sfs)
  HeadphoneCalibrationManager.InitState(state)

  -- One-time: sync animation state with saved provider preference
  if not hp_anim.showing_provider then
    hp_anim.showing_provider = state.hp_cal_provider or "roof"
  end

  local draw_api = UIUtils.GetDrawApi()
  if not draw_api then return end

  local dl    = draw_api.get_draw_list(ctx)
  local x, y  = draw_api.get_cursor_pos(ctx)
  local width = reaper.ImGui_GetContentRegionAvail(ctx)
  local right = x + width

  -- ── 1. Calculate height of animated body first ────────────────────────────
  local collapse_state = UIUtils.GetCollapseState(state, "hp_correction")
  if collapse_state and hp_anim.t > 0 then
    hp_anim.t = 0
    hp_anim.last_time = nil
  end

  local eased = TickAnim()
  local pid   = hp_anim.showing_provider
  local body_h = 0
  if pid and hp_anim.t >= 0.001 then
    local full_h = ROOF_BODY_H
    if pid ~= "roof" then
      HeadphoneCalibrationManager.FindExternalProviderFx(state)
      local missing = state.hp_cal_external_found == false
      if missing then
        full_h = MISSING_BODY_H
      elseif pid == "realphones" then
        full_h = REAL_BODY_H
      elseif pid == "sonarworks" then
        full_h = SONAR_BODY_H
      else
        full_h = EXT_BODY_H
      end
    end
    body_h  = math.floor(eased * full_h)
  end

  local HEADER_H = 26
  local GAP      = 4
  local padding  = body_h > 0 and 8 or 0
  local full_total_h = 22 + (body_h > 0 and (HEADER_H + GAP + body_h + padding) or 0)
  local total_h, _, collapse_anim = UIUtils.GetCollapsiblePanelHeight(state, "hp_correction", full_total_h, 22)

  -- ── 2. Draw unified instrument container around the entire calibration block ──
  UIUtils.DrawInstrumentPanel(dl, draw_api, x, y, right, y + total_h, 6.0)
  UIUtils.DrawCollapsibleModuleLabel(ctx, dl, draw_api, x, y, "HP CORRECTION", "hp_correction", state, sf, sfs)

  -- ── 3. Draw adaptive header text links (ROOF / SONARWORKS / REALPHONES) ───
  local sf_to_use = sf
  local sfs_to_use = sfs or 10

  if sf_to_use then reaper.ImGui_PushFont(ctx, sf_to_use, sfs_to_use) end
  local header_items = BuildProviderHeaderLayout(ctx, x, right, sf_to_use, sfs_to_use)
  local text_y = UIUtils.HeaderTextY(ctx, y, "REALPHONES", sf_to_use, sfs_to_use)

  local col_roof  = (state.hp_cal_provider == "roof")       and (hp_anim.expanded and 0x5CFFB6CC or 0x5CFFB677) or 0x8C94A056
  local col_sonar = (state.hp_cal_provider == "sonarworks") and (hp_anim.expanded and 0x5CFFB6CC or 0x5CFFB677) or 0x8C94A056
  local col_real  = (state.hp_cal_provider == "realphones") and (hp_anim.expanded and 0x5CFFB6CC or 0x5CFFB677) or 0x8C94A056

  local header_colors = {
    roof = col_roof,
    sonarworks = col_sonar,
    realphones = col_real,
  }

  for _, item in ipairs(header_items) do
    draw_api.text(dl, item.x, text_y, header_colors[item.id] or 0x8C94A056, item.label)
  end

  if sf_to_use then reaper.ImGui_PopFont(ctx) end

  -- ── 4. Set up invisible buttons for clicking on header labels ─────────────
  local clicked = nil

  for _, item in ipairs(header_items) do
    reaper.ImGui_SetCursorScreenPos(ctx, item.x - 3, y + 1)
    if reaper.ImGui_InvisibleButton(ctx, "##hp_mode_" .. item.id, math.max(1.0, item.w + 6), 17) then
      clicked = item.id
    end
  end

  -- ── 5. Handle clicking on options ──────────────────────────────────────────
  if clicked then
    if hp_anim.showing_provider == clicked and hp_anim.expanded then
      -- Clicked active option while expanded: collapse
      hp_anim.expanded  = false
      hp_anim.last_time = nil
    else
      -- Switch to new provider or expand
      if hp_anim.showing_provider ~= clicked then
        hp_anim.showing_provider = clicked
        hp_anim.t                = 0.0
        hp_anim.last_time        = nil
      end
      hp_anim.expanded  = true
      hp_anim.last_time = nil
      HeadphoneCalibrationManager.SetProvider(state, clicked)
    end
  end

  -- ── 6. Draw animated body inside the container (indented by 8px left/right) ─
  local body_clip = UIUtils.BeginAnimatedPanelBodyClip(ctx, x, y, right, y + total_h, collapse_anim)
  if not body_clip then
    reaper.ImGui_SetCursorScreenPos(ctx, x, y)
    draw_api.dummy(ctx, width, total_h)
    return
  end

  if body_h > 0 then
    local body_y = y + HEADER_H + GAP
    local body_x = x + 8
    local body_w = width - 16
    local final_body_h = DrawProviderBody(ctx, state, dl, draw_api, body_x, body_y, body_w, body_h, sf, sfs)
  end

  -- Advance cursor past the container
  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  UIUtils.EndAnimatedPanelBodyClip(ctx, body_clip)
  draw_api.dummy(ctx, width, total_h)
end

return HeadphoneCalPanel
