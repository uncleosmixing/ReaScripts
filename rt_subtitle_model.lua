-- Shared subtitle data model for ReaTitles.
--
-- P_NOTES is the displayed phrase text and remains authoritative while the
-- active source-word signature is unchanged. rt_montage_model.lua may rebuild
-- it when an audio edit actually removes or separates spoken words.
-- Word timing is auxiliary data used by split/repair/montage operations.
-- New timing rows are relative to the subtitle item's left edge so moving an
-- item (including REAPER Ripple Edit) never invalidates them.

local M = {}

M.NOTES_KEY = "P_NOTES"
M.RELATIVE_TIMING_KEY = "P_EXT:REATITLES_WORD_TIMING_REL"
M.LEGACY_TIMING_KEY = "P_EXT:REATITLES_WORD_TIMING"
M.TIMING_ANCHOR_KEY = "P_EXT:REATITLES_TIMING_ANCHOR"
M.TIMING_LENGTH_KEY = "P_EXT:REATITLES_TIMING_LENGTH"
M.AUDIO_WORDS_KEY = "P_EXT:REATITLES_AUDIO_WORDS"
M.HIDDEN_TAKE_MARKERS_KEY = "P_EXT:REATITLES_HIDDEN_TAKE_MARKERS"
M.TAKE_MARKERS_SECTION = "ReaTitles"
M.TAKE_MARKERS_VISIBLE_KEY = "take_markers_visible"
M.EPSILON = 0.000001

function M.take_markers_visible()
  return reaper.GetExtState(
    M.TAKE_MARKERS_SECTION, M.TAKE_MARKERS_VISIBLE_KEY) ~= "0"
end

function M.set_take_markers_visible(visible)
  reaper.SetExtState(
    M.TAKE_MARKERS_SECTION, M.TAKE_MARKERS_VISIBLE_KEY,
    visible and "1" or "0", true)
end

function M.get_string(item, key)
  local _, value = reaper.GetSetMediaItemInfo_String(item, key, "", false)
  return value or ""
end

function M.set_string(item, key, value)
  reaper.GetSetMediaItemInfo_String(item, key, value or "", true)
end

function M.get_take_string(take, key)
  local _, value = reaper.GetSetMediaItemTakeInfo_String(take, key, "", false)
  return value or ""
end

function M.set_take_string(take, key, value)
  reaper.GetSetMediaItemTakeInfo_String(take, key, value or "", true)
end

function M.parse_words(metadata)
  local words = {}
  for row in (metadata or ""):gmatch("[^\r\n]+") do
    local start_pos, end_pos, text =
      row:match("^([%-%d%.]+)\t([%-%d%.]+)\t(.*)$")
    start_pos, end_pos = tonumber(start_pos), tonumber(end_pos)
    if start_pos and end_pos and text then
      words[#words + 1] = { start_pos, end_pos, text }
    end
  end
  table.sort(words, function(a, b)
    if a[1] == b[1] then return a[2] < b[2] end
    return a[1] < b[1]
  end)
  return words
end

function M.serialize_words(words)
  local rows = {}
  for _, word in ipairs(words or {}) do
    local start_pos, end_pos, text =
      tonumber(word[1]), tonumber(word[2]), tostring(word[3] or "")
    if start_pos and end_pos then
      text = text:gsub("[\r\n\t]", " ")
      rows[#rows + 1] = string.format(
        "%.9f\t%.9f\t%s", start_pos, end_pos, text)
    end
  end
  return table.concat(rows, "\n")
end

function M.set_relative_words(item, words)
  M.set_string(item, M.RELATIVE_TIMING_KEY, M.serialize_words(words))
  -- Remove movement-sensitive legacy state after successful migration.
  M.set_string(item, M.LEGACY_TIMING_KEY, "")
  M.set_string(item, M.TIMING_ANCHOR_KEY, "")
  M.set_string(item, M.TIMING_LENGTH_KEY, "")
end

function M.get_relative_words(item, migrate_legacy)
  local relative = M.get_string(item, M.RELATIVE_TIMING_KEY)
  if relative ~= "" then return M.parse_words(relative), false end

  local legacy = M.get_string(item, M.LEGACY_TIMING_KEY)
  if legacy == "" then return {}, false end

  local absolute_words = M.parse_words(legacy)
  local anchor = tonumber(M.get_string(item, M.TIMING_ANCHOR_KEY))
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_pos + item_length
  local overlapping = {}
  for _, word in ipairs(absolute_words) do
    local midpoint = (word[1] + word[2]) * 0.5
    if midpoint >= item_pos - M.EPSILON and
       midpoint < item_end - M.EPSILON then
      overlapping[#overlapping + 1] = word
    end
  end

  -- Unmoved legacy items and native split children can be converted exactly
  -- from their current project range. If an old item has already moved, use its
  -- saved anchor; very old projects without anchors align the first word to 0.
  local source_words = (#overlapping > 0) and overlapping or absolute_words
  local base
  if #overlapping > 0 then
    base = item_pos
  elseif anchor then
    base = anchor
  elseif absolute_words[1] then
    base = absolute_words[1][1]
  else
    base = item_pos
  end
  local words = {}
  for _, word in ipairs(source_words) do
    words[#words + 1] = {
      word[1] - base,
      word[2] - base,
      word[3],
    }
  end
  if migrate_legacy and #words > 0 then M.set_relative_words(item, words) end
  return words, true
end

function M.words_for_range(words, range_start, range_end, rebase)
  local selected = {}
  for _, word in ipairs(words or {}) do
    local midpoint = (word[1] + word[2]) * 0.5
    if midpoint >= range_start - M.EPSILON and
       midpoint < range_end - M.EPSILON then
      selected[#selected + 1] = {
        word[1] - (rebase or 0),
        word[2] - (rebase or 0),
        word[3],
      }
    end
  end
  return selected
end

function M.text_from_words(words)
  local parts = {}
  for _, word in ipairs(words or {}) do
    parts[#parts + 1] = tostring(word[3] or "")
  end
  return table.concat(parts):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.text_for_range(words, range_start, range_end)
  return M.text_from_words(
    M.words_for_range(words, range_start, range_end, 0))
end

function M.snap_word_to_onset(take, w_start, prev_end_time)
  -- stable-ts provides highly accurate word timestamps, no snapping needed
  -- Calibration offset is applied in set_audio_words
  return w_start
end

-- ── Calibration offset ──────────────────────────────────────────────────────
-- The calibration offset compensates for any systematic delay between the
-- Whisper-predicted word start and the actual audible onset.
-- It is measured by comparing user-corrected take markers vs stored word data.

local CALIB_EXT_SECTION = "ReaTitles"
local CALIB_EXT_KEY     = "calibration_offset_sec"

function M.get_calibration_offset()
  local ok, val = reaper.GetProjExtState(0, CALIB_EXT_SECTION, CALIB_EXT_KEY)
  if ok > 0 and val ~= "" then
    return tonumber(val) or 0.0
  end
  return 0.0
end

function M.set_calibration_offset(offset)
  reaper.SetProjExtState(0, CALIB_EXT_SECTION, CALIB_EXT_KEY,
    string.format("%.6f", offset))
end

--- Measure calibration offset from a user-corrected audio item.
--- Call this after the user manually moves take markers to the correct positions.
--- Returns the computed offset in seconds (positive = Whisper was early).
function M.calibrate_from_markers(item)
  local take = reaper.GetActiveTake(item)
  if not take then return nil, "No active take" end
  
  local stored_words = M.get_audio_words(take)
  if #stored_words == 0 then
    return nil, "No stored word data on this item (run transcription first)"
  end
  
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local num_markers = reaper.GetNumTakeMarkers(take)
  if num_markers == 0 then
    return nil, "No take markers on this item"
  end
  
  -- Collect marker positions keyed by index
  local marker_positions = {}
  for mi = 0, num_markers - 1 do
    local retval, name, pos = reaper.GetTakeMarker(take, mi)
    if retval >= 0 then
      -- pos is relative to take start in take time (source seconds)
      marker_positions[mi + 1] = pos
    end
  end
  
  -- Compute per-word delta: marker_pos − whisper_word_start
  local deltas = {}
  for wi, word in ipairs(stored_words) do
    local marker_pos = marker_positions[wi]
    if marker_pos then
      local whisper_pos = word[1]  -- stored relative to take
      local delta = marker_pos - whisper_pos
      table.insert(deltas, delta)
      reaper.ShowConsoleMsg(string.format(
        "[Calibrate] Word %d '%s': whisper=%.3f marker=%.3f delta=%.3f\n",
        wi, word[3] or "?", whisper_pos, marker_pos, delta))
    end
  end
  
  if #deltas == 0 then
    return nil, "Could not match any markers to stored words"
  end
  
  -- Use median to avoid outliers
  table.sort(deltas)
  local median_delta
  local n = #deltas
  if n % 2 == 1 then
    median_delta = deltas[math.ceil(n / 2)]
  else
    median_delta = (deltas[n / 2] + deltas[n / 2 + 1]) / 2.0
  end
  
  M.set_calibration_offset(median_delta)
  reaper.ShowConsoleMsg(string.format(
    "[Calibrate] Measured %d word deltas. Median offset = %.3f sec saved.\n",
    #deltas, median_delta))
  return median_delta, nil
end

function M.set_audio_words(take, words)
  -- Rebuild take markers and snap times
  local markers_visible = M.take_markers_visible()
  if markers_visible then
    local num_markers = reaper.GetNumTakeMarkers(take)
    for i = num_markers - 1, 0, -1 do
      reaper.DeleteTakeMarker(take, i)
    end
  end
  
  local calibration = M.get_calibration_offset()
  
  local snapped_words = {}
  local prev_end = 0
  for _, word in ipairs(words) do
    local start_time = word[1] + calibration
    local snapped = M.snap_word_to_onset(take, start_time, prev_end)
    if markers_visible then
      reaper.SetTakeMarker(take, -1, word[3], snapped, 0)
    end
    
    local w_end = word[2] + calibration
    if w_end < snapped then w_end = snapped + 0.1 end
    table.insert(snapped_words, { snapped, w_end, word[3] })
    
    prev_end = snapped
  end
  
  -- Store snapped in take extension state (without calibration, so raw)
  -- Store raw word times (without calibration offset) for future re-calibration
  local raw_words = {}
  for _, word in ipairs(words) do
    table.insert(raw_words, { word[1], word[2], word[3] })
  end
  M.set_take_string(take, M.AUDIO_WORDS_KEY, M.serialize_words(raw_words))
end

function M.get_audio_words(take)
  local data = M.get_take_string(take, M.AUDIO_WORDS_KEY)
  if data == "" then return {} end
  return M.parse_words(data)
end

local function escape_marker_name(value)
  return tostring(value or "")
    :gsub("%%", "%%25")
    :gsub("\t", "%%09")
    :gsub("\r", "%%0D")
    :gsub("\n", "%%0A")
end

local function unescape_marker_name(value)
  return tostring(value or "")
    :gsub("%%0A", "\n")
    :gsub("%%0D", "\r")
    :gsub("%%09", "\t")
    :gsub("%%25", "%%")
end

function M.hide_take_markers(take)
  if not take then return 0 end
  local existing = M.get_take_string(take, M.HIDDEN_TAKE_MARKERS_KEY)
  if existing ~= "" then return 0 end
  local rows = {}
  local count = reaper.GetNumTakeMarkers(take)
  for i = 0, count - 1 do
    local pos, name, color = reaper.GetTakeMarker(take, i)
    if pos and pos >= 0 then
      rows[#rows + 1] = string.format(
        "%.9f\t%d\t%s", pos, tonumber(color) or 0,
        escape_marker_name(name))
    end
  end
  if #rows > 0 then
    M.set_take_string(take, M.HIDDEN_TAKE_MARKERS_KEY, table.concat(rows, "\n"))
  end
  for i = count - 1, 0, -1 do
    reaper.DeleteTakeMarker(take, i)
  end
  return #rows
end

function M.show_take_markers(take)
  if not take then return 0 end
  local snapshot = M.get_take_string(take, M.HIDDEN_TAKE_MARKERS_KEY)
  local restored = 0
  if snapshot ~= "" then
    for row in snapshot:gmatch("[^\r\n]+") do
      local pos, color, name =
        row:match("^([%-%d%.]+)\t([%-%d]+)\t(.*)$")
      pos, color = tonumber(pos), tonumber(color)
      if pos then
        reaper.SetTakeMarker(
          take, -1, unescape_marker_name(name), pos, color or 0)
        restored = restored + 1
      end
    end
    M.set_take_string(take, M.HIDDEN_TAKE_MARKERS_KEY, "")
    return restored
  end
  local words = M.get_audio_words(take)
  if #words > 0 then
    M.set_audio_words(take, words)
    restored = #words
  end
  return restored
end

return M
