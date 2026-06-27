local ReferencePanel = {}
local UIUtils = require("UIUtils")
local UIKit = require("UIKit")
local ReferenceWaveform = require("ReferenceWaveform")

local ffi_ok, ffi = pcall(require, "ffi")

local REF_PARAM_MODE = 0
local REF_PARAM_GAIN_DB = 1
local REF_PARAM_OFFSET = 2
local REF_PARAM_SYNC = 3
local REF_PARAM_MONO = 4

local cyrillic_map = {
  ["А"]="A", ["Б"]="B", ["В"]="V", ["Г"]="G", ["Д"]="D", ["Е"]="E", ["Ё"]="Yo", ["Ж"]="Zh", ["З"]="Z", ["И"]="I", ["Й"]="Y", ["К"]="K", ["Л"]="L", ["М"]="M", ["Н"]="N", ["О"]="O", ["П"]="P", ["Р"]="R", ["С"]="S", ["Т"]="T", ["У"]="U", ["Ф"]="F", ["Х"]="Kh", ["Ц"]="Ts", ["Ч"]="Ch", ["Ш"]="Sh", ["Щ"]="Shch", ["Ъ"]="", ["Ы"]="Y", ["Ь"]="", ["Э"]="E", ["Ю"]="Yu", ["Я"]="Ya",
  ["а"]="a", ["б"]="b", ["в"]="v", ["г"]="g", ["д"]="d", ["е"]="e", ["ё"]="yo", ["ж"]="zh", ["з"]="z", ["и"]="i", ["й"]="y", ["к"]="k", ["л"]="l", ["м"]="m", ["н"]="n", ["о"]="o", ["п"]="p", ["р"]="r", ["с"]="s", ["т"]="t", ["у"]="u", ["ф"]="f", ["х"]="kh", ["ц"]="ts", ["ч"]="ch", ["ш"]="sh", ["щ"]="shch", ["ъ"]="", ["ы"]="y", ["ь"]="", ["э"]="e", ["ю"]="yu", ["я"]="ya"
}

local function Transliterate(str)
  local result = {}
  local i = 1
  while i <= #str do
    local b = string.byte(str, i)
    if b >= 0xC0 and b <= 0xDF then
      local char = string.sub(str, i, i + 1)
      local repl = cyrillic_map[char] or char
      result[#result + 1] = repl
      i = i + 2
    else
      local char = string.sub(str, i, i)
      result[#result + 1] = char
      i = i + 1
    end
  end
  return table.concat(result)
end

local function RenameFileWindowsFFI(src, dst)
  if not ffi_ok then return false end
  
  local win_src = src:gsub("/", "\\")
  local win_dst = dst:gsub("/", "\\")
  
  local kernel32 = nil
  local ok_load = pcall(function()
    kernel32 = ffi.load("kernel32")
  end)
  if not ok_load or not kernel32 then
    kernel32 = ffi.C
  end
  
  pcall(function()
    ffi.cdef[[
      int MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags, const char* lpMultiByteStr, int cbMultiByte, unsigned short* lpWideCharStr, int cchWideChar);
      int MoveFileW(const unsigned short* lpExistingFileName, const unsigned short* lpNewFileName);
    ]]
  end)
  
  local CP_UTF8 = 65001
  
  local function to_utf16(str)
    local len = kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, nil, 0)
    if len <= 0 then return nil end
    local buf = ffi.new("unsigned short[?]", len)
    kernel32.MultiByteToWideChar(CP_UTF8, 0, str, -1, buf, len)
    return buf
  end
  
  local success = false
  pcall(function()
    local w_src = to_utf16(win_src)
    local w_dst = to_utf16(win_dst)
    if w_src and w_dst then
      success = (kernel32.MoveFileW(w_src, w_dst) ~= 0)
    end
  end)
  
  return success
end

local function RenameFileWindows(src, dst)
  -- 1. Try LuaJIT FFI first (extremely fast)
  local success = RenameFileWindowsFFI(src, dst)
  if success then return true end
  
  -- 2. Fallback to PowerShell via ExecProcess
  if reaper.ExecProcess then
    local esc_src = src:gsub("'", "''"):gsub("/", "\\")
    local esc_dst = dst:gsub("'", "''"):gsub("/", "\\")
    local cmd = 'powershell -NoProfile -Command "Move-Item -LiteralPath \'' .. esc_src .. '\' -Destination \'' .. esc_dst .. '\' -Force"'
    reaper.ExecProcess(cmd, 1500)
    return true
  end
  
  return false
end

local function SafeString(value, fallback)
  if type(value) == "string" and value ~= "" then
    return value
  end

  return fallback or ""
end

local function Ellipsize(ctx, text, max_width)
  text = SafeString(text, "")
  if UIUtils.TextWidth(ctx, text) <= max_width then
    return text
  end

  local suffix = "..."
  local lo, hi = 1, #text
  local best = suffix
  while lo <= hi do
    local mid = math.floor((lo + hi) * 0.5)
    local candidate = text:sub(1, mid) .. suffix
    if UIUtils.TextWidth(ctx, candidate) <= max_width then
      best = candidate
      lo = mid + 1
    else
      hi = mid - 1
    end
  end

  return best
end

local function TextSize(ctx, text, fallback_height)
  if reaper.ImGui_CalcTextSize then
    local w, h = reaper.ImGui_CalcTextSize(ctx, text)
    return w or UIUtils.TextWidth(ctx, text), h or fallback_height or 14
  end

  return UIUtils.TextWidth(ctx, text), fallback_height or 14
end

local function DrawTinyTextButton(ctx, draw_list, draw_api, id, label, x, y, w, h, active, small_font, small_font_size)
  w = math.max(1.0, w or 1.0)
  h = math.max(1.0, h or 1.0)
  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  local clicked = reaper.ImGui_InvisibleButton(ctx, id, w, h)
  local hovered = reaper.ImGui_IsItemHovered(ctx)

  local bg = active and 0x163B2AFF or (hovered and 0x1B1F25FF or 0x12151AFF)
  local border = active and 0x5CFFB666 or (hovered and 0x5CFFB633 or 0xFFFFFF16)
  local text = active and 0x5CFFB6FF or 0xD6DAE1E8
  draw_api.rect_filled(draw_list, x, y, x + w, y + h, bg, 4.0)
  draw_api.rect(draw_list, x, y, x + w, y + h, border, 4.0, nil, 1.0)

  UIUtils.DrawButtonTextInRect(ctx, draw_list, x, y, w, h, label, text, small_font, small_font_size)

  return clicked
end

local function Approach(current, target, speed)
  current = current or 0
  local dt = 1.0 / 30.0
  if reaper.time_precise then
    local now = reaper.time_precise()
    dt = math.min(0.05, math.max(0.001, now - (ReferencePanel._last_anim_time or now)))
    ReferencePanel._last_anim_time = now
  end

  local k = 1.0 - math.exp(-speed * dt)
  return current + (target - current) * k
end

local function UpdateRefExpandAnimation(state)
  local target = state.ref_expanded and 1.0 or 0.0
  local now = reaper.time_precise and reaper.time_precise() or 0
  local last = state.ref_expand_anim_time or now
  local dt = math.max(0.001, math.min(0.05, now - last))
  state.ref_expand_anim_time = now
  state.ref_expand_anim = state.ref_expand_anim or target

  local speed = target > state.ref_expand_anim and 3.8 or 4.8
  state.ref_expand_anim = state.ref_expand_anim + (target - state.ref_expand_anim) * (1.0 - math.exp(-speed * dt))

  if math.abs(state.ref_expand_anim - target) < 0.002 then
    state.ref_expand_anim = target
  end

  local t = math.max(0.0, math.min(1.0, state.ref_expand_anim))
  return 1.0 - ((1.0 - t) * (1.0 - t) * (1.0 - t))
end

local function FocusReferenceInScroll(ctx, state)
  if not state.ref_scroll_focus_until then
    return
  end

  local now = reaper.time_precise and reaper.time_precise() or 0
  if now <= state.ref_scroll_focus_until and reaper.ImGui_SetScrollHereY then
    reaper.ImGui_SetScrollHereY(ctx, 0.72)
  elseif now > state.ref_scroll_focus_until then
    state.ref_scroll_focus_until = nil
  end
end

-- Hidden tracks logic completely removed. Audio engine now runs entirely in JSFX memory.

local function SetReferencePlaybackMode(state, player_fx_idx, master, mode)
  state.ref_playback_mode = mode

  if mode == "free" then
    reaper.TrackFX_SetParam(master, player_fx_idx, REF_PARAM_SYNC, 0)
    reaper.gmem_write(10303, 0)
  else
    reaper.TrackFX_SetParam(master, player_fx_idx, REF_PARAM_SYNC, 1)
    reaper.gmem_write(10302, 0)
    reaper.gmem_write(10303, 1)
  end
end

local function ForceReferenceSync(state, player_fx_idx, master)
  state.ref_playback_mode = "sync"
  state.ref_loop_enabled = false
  state.ref_loop_drag_start = nil
  reaper.TrackFX_SetParam(master, player_fx_idx, REF_PARAM_SYNC, 1)
  reaper.gmem_write(10302, 0)
  reaper.gmem_write(10303, 1)
  reaper.gmem_write(10307, 0)
end

local function EnsureReferenceSlots(state)
  state.ref_slots = state.ref_slots or {}
  for index = 1, 10 do
    state.ref_slots[index] = state.ref_slots[index] or { name = "No reference track", path = nil, preview = nil }
  end
  state.ref_active_slot = math.max(1, math.min(10, state.ref_active_slot or 1))
end

local function SendReferencePath(path)
  reaper.gmem_attach("RCC_ANALYZER_TAP")
  if not path or path == "" then
    reaper.gmem_write(10000, 0)
    reaper.gmem_write(10100, reaper.time_precise())
    return
  end

  reaper.gmem_write(10000, #path)
  for i = 1, #path do
    reaper.gmem_write(10000 + i, string.byte(path, i))
  end
  reaper.gmem_write(10100, reaper.time_precise())
end

local function CleanupPcmSource(state)
  if state.ref_pcm_source and reaper.PCM_Source_Destroy then
    pcall(reaper.PCM_Source_Destroy, state.ref_pcm_source)
  end
  state.ref_pcm_source = nil
  state.ref_pcm_source_path = nil
end

local function ClearReferenceSlot(state, index)
  if not state.ref_slots or not state.ref_slots[index] then
    return
  end

  state.ref_slots[index] = { name = "No reference track", path = nil, preview = nil }
  if state.ref_active_slot == index then
    state.ref_loaded_path = nil
    state.ref_loudness = -14.0
    CleanupPcmSource(state)
    SendReferencePath(nil)
  end
end

local function ClearAllReferenceSlots(state)
  state.ref_slots = {}
  for index = 1, 10 do
    state.ref_slots[index] = { name = "No reference track", path = nil, preview = nil }
  end
  state.ref_active_slot = 1
  state.ref_loaded_path = nil
  state.ref_loudness = -14.0
  CleanupPcmSource(state)
end

local function SwitchReferenceSlot(state, slot_index, player_fx_idx, master)
  local slot = state.ref_slots[slot_index]
  if not slot or not slot.path then
    state.ref_active_slot = slot_index
    state.ref_loaded_path = nil
    CleanupPcmSource(state)
    SendReferencePath(nil)
    return
  end

  state.ref_active_slot = slot_index
  state.ref_loaded_path = slot.path
  CleanupPcmSource(state)
  SendReferencePath(slot.path)
  if slot.preview and slot.preview.estimated_lufs then
    state.ref_loudness = slot.preview.estimated_lufs
  end
end

local function SendReferenceTransport(state, seek_norm, play)
  state.ref_transport_serial = (state.ref_transport_serial or 0) + 1
  state.ref_ui_play_norm = math.max(0.0, math.min(1.0, seek_norm or 0))
  state.ref_ui_play_time = reaper.time_precise and reaper.time_precise() or 0
  reaper.gmem_write(10300, state.ref_transport_serial)
  reaper.gmem_write(10301, state.ref_ui_play_norm)
  reaper.gmem_write(10302, play and 1 or 0)
  reaper.gmem_write(10303, 0)
end

local function DrawPlaybackModeSelector(ctx, state, draw_list, draw_api, player_fx_idx, master, x, y, right, small_font, small_font_size)
  if not draw_api.text or not small_font then
    return
  end

  local adv_active = state.ref_expanded == true

  local easy_label = "EASY"
  local sync_label = "SYNC"
  local free_label = "FREE"
  local loop_label = "LOOP"
  local adv_label = "ADV"

  local easy_w = UIUtils.TextWidth(ctx, easy_label)
  local free_w = UIUtils.TextWidth(ctx, free_label)
  local sync_w = UIUtils.TextWidth(ctx, sync_label)
  local loop_w = UIUtils.TextWidth(ctx, loop_label)
  local adv_w = UIUtils.TextWidth(ctx, adv_label)

  local free_x = right - free_w - 9
  local sync_x = free_x - sync_w - 14
  local loop_x = sync_x - loop_w - 14
  local easy_x = adv_active and (loop_x - easy_w - 14) or (right - easy_w - 9)
  local adv_x = easy_x - adv_w - 14
  local text_y = UIUtils.HeaderTextY(ctx, y, sync_label, small_font, small_font_size)

  reaper.ImGui_PushFont(ctx, small_font, small_font_size)
  if adv_active then
    draw_api.text(draw_list, easy_x, text_y, 0x8C94A077, easy_label)
    draw_api.text(draw_list, loop_x, text_y, state.ref_loop_enabled and 0x5CFFB6CC or 0x8C94A056, loop_label)
    draw_api.text(draw_list, sync_x, text_y, state.ref_playback_mode ~= "free" and 0x5CFFB6CC or 0x8C94A056, sync_label)
    draw_api.text(draw_list, free_x, text_y, state.ref_playback_mode == "free" and 0x5CFFB6CC or 0x8C94A056, free_label)
  else
    draw_api.text(draw_list, adv_x, text_y, 0x8C94A077, adv_label)
    draw_api.text(draw_list, easy_x, text_y, 0x5CFFB6CC, easy_label)
  end
  reaper.ImGui_PopFont(ctx)

  if adv_active then
    reaper.ImGui_SetCursorScreenPos(ctx, loop_x - 3, y + 1)
    if reaper.ImGui_InvisibleButton(ctx, "##ref_mode_loop", loop_w + 6, 17) then
      state.ref_loop_enabled = not state.ref_loop_enabled
      reaper.gmem_write(10307, state.ref_loop_enabled and 1 or 0)
    end

    reaper.ImGui_SetCursorScreenPos(ctx, sync_x - 3, y + 1)
    if reaper.ImGui_InvisibleButton(ctx, "##ref_mode_sync", sync_w + 6, 17) then
      SetReferencePlaybackMode(state, player_fx_idx, master, "sync")
    end

    reaper.ImGui_SetCursorScreenPos(ctx, free_x - 3, y + 1)
    if reaper.ImGui_InvisibleButton(ctx, "##ref_mode_free", free_w + 6, 17) then
      SetReferencePlaybackMode(state, player_fx_idx, master, "free")
    end

    reaper.ImGui_SetCursorScreenPos(ctx, easy_x - 3, y + 1)
    if reaper.ImGui_InvisibleButton(ctx, "##ref_mode_easy", easy_w + 8, 17) then
      state.ref_expanded = false
      ForceReferenceSync(state, player_fx_idx, master)
    end
  else
    reaper.ImGui_SetCursorScreenPos(ctx, adv_x - 3, y + 1)
    if reaper.ImGui_InvisibleButton(ctx, "##ref_mode_adv", adv_w + 6, 17) then
      state.ref_expanded = true
      state.ref_scroll_focus_until = (reaper.time_precise and reaper.time_precise() or 0) + 0.45
    end
  end
end

local function DrawReferenceSlots(ctx, state, x, y, width, small_font, small_font_size, player_fx_idx, master, adv_visible)
  local gap = 3
  local button_w = math.floor((width - gap * 9) / 10)
  local button_h = 16
  if small_font then reaper.ImGui_PushFont(ctx, small_font, small_font_size) end
  
  local draw_api = UIUtils.GetDrawApi()
  local draw_list = draw_api and draw_api.get_draw_list(ctx)

  for slot_index = 1, 10 do
    reaper.ImGui_SetCursorScreenPos(ctx, x + (slot_index - 1) * (button_w + gap), y)
    local btn_x, btn_y = reaper.ImGui_GetCursorScreenPos(ctx)
    local active = state.ref_active_slot == slot_index
    
    if UIUtils.PremiumMonitorButton(ctx, tostring(slot_index) .. "##ref_slot_" .. slot_index, button_w, button_h, active) then
      SwitchReferenceSlot(state, slot_index, player_fx_idx, master)
    end
    
    if reaper.ImGui_IsItemClicked(ctx, 1) then
      state.ref_slot_menu_index = slot_index
      reaper.ImGui_OpenPopup(ctx, "##ref_slot_context")
    end
    
    -- Draw premium LED status dots BELOW slot buttons (only in ADV mode)
    if adv_visible and draw_api and draw_list then
      local slot = state.ref_slots[slot_index]
      local has_file = slot and slot.path and slot.path ~= ""
      
      local led_x = btn_x + button_w * 0.5
      local led_y = btn_y + button_h + 7.5 -- Centered right below the button
      
      if active then
        -- Smooth, organic breathing pulse animation for the active slot LED dot
        local time = reaper.time_precise and reaper.time_precise() or 0
        local pulse = 0.5 + 0.5 * math.sin(time * 5.5) -- smooth sinusoidal pulse
        
        local glow_radius = 2.0 + 2.5 * pulse
        local glow_alpha = math.floor(0x22 + 0x55 * pulse)
        local glow_color = 0x5CFFB600 | glow_alpha
        
        draw_api.circle_filled(draw_list, led_x, led_y, glow_radius, glow_color)
        draw_api.circle_filled(draw_list, led_x, led_y, 1.5, 0x5CFFB6FF)
        draw_api.circle_filled(draw_list, led_x, led_y, 0.7, 0xFFFFFFFF) -- Ultra-bright core
      elseif has_file then
        -- Steady soft emerald green dot for loaded slots
        draw_api.circle_filled(draw_list, led_x, led_y, 1.2, 0x32A852BB)
      else
        -- Dim grey dot for empty slots
        draw_api.circle_filled(draw_list, led_x, led_y, 1.0, 0x2D303588)
      end
    end
  end

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x111216FA)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x163B2AFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x1D5138FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x10291EFF)
  if reaper.ImGui_BeginPopup(ctx, "##ref_slot_context") then
    local index = state.ref_slot_menu_index or state.ref_active_slot or 1
    if reaper.ImGui_Selectable(ctx, "Clear slot##ref_clear_slot") then
      ClearReferenceSlot(state, index)
    end
    if reaper.ImGui_Selectable(ctx, "Clear all slots##ref_clear_all_slots") then
      ClearAllReferenceSlots(state)
    end
    reaper.ImGui_EndPopup(ctx)
  end
  reaper.ImGui_PopStyleColor(ctx, 4)
  if small_font then reaper.ImGui_PopFont(ctx) end
end

local function GetWaveformPeaksDynamic(state, path, view_start, view_end, num_points)
  if not path or path == "" then return nil, nil end
  if not reaper.PCM_Source_CreateFromFile or not reaper.PCM_Source_GetPeaks or not reaper.new_array then
    return nil, nil
  end

  -- Cache the PCM Source to avoid heavy disk/file overhead on every draw call
  local source = state.ref_pcm_source
  if not source or state.ref_pcm_source_path ~= path then
    if source and reaper.PCM_Source_Destroy then
      pcall(reaper.PCM_Source_Destroy, source)
    end
    source = reaper.PCM_Source_CreateFromFile(path)
    state.ref_pcm_source = source
    state.ref_pcm_source_path = path
  end

  if not source then return nil, nil end

  local ok, length = pcall(reaper.GetMediaSourceLength, source)
  if not ok or not length or length <= 0 then
    return nil, nil
  end

  local view_span = view_end - view_start
  local start_time = view_start * length
  local view_duration = view_span * length

  local channels = 2
  local buffer = reaper.new_array(num_points * channels * 2)
  local peakrate = num_points / math.max(0.0001, view_duration)
  
  local peak_ok = pcall(reaper.PCM_Source_GetPeaks, source, peakrate, start_time, channels, num_points, 0, buffer)
  if not peak_ok then
    return nil, nil
  end

  local values = buffer.table and buffer.table() or {}
  local points = {}
  local min_offset = num_points * channels
  
  for i = 1, num_points do
    local idx = (i - 1) * channels
    local l_max = values[idx + 1] or 0
    local r_max = values[idx + 2] or l_max
    local l_min = values[min_offset + idx + 1] or -l_max
    local r_min = values[min_offset + idx + 2] or -r_max
    local max_v = (l_max + r_max) * 0.5
    local min_v = (l_min + r_min) * 0.5

    points[#points + 1] = {
      min = math.max(-1.0, math.min(1.0, min_v)),
      max = math.max(-1.0, math.min(1.0, max_v)),
    }
  end

  return points, length
end

local function DrawReferenceWaveform(ctx, state, draw_list, draw_api, preview, player_fx_idx, master, x, y, right, bottom, small_font, small_font_size)
  if not x or not y or not right or not bottom then
    return
  end

  draw_api.rect_filled(draw_list, x, y, right, bottom, 0x0B0D11F2, 4.0)
  draw_api.rect(draw_list, x, y, right, bottom, 0x252830B8, 4.0, nil, 1.0)

  local width = math.max(1, right - x)
  local height = math.max(1, bottom - y)
  local center_y = y + height * 0.5
  local plot_left = x + 5
  local plot_right = right - 5
  local plot_w = math.max(1, plot_right - plot_left)
  local is_ref_active = state.ref_mode == true
  local wave_alpha_scale = is_ref_active and 1.0 or 0.48

  -- Initialize view windows for zoom
  state.ref_view_start = state.ref_view_start or 0.0
  state.ref_view_end = state.ref_view_end or 1.0
  local view_start = state.ref_view_start
  local view_end = state.ref_view_end
  local view_span = view_end - view_start

  local total_duration = preview and preview.duration or 1.0
  local view_duration = view_span * total_duration

  -- Draw zero line
  draw_api.line(draw_list, plot_left, center_y, plot_right, center_y, 0x2849368A, 1)
  
  -- Render приглушенную фоновую сетку (деление на 4 четверти)
  for i = 1, 3 do
    local gx = plot_left + plot_w * i * 0.25
    draw_api.line(draw_list, gx, y + 5, gx, bottom - 5, 0x1D20261A, 0.8)
  end

  -- Determine if we are zoomed in extremely close (< 0.22 seconds visible)
  local is_extreme_zoom = (view_duration < 0.22) and (state.ref_loaded_path and state.ref_loaded_path ~= "")
  local dyn_points = nil

  if is_extreme_zoom then
    local num_points = math.max(256, math.min(1200, math.floor(plot_w * 1.2)))
    dyn_points = GetWaveformPeaksDynamic(state, state.ref_loaded_path, view_start, view_end, num_points)
  end

  if is_extreme_zoom and dyn_points then
    -- Mode A: Dynamic Sample-Accurate Sine Wave mode (displays beautiful connected individual samples)
    local count = #dyn_points
    local amp = height * 0.34
    local last_px, last_py = nil, nil
    for i = 1, count do
      local px = plot_left + ((i - 1) / (count - 1)) * plot_w
      local pt = dyn_points[i]
      
      -- Under extreme zoom, max value holds the precise instantaneous sample amplitude
      local val_y = center_y - (pt.max or 0) * amp
      
      if last_px then
        -- Render premium connected sine wave line
        draw_api.line(draw_list, last_px, last_py, px, val_y, 0x5CFFB6DF, 1.6)
      end
      
      last_px = px
      last_py = val_y
    end
    
    -- Overlay elegant glowing LED jewel points on top of the sine curve
    local step_x = plot_w / count
    if step_x > 3.2 then
      for i = 1, count do
        local px = plot_left + ((i - 1) / (count - 1)) * plot_w
        local pt = dyn_points[i]
        local val_y = center_y - (pt.max or 0) * amp
        
        draw_api.circle_filled(draw_list, px, val_y, 2.5, 0x5CFFB6FF)
        draw_api.circle_filled(draw_list, px, val_y, 1.0, 0xFFFFFFFF)
      end
    end
  elseif preview and preview.points then
    -- Mode B: Premium Multi-Color Peak Waveform (static 5000 points with rock-solid high-speed lerp)
    local count = #preview.points
    local amp = height * 0.34
    local last_px = nil
    local last_top = nil
    local last_bot = nil
    
    local steps = math.floor(plot_w)
    for i = 1, steps do
      local t_norm = (i - 1) / math.max(1, steps - 1)
      local t_track = view_start + t_norm * view_span
      
      local real_idx = t_track * (count - 1) + 1
      local idx_low = math.max(1, math.min(count, math.floor(real_idx)))
      local idx_high = math.max(1, math.min(count, idx_low + 1))
      local frac = real_idx - idx_low

      local p_low = preview.points[idx_low]
      local p_high = preview.points[idx_high] or p_low

      local pt_min = p_low.min + (p_high.min - p_low.min) * frac
      local pt_max = p_low.max + (p_high.max - p_low.max) * frac

      local px = plot_left + t_norm * plot_w
      local min_y = center_y - math.max(-1, math.min(1, pt_min or 0)) * amp
      local max_y = center_y - math.max(-1, math.min(1, pt_max or 0)) * amp
      local top_y = math.min(min_y, max_y)
      local bot_y = math.max(min_y, max_y)

      if math.abs(bot_y - top_y) > 0.4 then
        local body_alpha = math.floor((22 + math.min(68, math.abs(bot_y - top_y) * 2.0)) * wave_alpha_scale)
        local col_top = (0x1A634800 | body_alpha)
        local col_center = (0x5CFFB600 | body_alpha)
        -- Draw top half gradient
        reaper.ImGui_DrawList_AddRectFilledMultiColor(draw_list, px, top_y, px + 1.2, center_y, col_top, col_top, col_center, col_center)
        -- Draw bottom half gradient
        reaper.ImGui_DrawList_AddRectFilledMultiColor(draw_list, px, center_y, px + 1.2, bot_y, col_center, col_center, col_top, col_top)
      end

      if last_px then
        local edge_alpha = math.floor(140 * wave_alpha_scale)
        draw_api.line(draw_list, last_px, last_top, px, top_y, 0x5CFFB600 | edge_alpha, 1.0)
        draw_api.line(draw_list, last_px, last_bot, px, bot_y, 0x5CFFB600 | edge_alpha, 1.0)
      end

      last_px = px
      last_top = top_y
      last_bot = bot_y
    end
  elseif draw_api.text and small_font then
    reaper.ImGui_PushFont(ctx, small_font, small_font_size)
    draw_api.text(draw_list, x + 8, y + 8, 0x767D8AFF, "WAV preview unavailable")
    reaper.ImGui_PopFont(ctx)
  end

  reaper.gmem_attach("RCC_ANALYZER_TAP")
  if state.ref_loop_enabled and state.ref_loop_start and state.ref_loop_end and state.ref_loop_end > state.ref_loop_start then
    local loop_screen_start = (state.ref_loop_start - view_start) / view_span
    local loop_screen_end = (state.ref_loop_end - view_start) / view_span

    local draw_x1 = plot_left + plot_w * math.max(0.0, math.min(1.0, loop_screen_start))
    local draw_x2 = plot_left + plot_w * math.max(0.0, math.min(1.0, loop_screen_end))
    if draw_x2 > draw_x1 then
      -- 1. Elegant, clean and extremely soft solid loop overlay to avoid any patchy gradients
      draw_api.rect_filled(draw_list, draw_x1, y + 4, draw_x2, bottom - 4, 0x5CFFB60D)

      -- Soft border for a delicate glass container feel
      draw_api.rect(draw_list, draw_x1, y + 4, draw_x2, bottom - 4, 0x5CFFB614, 0.0, nil, 1.0)

      -- 2. Thin neon boundaries and elegant round handles with glowing white core
      if loop_screen_start >= 0.0 and loop_screen_start <= 1.0 then
        draw_api.line(draw_list, draw_x1, y + 4, draw_x1, bottom - 4, 0x5CFFB688, 1.0)
        
        draw_api.circle_filled(draw_list, draw_x1, center_y, 5.0, 0x5CFFB61F)
        draw_api.circle_filled(draw_list, draw_x1, center_y, 3.2, 0x5CFFB6FF)
        draw_api.circle_filled(draw_list, draw_x1, center_y, 1.2, 0xFFFFFFFF)
      end
      if loop_screen_end >= 0.0 and loop_screen_end <= 1.0 then
        draw_api.line(draw_list, draw_x2, y + 4, draw_x2, bottom - 4, 0x5CFFB688, 1.0)
        
        draw_api.circle_filled(draw_list, draw_x2, center_y, 5.0, 0x5CFFB61F)
        draw_api.circle_filled(draw_list, draw_x2, center_y, 3.2, 0x5CFFB6FF)
        draw_api.circle_filled(draw_list, draw_x2, center_y, 1.2, 0xFFFFFFFF)
      end
    end
  end

  local js_play_norm = math.max(0.0, math.min(1.0, reaper.gmem_read(10304) or 0))
  local free_playing = (reaper.gmem_read(10306) or 0) >= 0.5
  local play_norm = js_play_norm
  if state.ref_playback_mode == "free" and (total_duration or (preview and preview.duration)) and (total_duration or preview.duration) > 0 then
    local duration = (total_duration or preview.duration)
    local now = reaper.time_precise and reaper.time_precise() or 0
    local ui_norm = state.ref_ui_play_norm
    local last_time = state.ref_ui_play_time
    if free_playing and state.ref_mode then
      if not ui_norm or math.abs((ui_norm or 0) - js_play_norm) > 0.05 then
        ui_norm = js_play_norm
      end
      if last_time then
        local next_norm = ui_norm + math.max(0, now - last_time) / duration
        if state.ref_loop_enabled and state.ref_loop_start and state.ref_loop_end and state.ref_loop_end > state.ref_loop_start then
          local loop_start = math.max(0.0, math.min(1.0, state.ref_loop_start))
          local loop_end = math.max(loop_start + 0.001, math.min(1.0, state.ref_loop_end))
          local loop_len = loop_end - loop_start
          next_norm = loop_start + ((next_norm - loop_start) % loop_len)
        else
          next_norm = math.min(1.0, next_norm)
        end
        ui_norm = next_norm
      end
      state.ref_ui_play_norm = ui_norm
      state.ref_ui_play_time = now
      play_norm = math.max(0.0, math.min(1.0, ui_norm))
    else
      state.ref_ui_play_norm = js_play_norm
      state.ref_ui_play_time = now
    end
  else
    state.ref_ui_play_norm = js_play_norm
    state.ref_ui_play_time = reaper.time_precise and reaper.time_precise() or 0
  end

  local play_screen_norm = (play_norm - view_start) / view_span
  if play_screen_norm >= 0.0 and play_screen_norm <= 1.0 then
    local play_x = plot_left + plot_w * play_screen_norm
    
    -- 3-layer glowing neon playhead
    draw_api.line(draw_list, play_x, y + 4, play_x, bottom - 4, 0x5CFFB618, 5.0) -- Outer glow
    draw_api.line(draw_list, play_x, y + 4, play_x, bottom - 4, 0x5CFFB650, 3.0) -- Inner glow
    draw_api.line(draw_list, play_x, y + 4, play_x, bottom - 4, 0xEFFFFFFF, 1.2) -- Core white center
    
    -- Glowing LED handle at the top of the playhead
    draw_api.circle_filled(draw_list, play_x, y + 7, 5.0, 0x5CFFB644)
    draw_api.circle_filled(draw_list, play_x, y + 7, 4.0, 0x5CFFB6FF)
    draw_api.circle_filled(draw_list, play_x, y + 7, 2.0, 0xFFFFFFFF)
  end

  local clicked, active, hovered = false, false, false
  if width > 0.001 and height > 0.001 then
    local active_w = math.max(1.0, width)
    local active_h = math.max(1.0, height)
    reaper.ImGui_SetCursorScreenPos(ctx, x, y)
    clicked = reaper.ImGui_InvisibleButton(ctx, "##ref_waveform_seek", active_w, active_h)
    active = reaper.ImGui_IsItemActive(ctx)
    hovered = reaper.ImGui_IsItemHovered(ctx)
  end
  local mouse_x = ({ reaper.ImGui_GetMousePos(ctx) })[1]
  local hover_norm = math.max(0.0, math.min(1.0, ((mouse_x or x) - plot_left) / plot_w))

  -- Handle Keyboard Modifier Detection safely
  local mods = reaper.ImGui_GetKeyMods and reaper.ImGui_GetKeyMods(ctx) or 0
  local ctrl_flag = (reaper.ImGui_Mod_Ctrl and reaper.ImGui_Mod_Ctrl()) or 
                    (reaper.ImGui_ModFlags_Ctrl and reaper.ImGui_ModFlags_Ctrl())
  local ctrl_pressed = false
  if ctrl_flag and ctrl_flag ~= 0 then
    ctrl_pressed = (mods & ctrl_flag) ~= 0
  else
    local left_ctrl = reaper.ImGui_Key_LeftCtrl and reaper.ImGui_Key_LeftCtrl() or 512
    local right_ctrl = reaper.ImGui_Key_RightCtrl and reaper.ImGui_Key_RightCtrl() or 513
    ctrl_pressed = reaper.ImGui_IsKeyDown and (reaper.ImGui_IsKeyDown(ctx, left_ctrl) or reaper.ImGui_IsKeyDown(ctx, right_ctrl))
  end

  -- Handle Zoom & Reset interactions when hovering
  if hovered then
    -- 1. Ctrl + Wheel Zoom (Highly compatible and extremely smooth via GetMouseWheel)
    if ctrl_pressed then
      local wheel = reaper.ImGui_GetMouseWheel and reaper.ImGui_GetMouseWheel(ctx) or 0
      if wheel ~= 0 then
        local zoom_factor = 1.12
        local new_span = view_span
        if wheel > 0 then
          new_span = view_span / zoom_factor
        else
          new_span = view_span * zoom_factor
        end
        new_span = math.max(0.0001, math.min(1.0, new_span)) -- limit zoom between 10000x (sample level) and 1x

        -- Anchor zoom strictly to mouse pointer
        local absolute_norm = view_start + hover_norm * view_span
        view_start = absolute_norm - hover_norm * new_span
        view_end = absolute_norm + (1.0 - hover_norm) * new_span

        -- Clamp boundaries
        if view_start < 0 then
          view_end = math.min(1.0, view_end - view_start)
          view_start = 0.0
        end
        if view_end > 1.0 then
          view_start = math.max(0.0, view_start - (view_end - 1.0))
          view_end = 1.0
        end

        state.ref_view_start = view_start
        state.ref_view_end = view_end
        view_span = view_end - view_start
      end
    end

    -- Double click to reset zoom to 100%
    if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
      state.ref_view_start = 0.0
      state.ref_view_end = 1.0
      view_start = 0.0
      view_end = 1.0
      view_span = 1.0
    end
  end

  -- 2. Ctrl + Drag Zoom (Left mouse button vertical dragging with Ctrl pressed)
  -- This is 100% bulletproof and works on ALL versions of ReaImGui!
  if active and ctrl_pressed then
    local drag_x, drag_y = 0, 0
    if reaper.ImGui_GetMouseDragDelta then
      drag_x, drag_y = reaper.ImGui_GetMouseDragDelta(ctx, 0)
    end
    if drag_y and math.abs(drag_y) > 2.0 then
      if reaper.ImGui_ResetMouseDragDelta then
        reaper.ImGui_ResetMouseDragDelta(ctx, 0)
      end
      
      -- drag_y is negative when moving UP (zoom in), positive when moving DOWN (zoom out)
      local zoom_factor = 1.0 + (drag_y * 0.015)
      local new_span = view_span * zoom_factor
      new_span = math.max(0.0001, math.min(1.0, new_span))

      -- Anchor zoom to the click coordinate
      local absolute_norm = view_start + hover_norm * view_span
      view_start = absolute_norm - hover_norm * new_span
      view_end = absolute_norm + (1.0 - hover_norm) * new_span

      -- Clamp boundaries
      if view_start < 0 then
        view_end = math.min(1.0, view_end - view_start)
        view_start = 0.0
      end
      if view_end > 1.0 then
        view_start = math.max(0.0, view_start - (view_end - 1.0))
        view_end = 1.0
      end

      state.ref_view_start = view_start
      state.ref_view_end = view_end
      view_span = view_end - view_start
    end
  end

  if hovered then
    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    local hover_x = plot_left + plot_w * hover_norm
    
    -- Floating hover line ruler indicator (soft neon мятный & translucent white)
    draw_api.line(draw_list, hover_x, y + 4, hover_x, bottom - 4, 0x5CFFB63C, 1.5)
    draw_api.line(draw_list, hover_x, y + 4, hover_x, bottom - 4, 0xFFFFFF55, 1.0)
  end

  if clicked or active then
    local seek_norm = view_start + hover_norm * view_span

    if state.ref_loop_enabled and active and reaper.ImGui_IsMouseDragging and reaper.ImGui_IsMouseDragging(ctx, 0, 4.0) then
      -- Loop selection (only if not zooming with Ctrl)
      if not ctrl_pressed then
        state.ref_loop_drag_start = state.ref_loop_drag_start or seek_norm
        state.ref_loop_start = math.min(state.ref_loop_drag_start, seek_norm)
        state.ref_loop_end = math.max(state.ref_loop_drag_start, seek_norm)
        reaper.gmem_write(10307, 1)
        reaper.gmem_write(10308, state.ref_loop_start)
        reaper.gmem_write(10309, state.ref_loop_end)
      end
    elseif not ctrl_pressed then
      -- Seek (only if not zooming with Ctrl)
      if clicked then
        local duration = (total_duration or (preview and preview.duration) or 0)
        if state.ref_playback_mode == "free" then
          reaper.TrackFX_SetParam(master, player_fx_idx, REF_PARAM_SYNC, 0)
          SendReferenceTransport(state, seek_norm, state.ref_mode == true)
        elseif duration > 0 then
          local seek_time = duration * seek_norm
          local time_offset = reaper.GetProjectTimeOffset and reaper.GetProjectTimeOffset(0, false) or 0.0
          reaper.SetEditCurPos(seek_time + time_offset, true, true)
          reaper.TrackFX_SetParam(master, player_fx_idx, REF_PARAM_SYNC, 1)
          reaper.gmem_write(10302, 0)
          reaper.gmem_write(10303, 1)
        end
      end
    end
  else
    state.ref_loop_drag_start = nil
  end

  if draw_api.text and small_font then
    reaper.ImGui_PushFont(ctx, small_font, small_font_size)
    local duration = (total_duration or (preview and preview.duration) or 0)
    local play_time = duration * play_norm
    local label = string.format("%d:%02d", math.floor(play_time / 60), math.floor(play_time % 60))
    
    local start_time = duration * view_start
    local start_label = string.format("%d:%02d", math.floor(start_time / 60), math.floor(start_time % 60))
    
    local end_time = duration * view_end
    local end_label = string.format("%d:%02d", math.floor(end_time / 60), math.floor(end_time % 60))

    draw_api.text(draw_list, x + 5, bottom - 12, 0x8C94A070, start_label)
    draw_api.text(draw_list, right - UIUtils.TextWidth(ctx, label) - 5, bottom - 12, 0x8C94A0AA, label)
    if hovered then
      local hover_time = duration * (view_start + hover_norm * view_span)
      local hover_label = string.format("%d:%02d", math.floor(hover_time / 60), math.floor(hover_time % 60))
      draw_api.text(draw_list, math.max(x + 5, math.min(right - UIUtils.TextWidth(ctx, hover_label) - 5, plot_left + plot_w * hover_norm - UIUtils.TextWidth(ctx, hover_label) * 0.5)), y + 5, 0xD7FBEACC, hover_label)
    elseif not is_ref_active then
      draw_api.text(draw_list, right - UIUtils.TextWidth(ctx, end_label) - 5, bottom - 12, 0x8C94A070, end_label)
    end
    reaper.ImGui_PopFont(ctx)
  end
end

function ReferencePanel.Draw(ctx, state, analyzer, manager, small_font, small_font_size)
  local width = reaper.ImGui_GetContentRegionAvail(ctx)
  local expand_anim = UpdateRefExpandAnimation(state)
  local full_height = math.floor(76 + (184 - 76) * expand_anim + 0.5)
  local height, _, collapse_anim = UIUtils.GetCollapsiblePanelHeight(state, "reference", full_height, 22)
  local adv_visible = expand_anim > 0.01
  local draw_api = UIUtils.GetDrawApi()

  if not draw_api then
    return
  end

  local draw_list = draw_api.get_draw_list(ctx)
  local x, y = draw_api.get_cursor_pos(ctx)
  local right = x + width
  local bottom = y + height

  local wave_y_top, wave_y_bottom, buttons_y
  if adv_visible then
    wave_y_top = y + 76 + 15 * expand_anim
    wave_y_bottom = math.min(y + 149, bottom - 32)
    buttons_y = y + 45 + 109 * expand_anim
  else
    buttons_y = y + 45
  end
  buttons_y = math.min(buttons_y, bottom - 28)

  UIUtils.DrawInstrumentPanel(draw_list, draw_api, x, y, right, bottom, 6.0)
  UIUtils.DrawCollapsibleModuleLabel(ctx, draw_list, draw_api, x, y, "REFERENCE", "reference", state, small_font, small_font_size)

  -- Ensure JSFX Player is installed on Monitoring FX chain
  local player_fx_idx = manager.EnsureRefPlayerInstalled(state)
  local master = reaper.GetMasterTrack(0)

  -- Background deferred slot switching orchestrator is bypassed for instant Metric AB direct switching

  if not player_fx_idx or not master then
    reaper.ImGui_SetCursorScreenPos(ctx, x + 10, y + 28)
    reaper.ImGui_Text(ctx, "Reference Player loading...")
    draw_api.dummy(ctx, width, height)
    return
  end

  -- Background playlist directory scanner
  local now_time = reaper.time_precise()
  if not state.ref_files or not state.ref_last_scan_time or (now_time - state.ref_last_scan_time > 1.5) then
    state.ref_last_scan_time = now_time
    state.ref_files = {}
    local path = reaper.GetResourcePath() .. "/Data/ref_tracks"
    reaper.RecursiveCreateDirectory(path, 0)
    
    local file_idx = 0
    while true do
      local filename = reaper.EnumerateFiles(path, file_idx)
      if not filename then break end
      
      -- Auto-rename Cyrillic names to ASCII-safe Latin equivalents on the fly
      if filename:match("[^\32-\126]") then
        local ascii_name = Transliterate(filename)
        ascii_name = ascii_name:gsub("[^\32-\126]", "_") -- Fallback strip remaining non-ASCII characters
        
        local src_full = path .. "/" .. filename
        local dst_full = path .. "/" .. ascii_name
        
        if RenameFileWindows(src_full, dst_full) then
          filename = ascii_name
        end
      end
      
      -- Filter to only list standard audio formats (.wav and .aiff/.aif)
      local ext = filename:match("^.+(%.[^%.]+)$")
      if ext then
        ext = ext:lower()
        if ext == ".wav" or ext == ".aiff" or ext == ".aif" then
          state.ref_files[#state.ref_files + 1] = {
            index = file_idx,
            name = filename,
          }
        end
      end
      file_idx = file_idx + 1
    end
  end

  -- Initialize slots and state parameters safely
  EnsureReferenceSlots(state)
  state.auto_gain_match = (state.auto_gain_match ~= nil) and state.auto_gain_match or false
  state.ref_mono = (state.ref_mono ~= nil) and state.ref_mono or false
  state.mix_loudness = state.mix_loudness or -18.0
  state.ref_loudness = state.ref_loudness or -14.0
  state.ref_gain_db_manual = state.ref_gain_db_manual or 0.0

  -- Dynamic states from JSFX parameters
  local curr_mode = reaper.TrackFX_GetParam(master, player_fx_idx, REF_PARAM_MODE)
  state.ref_mode = (curr_mode == 1.0)

  local curr_offset = reaper.TrackFX_GetParam(master, player_fx_idx, REF_PARAM_OFFSET)
  state.ref_offset = curr_offset or 0.0

  local curr_sync = reaper.TrackFX_GetParam(master, player_fx_idx, REF_PARAM_SYNC)
  state.ref_sync = (curr_sync == 1.0)
  state.ref_playback_mode = state.ref_playback_mode or "sync"
  state.ref_loop_enabled = state.ref_loop_enabled or false
  if not state.ref_expanded and (state.ref_playback_mode ~= "sync" or state.ref_loop_enabled) then
    ForceReferenceSync(state, player_fx_idx, master)
  end

  -- Resolve active reference track file path for the active slot
  local active_slot = state.ref_slots[state.ref_active_slot]
  local current_file_name = SafeString(active_slot.name, "No reference track")
  local current_file_path = active_slot.path

  -- Sync active slot path to JSFX player if it has changed
  if state.ref_loaded_path ~= current_file_path then
    state.ref_loaded_path = current_file_path
    SendReferencePath(current_file_path)
  end

  local time_offset = reaper.GetProjectTimeOffset and reaper.GetProjectTimeOffset(0, false) or 0.0
  reaper.gmem_write(10310, time_offset)

  -- Real-time LUFS calculations for Auto-Gain Match
  if analyzer and analyzer.active and analyzer.lufs_s and analyzer.lufs_s > -100 then
    if not state.ref_mode then
      state.mix_loudness = state.mix_loudness * 0.98 + analyzer.lufs_s * 0.02
    else
      state.ref_loudness = state.ref_loudness * 0.98 + analyzer.lufs_s * 0.02
    end
  end

  -- Apply manual volume slider + Dynamic Auto-Gain compensation
  local delta_gain = 0.0
  if state.auto_gain_match then
    delta_gain = state.mix_loudness - state.ref_loudness
    delta_gain = math.max(-30.0, math.min(12.0, delta_gain))
  end
  local total_ref_gain = state.ref_gain_db_manual + delta_gain
  reaper.TrackFX_SetParam(master, player_fx_idx, REF_PARAM_GAIN_DB, total_ref_gain)

  -- Sync active slot path to JSFX player is bypassed because we use native hidden tracks

  reaper.gmem_write(10303, state.ref_playback_mode == "free" and 0 or 1)
  reaper.gmem_write(10307, state.ref_loop_enabled and 1 or 0)
  reaper.gmem_write(10308, state.ref_loop_start or 0)
  reaper.gmem_write(10309, state.ref_loop_end or 1)
  
  -- JSFX exposes slider6 as the fifth actual FX parameter, so the zero-based
  -- parameter index is 4. Writing index 5 can hit a different host parameter.
  reaper.TrackFX_SetParam(master, player_fx_idx, REF_PARAM_MONO, state.ref_mono and 1.0 or 0.0)

  -- Draw Playback Mode (SYNC / FREE / LOOP) in header
  DrawPlaybackModeSelector(ctx, state, draw_list, draw_api, player_fx_idx, master, x, y, right, small_font, small_font_size)

  local body_clip = UIUtils.BeginAnimatedPanelBodyClip(ctx, x, y, right, bottom, collapse_anim)
  if not body_clip then
    reaper.ImGui_SetCursorScreenPos(ctx, x, y)
    draw_api.dummy(ctx, width, height)
    return
  end

  DrawReferenceSlots(ctx, state, x + 8, y + 21, width - 16, small_font, small_font_size, player_fx_idx, master, adv_visible)
  active_slot = state.ref_slots[state.ref_active_slot]
  current_file_name = SafeString(active_slot.name, "No reference track")
  current_file_path = active_slot.path

  -- Draw advanced controls only in ADV mode
  if adv_visible then
    -- Manual Volume Offset drag box (DragFloat)
    local row2_y = y + 45 + 19 * expand_anim
    local row_x = x + 8
    local row_w = width - 16
    local row_gap = 5
    local agm_w = 38
    local mon_w = 38
    if row2_y + 16 <= bottom - 4 then
      local vol_w = math.max(62, row_w - agm_w - mon_w - row_gap * 2)
      local vol_x = row_x
      reaper.ImGui_SetCursorScreenPos(ctx, vol_x, row2_y)
      reaper.ImGui_PushItemWidth(ctx, vol_w)
      reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 4.0)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x15171CFF)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x1E2229FF)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), 0x163B2AFF)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TextSelectedBg(), 0x5CFFB644)
      
      local vol_changed, vol_val = reaper.ImGui_DragDouble(ctx, "##ref_vol_slider", state.ref_gain_db_manual or 0.0, 0.1, -24.0, 12.0, "%.1fdB")
      if vol_changed then
        state.ref_gain_db_manual = math.max(-24.0, math.min(12.0, vol_val))
      end
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
        if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
          state.ref_gain_db_manual = 0.0
        end
      end
      
      reaper.ImGui_PopStyleColor(ctx, 4)
      reaper.ImGui_PopStyleVar(ctx, 1)
      reaper.ImGui_PopItemWidth(ctx)

      -- Toggles: AGM and MONO on the right
      reaper.ImGui_SetCursorScreenPos(ctx, row_x + vol_w + row_gap, row2_y)
      
      local agm_x = row_x + vol_w + row_gap
      if DrawTinyTextButton(ctx, draw_list, draw_api, "##ref_agm", "AGM", agm_x, row2_y, agm_w, 16, state.auto_gain_match, small_font, small_font_size) then
        state.auto_gain_match = not state.auto_gain_match
      end
      
      if DrawTinyTextButton(ctx, draw_list, draw_api, "##ref_mono", "MON", agm_x + agm_w + row_gap, row2_y, mon_w, 16, state.ref_mono, small_font, small_font_size) then
        state.ref_mono = not state.ref_mono
      end
    end
  end

  -- Row 2: MIX, REF, Dropdown combo, [O] Folder Button
  reaper.ImGui_SetCursorScreenPos(ctx, x + 8, buttons_y)

  local gap = 6
  local total_w = width - 16
  local row_h = 22
  local folder_btn_w = 22
  local remaining_w = total_w - folder_btn_w - gap * 3
  local btn_w = math.max(36, math.min(42, math.floor(remaining_w * 0.17)))
  local combo_w = remaining_w - btn_w * 2

  -- 1. MIX Button
  if UIUtils.PremiumMonitorButton(ctx, "MIX", btn_w, row_h, not state.ref_mode) then
    state.ref_mode = false
    reaper.gmem_write(10302, 0)
    reaper.gmem_write(10303, state.ref_playback_mode == "free" and 0 or 1)
    reaper.TrackFX_SetParam(master, player_fx_idx, REF_PARAM_MODE, 0)
    reaper.TrackFX_SetParam(master, player_fx_idx, REF_PARAM_SYNC, state.ref_playback_mode == "free" and 0 or 1)
  end

  -- 2. REF Button
  reaper.ImGui_SameLine(ctx, nil, gap)
  if UIUtils.PremiumMonitorButton(ctx, "REF", btn_w, row_h, state.ref_mode) then
    state.ref_mode = true
    reaper.TrackFX_SetParam(master, player_fx_idx, REF_PARAM_MODE, 1)
    if state.ref_playback_mode == "free" then
      reaper.TrackFX_SetParam(master, player_fx_idx, REF_PARAM_SYNC, 0)
      local start_norm = reaper.gmem_read(10304)
      if not start_norm or start_norm <= 0.0001 then
        start_norm = state.ref_ui_play_norm or 0
      end
      SendReferenceTransport(state, math.max(0.0, math.min(1.0, start_norm)), true)
    end
  end

  -- 3. Seamless custom playlist popup with real-time text filter.
  reaper.ImGui_SameLine(ctx, nil, gap)
  local combo_x, combo_y = draw_api.get_cursor_pos(ctx)
  local display_name = Ellipsize(ctx, current_file_name, combo_w - 28)
  local display_w, display_h = TextSize(ctx, display_name, small_font_size or 14)
  local display_x = combo_x + math.max(8, (combo_w - display_w) * 0.5)
  local active_combo_w = math.max(1.0, combo_w)
  local active_row_h = math.max(1.0, row_h)
  if reaper.ImGui_InvisibleButton(ctx, "##ref_playlist_popup_button", active_combo_w, active_row_h) then
    reaper.ImGui_OpenPopup(ctx, "##ref_playlist_popup")
  end
  local combo_hovered = reaper.ImGui_IsItemHovered(ctx)
  state.ref_combo_hover_anim = Approach(state.ref_combo_hover_anim, combo_hovered and 1.0 or 0.0, 10.0)
  local hover_a = state.ref_combo_hover_anim or 0.0
  local fill = hover_a > 0.01 and 0x171A1FFF or 0x15171CFF
  local border = hover_a > 0.01 and 0x5CFFB64A or 0xFFFFFF14
  local glow = math.floor(0x10 + hover_a * 0x30)
  local glow_color = 0x5CFFB600 + glow
  local text_y = combo_y + (row_h - display_h) * 0.5 - 0.5

  draw_api.rect_filled(draw_list, combo_x, combo_y, combo_x + combo_w, combo_y + row_h, fill, 4.0)
  draw_api.rect(draw_list, combo_x, combo_y, combo_x + combo_w, combo_y + row_h, border, 4.0, nil, 1.0)
  if hover_a > 0.02 then
    draw_api.rect(draw_list, combo_x + 1, combo_y + 1, combo_x + combo_w - 1, combo_y + row_h - 1, glow_color, 3.0, nil, 1.0)
  end
  draw_api.text(draw_list, display_x, text_y, current_file_name == "No reference track" and 0x767D8AFF or 0xD6DAE1FF, display_name)

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x111216FA)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x2A2C31FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x163B2AFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x1D5138FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x10291EFF)
  
  if reaper.ImGui_BeginPopup(ctx, "##ref_playlist_popup") then
    -- Real-time text search filter input at the top of the popup
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 4.0)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x1E2229FF)
    
    if reaper.ImGui_SetNextItemWidth then
      reaper.ImGui_SetNextItemWidth(ctx, combo_w - 12)
    end
    local search_changed, search_val = reaper.ImGui_InputText(ctx, "##ref_search_filter", state.ref_search_query or "", reaper.ImGui_InputTextFlags_AutoSelectAll and reaper.ImGui_InputTextFlags_AutoSelectAll() or 0)
    if search_changed then
      state.ref_search_query = search_val
    end
    
    reaper.ImGui_PopStyleColor(ctx, 1)
    reaper.ImGui_PopStyleVar(ctx, 1)
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)

    local query = (state.ref_search_query or ""):lower()
    local draw_count = 0
    
    if #(state.ref_files or {}) == 0 then
      reaper.ImGui_Text(ctx, "Empty (drop WAV/MP3 to ref_tracks/)")
    else
      for _, f in ipairs(state.ref_files or {}) do
        local file_name = SafeString(f.name, "Untitled reference")
        if query == "" or file_name:lower():find(query, 1, true) then
          draw_count = draw_count + 1
          local selected = (active_slot.name == f.name)
          if selected then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x5CFFB6FF)
          end
          if reaper.ImGui_Selectable(ctx, file_name .. "##ref_file_" .. tostring(f.index), selected) then
            active_slot.name = f.name
            local full_path = (reaper.GetResourcePath() .. "/Data/ref_tracks/" .. f.name):gsub("\\", "/")
            active_slot.path = full_path
            
             -- Estimate static loudness immediately
             active_slot.preview = ReferenceWaveform.Get(full_path, 5000)
             if active_slot.preview and active_slot.preview.estimated_lufs then
               state.ref_loudness = active_slot.preview.estimated_lufs
             end
             
             state.ref_loaded_path = full_path
             SendReferencePath(full_path)
           end
           if selected then
             reaper.ImGui_PopStyleColor(ctx, 1)
           end
         end
       end
     end
     
     if query ~= "" and draw_count == 0 then
       reaper.ImGui_Text(ctx, "No matches found")
     end
     
     if reaper.ImGui_EndPopup then
       reaper.ImGui_EndPopup(ctx)
     end
   end
   reaper.ImGui_PopStyleColor(ctx, 5)
 
   -- 4. Open Folder Button
   reaper.ImGui_SameLine(ctx, nil, gap)
   local folder_x, folder_y = draw_api.get_cursor_pos(ctx)
   local active_folder_btn_w = math.max(1.0, folder_btn_w)
   local active_row_h = math.max(1.0, row_h)
   local folder_clicked = reaper.ImGui_InvisibleButton(ctx, "##open_ref_dir_compact", active_folder_btn_w, active_row_h)
   local folder_hovered = reaper.ImGui_IsItemHovered(ctx)
   local folder_target = folder_hovered and 1.0 or 0.0
   state.ref_folder_hover_anim = (state.ref_folder_hover_anim or 0.0) + (folder_target - (state.ref_folder_hover_anim or 0.0)) * 0.18
   local folder_a = state.ref_folder_hover_anim or 0.0
   local folder_fill = folder_a > 0.01 and 0x171A1FFF or 0x15171CFF
   local folder_border = folder_a > 0.01 and 0x5CFFB644 or 0xFFFFFF14
   local folder_glow = 0x5CFFB600 + math.floor(0x0C + folder_a * 0x34)
   local folder_text_w, folder_text_h = TextSize(ctx, "O", small_font_size or 14)
   local folder_text_x = folder_x + (folder_btn_w - folder_text_w) * 0.5
   local folder_text_y = folder_y + (row_h - folder_text_h) * 0.5 - 0.5
 
   draw_api.rect_filled(draw_list, folder_x, folder_y, folder_x + folder_btn_w, folder_y + row_h, folder_fill, 4.0)
   draw_api.rect(draw_list, folder_x, folder_y, folder_x + folder_btn_w, folder_y + row_h, folder_border, 4.0, nil, 1.0)
   if folder_a > 0.02 then
     draw_api.rect(draw_list, folder_x + 1, folder_y + 1, folder_x + folder_btn_w - 1, folder_y + row_h - 1, folder_glow, 3.0, nil, 1.0)
   end
   draw_api.text(draw_list, folder_text_x, folder_text_y, folder_hovered and 0x5CFFB6FF or 0xD6DAE1FF, "O")
 
   if folder_clicked then
     local path = reaper.GetResourcePath() .. "/Data/ref_tracks"
     reaper.RecursiveCreateDirectory(path, 0)
     if reaper.CF_ShellExecute then
       reaper.CF_ShellExecute(path)
     else
       local os_name = reaper.GetOS()
       if os_name:find("Win") then
         os.execute('explorer "' .. path:gsub("/", "\\") .. '"')
       elseif os_name:find("OSX") then
         os.execute('open "' .. path .. '"')
       end
     end
   end
 
   -- Load and draw waveform preview
   local preview = nil
   if current_file_path then
     active_slot.preview = ReferenceWaveform.Get(current_file_path, 5000)
     preview = active_slot.preview
     
     -- Preload estimated static LUFS if it's default
     if preview and preview.estimated_lufs and (not state.ref_loudness or state.ref_loudness == -14.0) then
       state.ref_loudness = preview.estimated_lufs
     end
   end

  if adv_visible and wave_y_top and wave_y_bottom and wave_y_bottom > wave_y_top + 18 then
    DrawReferenceWaveform(ctx, state, draw_list, draw_api, preview, player_fx_idx, master, x + 8, wave_y_top, right - 8, wave_y_bottom, small_font, small_font_size)
  end

  reaper.ImGui_SetCursorScreenPos(ctx, x, y)
  UIUtils.EndAnimatedPanelBodyClip(ctx, body_clip)
  draw_api.dummy(ctx, width, height)
  FocusReferenceInScroll(ctx, state)
end

return ReferencePanel
