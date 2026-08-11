local SampleBrowserPanel = {}
local UIUtils = require("UIUtils")
local UIKit = require("UIKit")

local EXT_SECTION = "RCC"
local EXT_DIR_KEY = "sample_browser_dir"
local EXT_RECURSIVE_KEY = "sample_browser_recursive"
local DEFAULT_SUBDIR = "Data/rcc_samples"
local MAX_FILES = 2000

local SUPPORTED_EXT = {
  wav = true,
  wave = true,
  aif = true,
  aiff = true,
  flac = true,
  mp3 = true,
  ogg = true,
}

local function NormalizePath(path)
  path = tostring(path or ""):gsub("\\", "/")
  path = path:gsub("/+$", "")
  return path
end

local function JoinPath(dir, name)
  dir = NormalizePath(dir)
  name = tostring(name or ""):gsub("^[/\\]+", "")
  if dir == "" then return name end
  return dir .. "/" .. name
end

local function FileExt(name)
  return tostring(name or ""):match("%.([^%.]+)$")
end

local function FileName(path)
  return tostring(path or ""):gsub("\\", "/"):match("([^/]+)$") or tostring(path or "")
end

local function ParentDir(path)
  return tostring(path or ""):gsub("\\", "/"):match("^(.*)/[^/]*$") or ""
end

local function DefaultSampleDir()
  return JoinPath(reaper.GetResourcePath(), DEFAULT_SUBDIR)
end

local function EnsureDir(path)
  path = NormalizePath(path)
  if path == "" then return false end
  if reaper.RecursiveCreateDirectory then
    return reaper.RecursiveCreateDirectory(path, 0) == 0
  end
  return true
end

local function OpenPath(path)
  path = NormalizePath(path)
  if path == "" then return end
  if reaper.CF_ShellExecute then
    reaper.CF_ShellExecute(path)
    return
  end
  reaper.ShowMessageBox(path, "RCC Sample Browser", 0)
end

local function PushSmallFont(ctx, small_font, small_font_size)
  if small_font then
    reaper.ImGui_PushFont(ctx, small_font, small_font_size)
    return true
  end
  return false
end

local function PopSmallFont(ctx, pushed)
  if pushed then
    reaper.ImGui_PopFont(ctx)
  end
end

local function SaveSettings(state)
  if not state then return end
  reaper.SetExtState(EXT_SECTION, EXT_DIR_KEY, NormalizePath(state.sample_browser_dir or ""), true)
  reaper.SetExtState(EXT_SECTION, EXT_RECURSIVE_KEY, state.sample_browser_recursive and "1" or "0", true)
end

local function InitState(state)
  if state.sample_browser_initialized then return end

  local stored_dir = reaper.GetExtState(EXT_SECTION, EXT_DIR_KEY)
  local stored_recursive = reaper.GetExtState(EXT_SECTION, EXT_RECURSIVE_KEY)

  state.sample_browser_dir = NormalizePath(stored_dir ~= "" and stored_dir or DefaultSampleDir())
  state.sample_browser_recursive = stored_recursive == "" and true or stored_recursive == "1"
  state.sample_browser_query = state.sample_browser_query or ""
  state.sample_browser_files = state.sample_browser_files or {}
  state.sample_browser_selected = state.sample_browser_selected or nil
  state.sample_browser_status = state.sample_browser_status or "Ready"
  state.sample_browser_initialized = true
  state.sample_browser_scan_needed = true
end

local function AddFile(files, root, dir, name)
  local ext = FileExt(name)
  if not ext or not SUPPORTED_EXT[ext:lower()] then return end

  local path = JoinPath(dir, name)
  local rel = path
  local root_prefix = NormalizePath(root) .. "/"
  if rel:sub(1, #root_prefix):lower() == root_prefix:lower() then
    rel = rel:sub(#root_prefix + 1)
  end

  files[#files + 1] = {
    name = name,
    path = path,
    rel = rel,
    ext = ext:lower(),
  }
end

local function ScanDir(files, root, dir, recursive)
  if #files >= MAX_FILES then return true end

  local index = 0
  while true do
    local name = reaper.EnumerateFiles(dir, index)
    if not name then break end
    AddFile(files, root, dir, name)
    if #files >= MAX_FILES then return true end
    index = index + 1
  end

  if recursive then
    local sub_index = 0
    while true do
      local sub = reaper.EnumerateSubdirectories(dir, sub_index)
      if not sub then break end
      if sub ~= "." and sub ~= ".." then
        local capped = ScanDir(files, root, JoinPath(dir, sub), recursive)
        if capped then return true end
      end
      sub_index = sub_index + 1
    end
  end

  return false
end

local function RefreshFiles(state)
  local root = NormalizePath(state.sample_browser_dir or "")
  EnsureDir(root)

  local files = {}
  local capped = ScanDir(files, root, root, state.sample_browser_recursive)
  table.sort(files, function(a, b)
    return (a.rel or a.name):lower() < (b.rel or b.name):lower()
  end)

  state.sample_browser_files = files
  state.sample_browser_scan_needed = false
  state.sample_browser_selected = nil
  state.sample_browser_status = tostring(#files) .. (capped and "+" or "") .. " files"
end

local function FilterFiles(state)
  local query = tostring(state.sample_browser_query or ""):lower()
  local out = {}
  for _, file in ipairs(state.sample_browser_files or {}) do
    local haystack = tostring(file.rel or file.name):lower()
    if query == "" or haystack:find(query, 1, true) then
      out[#out + 1] = file
    end
  end
  return out
end

local function InsertSelected(state)
  local file = state.sample_browser_selected
  if not file or not file.path then
    state.sample_browser_status = "Select a sample"
    return
  end

  reaper.Undo_BeginBlock()
  local ok = reaper.InsertMedia(file.path, 0)
  reaper.Undo_EndBlock("RCC: insert sample", -1)
  local inserted = ok == true or ok == 1
  state.sample_browser_status = inserted and ("Inserted: " .. file.name) or "Insert failed"
end

local function SetDirectory(ctx, state)
  local ok, value = reaper.GetUserInputs("RCC Sample Browser", 1, "Sample folder path:", state.sample_browser_dir or "")
  if not ok then return end

  value = NormalizePath(value)
  if value == "" then return end

  state.sample_browser_dir = value
  SaveSettings(state)
  state.sample_browser_scan_needed = true
end

local function DrawHeaderStatus(ctx, draw_list, draw_api, x, y, right, state, small_font, small_font_size)
  if not draw_api.text then return end

  local text = state.sample_browser_status or ""
  local text_w = UIUtils.TextWidth(ctx, text)
  local pushed = PushSmallFont(ctx, small_font, small_font_size)
  draw_api.text(draw_list, math.max(x + 88, right - text_w - 10), UIUtils.HeaderTextY(ctx, y, text, small_font, small_font_size), 0x8C94A088, text)
  PopSmallFont(ctx, pushed)
end

local function DrawControls(ctx, state, width)
  local row_h = 22
  local gap = 5
  local button_w = 42
  local right_buttons_w = (button_w * 4) + (gap * 3)
  local search_w = math.max(80, width - right_buttons_w - 18)

  reaper.ImGui_SetNextItemWidth(ctx, search_w)
  local changed, query = reaper.ImGui_InputText(ctx, "##sample_browser_search", state.sample_browser_query or "")
  if changed then
    state.sample_browser_query = query
  end

  reaper.ImGui_SameLine(ctx, nil, gap)
  if UIKit.TinyButton(ctx, "SET##sample_dir", button_w, row_h, false) then
    SetDirectory(ctx, state)
  end

  reaper.ImGui_SameLine(ctx, nil, gap)
  if UIKit.TinyButton(ctx, "OPEN##sample_open", button_w, row_h, false) then
    EnsureDir(state.sample_browser_dir)
    OpenPath(state.sample_browser_dir)
  end

  reaper.ImGui_SameLine(ctx, nil, gap)
  if UIKit.TinyButton(ctx, "REC##sample_recursive", button_w, row_h, state.sample_browser_recursive) then
    state.sample_browser_recursive = not state.sample_browser_recursive
    SaveSettings(state)
    state.sample_browser_scan_needed = true
  end

  reaper.ImGui_SameLine(ctx, nil, gap)
  if UIKit.TinyButton(ctx, "SCAN##sample_scan", button_w, row_h, false) then
    state.sample_browser_scan_needed = true
  end
end

local function DrawList(ctx, state, files, width, height)
  local flags = 0
  if reaper.ImGui_WindowFlags_HorizontalScrollbar then
    flags = flags | reaper.ImGui_WindowFlags_HorizontalScrollbar()
  end

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x10121688)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x24252AFF)

  if reaper.ImGui_BeginChild(ctx, "##sample_browser_list", width, height, true, flags) then
    if #(state.sample_browser_files or {}) == 0 then
      reaper.ImGui_TextDisabled(ctx, "No samples found")
    elseif #files == 0 then
      reaper.ImGui_TextDisabled(ctx, "No matches")
    else
      for index, file in ipairs(files) do
        local label = (file.rel or file.name) .. "##sample_file_" .. tostring(index)
        local selected = state.sample_browser_selected and state.sample_browser_selected.path == file.path
        if reaper.ImGui_Selectable(ctx, label, selected) then
          state.sample_browser_selected = file
        end
        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
          state.sample_browser_selected = file
          InsertSelected(state)
        end
      end
    end
    reaper.ImGui_EndChild(ctx)
  end

  reaper.ImGui_PopStyleColor(ctx, 2)
end

local function DrawFooter(ctx, state, screen_x, width)
  local selected = state.sample_browser_selected
  local name = selected and selected.name or "No sample selected"
  local max_chars = math.max(18, math.floor((width - 82) / 7))
  if #name > max_chars then
    name = "..." .. name:sub(#name - max_chars + 4)
  end

  reaper.ImGui_TextDisabled(ctx, name)
  reaper.ImGui_SameLine(ctx)
  local button_w = math.min(74, math.max(58, width * 0.28))
  local _, screen_y = reaper.ImGui_GetCursorScreenPos(ctx)
  reaper.ImGui_SetCursorScreenPos(ctx, screen_x + width - button_w, screen_y)
  if UIKit.TinyButton(ctx, "INSERT##sample_insert", button_w, 22, selected ~= nil) then
    InsertSelected(state)
  end

  if selected and reaper.ImGui_BeginPopupContextItem(ctx, "##sample_context") then
    if reaper.ImGui_Selectable(ctx, "Open file") then
      OpenPath(selected.path)
    end
    if reaper.ImGui_Selectable(ctx, "Open folder") then
      OpenPath(ParentDir(selected.path))
    end
    reaper.ImGui_EndPopup(ctx)
  end
end

function SampleBrowserPanel.Draw(ctx, state, _, _, small_font, small_font_size)
  InitState(state)
  if state.sample_browser_scan_needed then
    RefreshFiles(state)
  end

  local draw_api = UIUtils.GetDrawApi()
  if not draw_api then return end

  local width = reaper.ImGui_GetContentRegionAvail(ctx)
  local full_height = 164
  local height, _, collapse_anim = UIUtils.GetCollapsiblePanelHeight(state, "sample_browser", full_height, 22)
  local draw_list = draw_api.get_draw_list(ctx)
  local x, y = draw_api.get_cursor_pos(ctx)
  local right = x + width
  local bottom = y + height

  UIUtils.DrawInstrumentPanel(draw_list, draw_api, x, y, right, bottom, 6.0)
  UIUtils.DrawCollapsibleModuleLabel(ctx, draw_list, draw_api, x, y, "SAMPLE BROWSER", "sample_browser", state, small_font, small_font_size)
  DrawHeaderStatus(ctx, draw_list, draw_api, x, y, right, state, small_font, small_font_size)

  local body_clip = UIUtils.BeginAnimatedPanelBodyClip(ctx, x, y, right, bottom, collapse_anim)
  if not body_clip then
    draw_api.dummy(ctx, width, height)
    return
  end

  local body_x = x + 7
  local body_y = y + 25
  local body_w = math.max(1, width - 14)
  reaper.ImGui_SetCursorScreenPos(ctx, body_x, body_y)

  local pushed = PushSmallFont(ctx, small_font, small_font_size)
  DrawControls(ctx, state, body_w)
  reaper.ImGui_SetCursorScreenPos(ctx, body_x, body_y + 27)
  local filtered = FilterFiles(state)
  DrawList(ctx, state, filtered, body_w, math.max(44, height - 82))
  reaper.ImGui_SetCursorScreenPos(ctx, body_x, bottom - 28)
  DrawFooter(ctx, state, body_x, body_w)
  PopSmallFont(ctx, pushed)

  UIUtils.EndAnimatedPanelBodyClip(ctx, body_clip)
  draw_api.dummy(ctx, width, height)
end

return SampleBrowserPanel
