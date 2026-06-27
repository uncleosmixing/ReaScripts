-- @description ReaTitles Smart Split
-- @version 1.0.0
-- @author ReaTitles
-- @about
--   Split selected subtitle/audio groups at the edit cursor.
--   Subtitle text is divided using Whisper word timestamps.

local r = reaper
local EPSILON = 0.000001
local WORD_TIMING_KEY = "P_EXT:REATITLES_WORD_TIMING"

local function get_string(item, key)
  local _, value = r.GetSetMediaItemInfo_String(item, key, "", false)
  return value or ""
end

local function set_string(item, key, value)
  r.GetSetMediaItemInfo_String(item, key, value or "", true)
end

local function parse_words(metadata)
  local words = {}
  for row in (metadata or ""):gmatch("[^\r\n]+") do
    local start_pos, end_pos, text =
      row:match("^([%-%d%.]+)\t([%-%d%.]+)\t(.*)$")
    start_pos, end_pos = tonumber(start_pos), tonumber(end_pos)
    if start_pos and end_pos and text then
      words[#words+1] = { start_pos, end_pos, text }
    end
  end
  return words
end

local function text_for_range(words, range_start, range_end)
  local parts = {}
  for _, word in ipairs(words) do
    local midpoint = (word[1] + word[2]) * 0.5
    if midpoint >= range_start - EPSILON and midpoint < range_end - EPSILON then
      parts[#parts+1] = word[3]
    end
  end
  return table.concat(parts):gsub("^%s+", ""):gsub("%s+$", "")
end

local function fallback_split_text(text, ratio)
  text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return "", "" end
  ratio = math.max(0, math.min(1, ratio))
  local target = #text * ratio
  local candidates = {}

  -- Prefer a sentence boundary near the acoustic cut.
  local search_from = 1
  while true do
    local s, e = text:find("[%.%!%?…]+%s+", search_from)
    if not s then break end
    candidates[#candidates+1] = e
    search_from = e + 1
  end

  -- Fall back to any word boundary.
  if #candidates == 0 then
    search_from = 1
    while true do
      local s, e = text:find("%s+", search_from)
      if not s then break end
      candidates[#candidates+1] = e
      search_from = e + 1
    end
  end

  if #candidates == 0 then
    return text, ""
  end
  local best = candidates[1]
  for _, boundary in ipairs(candidates) do
    if math.abs(boundary - target) < math.abs(best - target) then best = boundary end
  end
  local left = text:sub(1, best):gsub("%s+$", "")
  local right = text:sub(best + 1):gsub("^%s+", "")
  return left, right
end

local function update_take_name(item, text)
  local take = r.GetActiveTake(item)
  if not take then return end
  local short = text
  if #short > 40 then short = short:sub(1, 40) .. "..." end
  r.GetSetMediaItemTakeInfo_String(take, "P_NAME", short, true)
end

local function collect_targets(cursor)
  local selected = {}
  local selected_groups = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    selected[item] = true
    local group_id = r.GetMediaItemInfo_Value(item, "I_GROUPID")
    if group_id > 0 then selected_groups[group_id] = true end
  end

  local targets = {}
  for t = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, t)
    for i = 0, r.CountTrackMediaItems(track) - 1 do
      local item = r.GetTrackMediaItem(track, i)
      local group_id = r.GetMediaItemInfo_Value(item, "I_GROUPID")
      if selected[item] or selected_groups[group_id] then
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")
        if cursor > pos + EPSILON and cursor < item_end - EPSILON then
          targets[#targets+1] = {
            item = item,
            pos = pos,
            item_end = item_end,
            group_id = group_id,
            notes = get_string(item, "P_NOTES"),
            metadata = get_string(item, WORD_TIMING_KEY),
          }
        end
      end
    end
  end
  return targets
end

local function next_group_ids(count)
  local max_group = 0
  for t = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, t)
    for i = 0, r.CountTrackMediaItems(track) - 1 do
      max_group = math.max(
        max_group,
        r.GetMediaItemInfo_Value(r.GetTrackMediaItem(track, i), "I_GROUPID"))
    end
  end
  local ids = {}
  for i = 1, count do ids[i] = max_group + i end
  return ids
end

local function main()
  if r.CountSelectedMediaItems(0) == 0 then
    r.ShowMessageBox(
      "Select an audio or subtitle item, place the edit cursor inside it, and run Smart Split.",
      "ReaTitles Smart Split", 0)
    return
  end

  local cursor = r.GetCursorPosition()
  local targets = collect_targets(cursor)
  if #targets == 0 then
    r.ShowMessageBox(
      "The edit cursor does not cross any selected/grouped item.",
      "ReaTitles Smart Split", 0)
    return
  end

  local group_map = {}
  local group_count = 0
  for _, target in ipairs(targets) do
    if target.group_id > 0 and not group_map[target.group_id] then
      group_count = group_count + 1
      group_map[target.group_id] = group_count
    end
  end
  local ids = next_group_ids(group_count * 2)
  for old_group, index in pairs(group_map) do
    group_map[old_group] = {
      left = ids[(index - 1) * 2 + 1],
      right = ids[(index - 1) * 2 + 2],
    }
  end

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok, err = xpcall(function()
    r.Main_OnCommand(40289, 0) -- Unselect all items
    for _, target in ipairs(targets) do
      if r.ValidatePtr(target.item, "MediaItem*") then
        local right = r.SplitMediaItem(target.item, cursor)
        if right then
          local groups = group_map[target.group_id]
          if groups then
            r.SetMediaItemInfo_Value(target.item, "I_GROUPID", groups.left)
            r.SetMediaItemInfo_Value(right, "I_GROUPID", groups.right)
          end

          if target.notes ~= "" or target.metadata ~= "" then
            -- SplitMediaItem may not copy extension data on every REAPER build.
            if target.metadata ~= "" then
              set_string(target.item, WORD_TIMING_KEY, target.metadata)
              set_string(right, WORD_TIMING_KEY, target.metadata)
            end

            local left_text, right_text
            local words = parse_words(target.metadata)
            if #words > 0 then
              left_text = text_for_range(words, target.pos, cursor)
              right_text = text_for_range(words, cursor, target.item_end)
            else
              local ratio = (cursor - target.pos) / (target.item_end - target.pos)
              left_text, right_text = fallback_split_text(target.notes, ratio)
            end

            set_string(target.item, "P_NOTES", left_text)
            set_string(right, "P_NOTES", right_text)
            update_take_name(target.item, left_text)
            update_take_name(right, right_text)
          end
          r.SetMediaItemSelected(right, true)
        end
      end
    end
  end, debug.traceback)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("ReaTitles: Smart Split", -1)

  if not ok then
    r.ShowMessageBox(tostring(err), "ReaTitles Smart Split", 0)
  end
end

main()
