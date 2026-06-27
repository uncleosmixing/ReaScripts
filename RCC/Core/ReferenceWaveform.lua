local ReferenceWaveform = {}

local cache = {}

local function EstimateLoudness(points)
  if not points or #points == 0 then return -14.0 end
  local sum_sq = 0
  for i = 1, #points do
    local pk = math.max(math.abs(points[i].min or 0), math.abs(points[i].max or 0))
    sum_sq = sum_sq + (pk * pk)
  end
  local rms = math.sqrt(sum_sq / #points)
  if rms <= 0.0001 then return -150.0 end
  local est_db = 20 * (math.log(rms) / math.log(10))
  return math.max(-150.0, math.min(0.0, est_db - 3.0))
end

local function U16LE(data, pos)
  local a, b = data:byte(pos, pos + 1)
  if not a or not b then return 0 end
  return a + b * 256
end

local function U32LE(data, pos)
  local a, b, c, d = data:byte(pos, pos + 3)
  if not a or not b or not c or not d then return 0 end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function I16LE(data, pos)
  local v = U16LE(data, pos)
  if v >= 32768 then v = v - 65536 end
  return v / 32768
end

local function I24LE(data, pos)
  local a, b, c = data:byte(pos, pos + 2)
  if not a or not b or not c then return 0 end
  local v = a + b * 256 + c * 65536
  if v >= 8388608 then v = v - 16777216 end
  return v / 8388608
end

local function I32LE(data, pos)
  local v = U32LE(data, pos)
  if v >= 2147483648 then v = v - 4294967296 end
  return v / 2147483648
end

local function F32LE(data, pos)
  if not string.unpack then return 0 end
  local ok, value = pcall(string.unpack, "<f", data, pos)
  if ok and value then
    return math.max(-1.0, math.min(1.0, value))
  end
  return 0
end

local function ReadSample(data, pos, audio_format, bits)
  if audio_format == 3 and bits == 32 then
    return F32LE(data, pos)
  elseif bits == 16 then
    return I16LE(data, pos)
  elseif bits == 24 then
    return I24LE(data, pos)
  elseif bits == 32 then
    return I32LE(data, pos)
  end

  return 0
end

local function ParseWave(path, point_count)
  local file = io.open(path, "rb")
  if not file then
    return nil, "Cannot open reference file"
  end

  local data = file:read("*a")
  file:close()

  if data:sub(1, 4) ~= "RIFF" or data:sub(9, 12) ~= "WAVE" then
    return nil, "Preview supports WAV files first"
  end

  local fmt = nil
  local data_pos = nil
  local data_size = nil
  local pos = 13

  while pos + 8 <= #data do
    local chunk_id = data:sub(pos, pos + 3)
    local chunk_size = U32LE(data, pos + 4)
    local chunk_data = pos + 8

    if chunk_id == "fmt " then
      fmt = {
        audio_format = U16LE(data, chunk_data),
        channels = U16LE(data, chunk_data + 2),
        sample_rate = U32LE(data, chunk_data + 4),
        block_align = U16LE(data, chunk_data + 12),
        bits = U16LE(data, chunk_data + 14),
      }
    elseif chunk_id == "data" then
      data_pos = chunk_data
      data_size = chunk_size
      break
    end

    pos = chunk_data + chunk_size + (chunk_size % 2)
  end

  if not fmt or not data_pos or not data_size then
    return nil, "WAV preview data missing"
  end

  if fmt.channels <= 0 or fmt.block_align <= 0 or fmt.sample_rate <= 0 then
    return nil, "Unsupported WAV format"
  end

  if fmt.audio_format ~= 1 and fmt.audio_format ~= 3 then
    return nil, "Only PCM/float WAV preview supported"
  end

  local bytes_per_sample = math.floor(fmt.bits / 8)
  if bytes_per_sample <= 0 then
    return nil, "Unsupported bit depth"
  end

  local total_frames = math.floor(data_size / fmt.block_align)
  local points = {}
  local point_total = point_count or 256
  local frames_per_point = math.max(1, math.floor(total_frames / point_total))

  for point = 1, point_total do
    local frame_start = (point - 1) * frames_per_point
    local frame_end = point == point_total and (total_frames - 1) or math.min(total_frames - 1, point * frames_per_point - 1)
    local stride = math.max(1, math.floor((frame_end - frame_start + 1) / 192))
    local min_v = 0
    local max_v = 0

    for frame = frame_start, frame_end, stride do
      local frame_pos = data_pos + frame * fmt.block_align
      local sum = 0

      for ch = 0, fmt.channels - 1 do
        sum = sum + ReadSample(data, frame_pos + ch * bytes_per_sample, fmt.audio_format, fmt.bits)
      end

      local mono = sum / fmt.channels
      if mono < min_v then min_v = mono end
      if mono > max_v then max_v = mono end
    end

    points[#points + 1] = { min = min_v, max = max_v }
  end

  return {
    path = path,
    points = points,
    channels = fmt.channels,
    sample_rate = fmt.sample_rate,
    frames = total_frames,
    duration = total_frames / fmt.sample_rate,
    estimated_lufs = EstimateLoudness(points),
  }, nil
end

local function ParseViaReaperSource(path, point_count)
  if not reaper.PCM_Source_CreateFromFile or not reaper.PCM_Source_GetPeaks or not reaper.new_array then
    return nil, "REAPER preview API unavailable"
  end

  local source = reaper.PCM_Source_CreateFromFile(path)
  if not source then
    return nil, "Cannot create REAPER source"
  end

  local ok, length = pcall(reaper.GetMediaSourceLength, source)
  if not ok or not length or length <= 0 then
    if reaper.PCM_Source_Destroy then reaper.PCM_Source_Destroy(source) end
    return nil, "Cannot read source length"
  end

  local channels = 2
  local sample_count = point_count or 256
  local buffer = reaper.new_array(sample_count * channels * 2)
  local peakrate = sample_count / length
  local peak_ok = pcall(reaper.PCM_Source_GetPeaks, source, peakrate, 0.0, channels, sample_count, 0, buffer)

  if reaper.PCM_Source_Destroy then
    reaper.PCM_Source_Destroy(source)
  end

  if not peak_ok then
    return nil, "Cannot read source peaks"
  end

  local values = buffer.table and buffer.table() or {}
  local points = {}
  local has_signal = false
  local min_offset = sample_count * channels

  for i = 1, sample_count do
    local idx = (i - 1) * channels
    local l_max = values[idx + 1] or 0
    local r_max = values[idx + 2] or l_max
    local l_min = values[min_offset + idx + 1] or -l_max
    local r_min = values[min_offset + idx + 2] or -r_max
    local max_v = (l_max + r_max) * 0.5
    local min_v = (l_min + r_min) * 0.5

    if math.abs(max_v) > 0.000001 or math.abs(min_v) > 0.000001 then
      has_signal = true
    end

    points[#points + 1] = {
      min = math.max(-1.0, math.min(1.0, min_v)),
      max = math.max(-1.0, math.min(1.0, max_v)),
    }
  end

  if not has_signal then
    return nil, "Source peaks unavailable"
  end

  return {
    path = path,
    points = points,
    channels = channels,
    sample_rate = 0,
    frames = 0,
    duration = length,
    estimated_lufs = EstimateLoudness(points),
  }, nil
end

function ReferenceWaveform.Get(path, point_count)
  if not path or path == "" then
    return nil, "No reference file"
  end

  local key = path .. "|" .. tostring(point_count or 256)
  if cache[key] then
    return cache[key], nil
  end

  local preview, error_message = ParseWave(path, point_count)
  if not preview then
    preview, error_message = ParseViaReaperSource(path, point_count)
  end
  if preview then
    cache[key] = preview
  end

  return preview, error_message
end

return ReferenceWaveform
