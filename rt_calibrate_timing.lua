-- @description ReaTitles: Calibrate word timing from corrected markers
-- @version 1.7.1
-- @author ReaTitles
-- @about
--   After transcribing an audio item and manually correcting the take marker
--   positions to match the actual word onsets, run this script on the same item.
--   It computes the median offset between your corrected markers and the original
--   Whisper timestamps and saves it as a project-level calibration value.
--   All future transcriptions on this project will apply this offset automatically.

local r = reaper

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  if info and info.source then
    local path = info.source:match("^@(.+)")
    if path then return path:match("^(.*[/\\])") or "" end
  end
  return ""
end

local script_dir = get_script_dir()
local model_path = script_dir .. "rt_subtitle_model.lua"
local chunk = loadfile(model_path)
if not chunk then
  r.ShowMessageBox("Cannot load rt_subtitle_model.lua from:\n" .. model_path, "ReaTitles Calibrate", 0)
  return
end
local M = chunk()

local sel_count = r.CountSelectedMediaItems(0)
if sel_count == 0 then
  r.ShowMessageBox(
    "Select the audio item whose take markers you have already corrected, then run this script.",
    "ReaTitles Calibrate", 0)
  return
end

local current = M.get_calibration_offset()
r.ShowConsoleMsg(string.format("[Calibrate] Current offset: %.3f sec\n", current))

local all_deltas = {}

for i = 0, sel_count - 1 do
  local item = r.GetSelectedMediaItem(0, i)
  if item then
    local take = r.GetActiveTake(item)
    if take then
      local stored_words = M.get_audio_words(take)
      if #stored_words == 0 then
        r.ShowConsoleMsg("[Calibrate] Item " .. (i+1) .. ": no stored word data, skipping\n")
      else
        local num_markers = r.GetNumTakeMarkers(take)
        if num_markers == 0 then
          r.ShowConsoleMsg("[Calibrate] Item " .. (i+1) .. ": no take markers, skipping\n")
        else
          local marker_positions = {}
          for mi = 0, num_markers - 1 do
            local retval, name, pos = r.GetTakeMarker(take, mi)
            if retval >= 0 then
              marker_positions[mi + 1] = pos
            end
          end
          r.ShowConsoleMsg(string.format(
            "[Calibrate] Item %d: %d stored words, %d markers\n",
            i+1, #stored_words, num_markers))
          for wi, word in ipairs(stored_words) do
            local marker_pos = marker_positions[wi]
            if marker_pos then
              local delta = marker_pos - word[1]
              table.insert(all_deltas, delta)
              r.ShowConsoleMsg(string.format(
                "  word %d '%s': whisper=%.3f  marker=%.3f  delta=%+.3f\n",
                wi, word[3] or "?", word[1], marker_pos, delta))
            end
          end
        end
      end
    end
  end
end

if #all_deltas == 0 then
  r.ShowMessageBox(
    "No matching word/marker pairs found.\n\nMake sure you:\n1. Transcribed this item with ReaTitles\n2. Manually corrected the take markers to the correct positions\n3. Selected the same item before running this script",
    "ReaTitles Calibrate", 0)
  return
end

table.sort(all_deltas)
local n = #all_deltas
local median_delta
if n % 2 == 1 then
  median_delta = all_deltas[math.ceil(n / 2)]
else
  median_delta = (all_deltas[n / 2] + all_deltas[n / 2 + 1]) / 2.0
end

local sum = 0
for _, d in ipairs(all_deltas) do sum = sum + d end
local mean_delta = sum / n

M.set_calibration_offset(median_delta)

local msg = string.format(
  "Calibration complete!\n\nMeasured %d word offsets:\n  Median: %+.3f sec\n  Mean:   %+.3f sec\n\nThis offset will be applied to all future transcriptions in this project.\n\nPrevious offset was: %+.3f sec",
  n, median_delta, mean_delta, current)

r.ShowConsoleMsg(string.format(
  "[Calibrate] Done! Saved median offset = %+.3f sec (was %+.3f sec)\n",
  median_delta, current))

r.ShowMessageBox(msg, "ReaTitles Calibrate", 0)
