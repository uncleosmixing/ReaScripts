local ReferencePlayer = {}
local FX_DIR = "RCC"
local ensure_checked = false
local ensure_changed = false
local ensure_error = nil

local REF_PLAYER_FILE = "RCC_RefPlayer_v1.jsfx"
local REF_PLAYER_FX_NAMES = {
  "JS: RCC/RCC_RefPlayer_v1",
  "JS: RCC Reference Player v1",
  "RCC_RefPlayer_v1",
  "RCC Reference Player v1",
}
local JSFX_REF_PLAYER = [[desc:RCC Reference Player v1
options:gmem=RCC_ANALYZER_TAP
options:maxmem=33554432

slider1:0<0,1,1{Mix (A),Reference (B)}>Mode
slider2:0<-60,12,0.1>Volume (dB)
slider3:0<0,100,1>Offset (fake)
slider4:1<0,1,1{Free,Sync}>Sync Mode
slider5:0<0,1,1{Stereo,Mono}>Ref Mono

@init
fade_ref = 0;
fade_speed = 1 / (srate * 0.025); // 25ms equal-power crossfade transition speed

slot_fade = 1.0;
ref_load_triggered = 0;
load_state = 0; // 0 - idle, 1 - fadeout, 2 - load first chunk, 3 - async loading
mem_ptr = 0;
total_samples_loaded = 0;
loaded_frames = 0;
loaded_nch = 0;
loaded_srate = 44100;
fp = 0;

free_play_pos = 0;
free_playing = 0;

last_gmem_path_time = 0;
last_transport_serial = 0;

sync_start_frame = 0;
sample_offset = 0;
last_played_frame = 0;

@block
// Check for file path change in gmem
gmem_path_time = gmem[10100];
gmem_path_time != last_gmem_path_time ? (
  last_gmem_path_time = gmem_path_time;
  len = gmem[10000];
  len > 0 ? (
    // Assemble string #path from global memory
    str_setlen(#path, len);
    i = 0;
    loop(len,
      char = gmem[10001 + i];
      str_setchar(#path, i, char);
      i += 1;
    );
    // Trigger smooth fade-out before loading new slot
    ref_load_triggered = 1;
  ) : (
    // Clear reference file
    ref_load_triggered = 0;
    load_state = 0;
    fp > 0 ? (
      file_close(fp);
      fp = 0;
    );
    total_samples_loaded = 0;
    loaded_frames = 0;
    loaded_nch = 0;
    last_played_frame = 0;
  );
);

// Check for transport commands from UI
curr_serial = gmem[10300];
curr_serial != last_transport_serial ? (
  last_transport_serial = curr_serial;
  free_playing = gmem[10302];
  seek_norm = gmem[10301];
  free_play_pos = seek_norm * loaded_frames;
  last_played_frame = free_play_pos;
);

// Read settings from gmem
ref_sync_mode = gmem[10303]; // 1 - sync, 0 - free
ref_loop_enabled = gmem[10307]; // 1 - loop, 0 - off
ref_loop_start = gmem[10308];
ref_loop_end = gmem[10309];

// Load State Machine - Load entire file instantly (since progressive file handles are killed by host between blocks)
load_state == 2 ? (
  fp = file_open(#path);
  fp > 0 ? (
    file_riff(fp, loaded_nch, loaded_srate);
    loaded_nch > 0 && loaded_srate > 0 ? (
      mem_ptr = 0;
      total_samples_loaded = 0;
      max_remaining = 33000000;
      samples_read = file_mem(fp, mem_ptr, max_remaining);
      while(samples_read > 0 ? (
        total_samples_loaded += samples_read;
        mem_ptr += samples_read;
        max_remaining = 33000000 - mem_ptr;
        samples_read = file_mem(fp, mem_ptr, max_remaining);
      ));
      file_close(fp);
      fp = 0;
      loaded_frames = total_samples_loaded / loaded_nch;
      
      ref_load_triggered = 3; // Trigger fade-in for the new slot
      free_play_pos = 0;
      last_played_frame = 0;
    ) : (
      file_close(fp);
      fp = 0;
      ref_load_triggered = 0;
      total_samples_loaded = 0;
      loaded_frames = 0;
      slot_fade = 1.0; // Reset fade on error
    );
  ) : (
    ref_load_triggered = 0;
    total_samples_loaded = 0;
    loaded_frames = 0;
    slot_fade = 1.0; // Reset fade on error
  );
  load_state = 0;
);

// Track exact start frame of the block for sample-accurate host sync (compensating for project start time offset)
project_time_offset = gmem[10310];
sync_play_pos = play_position - project_time_offset;
sync_start_frame = sync_play_pos * loaded_srate;
sample_offset = 0;

// Force visual cursor alignment on host stop in SYNC mode
ref_sync_mode == 1 && (play_state & 1) == 0 ? (
  last_played_frame = sync_start_frame;
);

// Publish diagnostics for UI
gmem[10202] = loaded_frames;
gmem[10203] = loaded_nch;
gmem[10204] = loaded_srate;
gmem[10306] = free_playing;

// Share playback position with Lua based on actual DSP played frame
loaded_frames > 0 ? (
  gmem[10304] = last_played_frame / loaded_frames;
) : (
  gmem[10304] = 0;
);

@sample
gain = 10 ^ (slider2 / 20);
is_ref = (slider1 == 1);

// Smooth A/B crossfading
fade_ref = max(0, min(1, fade_ref + (is_ref ? fade_speed : -fade_speed)));

// Smooth Slot switching crossfading
ref_load_triggered == 1 ? (
  slot_fade = max(0, slot_fade - fade_speed);
  slot_fade == 0 ? (
    load_state = 2; // Signal @block to load new file
    ref_load_triggered = 2; // Wait for load
  );
) : ref_load_triggered == 3 ? (
  slot_fade = min(1, slot_fade + fade_speed);
  slot_fade == 1 ? (
    ref_load_triggered = 0; // Transition completed
  );
);

ref_l = 0;
ref_r = 0;

loaded_frames > 0 && slot_fade > 0 ? (
  ref_sync_mode == 1 ? (
    (play_state & 1) != 0 ? (
      raw_frame = sync_start_frame + sample_offset * (loaded_srate / srate);
      sample_offset += 1;
      
      // SYNC Mode Loop support
      ref_loop_enabled == 1 && ref_loop_end > ref_loop_start ? (
        loop_start_frame = ref_loop_start * loaded_frames;
        loop_end_frame = ref_loop_end * loaded_frames;
        raw_frame >= loop_start_frame ? (
          loop_len = loop_end_frame - loop_start_frame;
          loop_len > 0 ? (
            frame_idx = loop_start_frame + (raw_frame - loop_start_frame) % loop_len;
          ) : (
            frame_idx = raw_frame;
          );
        ) : (
          frame_idx = raw_frame;
        );
      ) : (
        frame_idx = raw_frame;
      );
    ) : (
      frame_idx = -1;
    );
  ) : (
    frame_idx = free_play_pos;
    
    free_playing && is_ref ? (
      step = loaded_srate / srate;
      free_play_pos += step;
      
      ref_loop_enabled == 1 && ref_loop_end > ref_loop_start ? (
        loop_start_frame = ref_loop_start * loaded_frames;
        loop_end_frame = ref_loop_end * loaded_frames;
        free_play_pos >= loop_end_frame ? (
          free_play_pos = loop_start_frame;
        );
      ) : (
        free_play_pos >= loaded_frames ? (
          free_play_pos = loaded_frames;
          free_playing = 0;
        );
      );
    );
  );
  
  // Track last played frame for UI visual alignment
  frame_idx >= 0 ? (
    last_played_frame = frame_idx;
  );
  
  // Real-time linear interpolation resampling
  frame_idx >= 0 && frame_idx < loaded_frames - 1 ? (
    idx_floor = floor(frame_idx);
    frac = frame_idx - idx_floor;
    
    loaded_nch == 2 ? (
      addr = idx_floor * 2;
      ref_l = (mem[addr] * (1 - frac) + mem[addr + 2] * frac) * gain * slot_fade;
      ref_r = (mem[addr + 1] * (1 - frac) + mem[addr + 3] * frac) * gain * slot_fade;
    ) : (
      ref_l = (mem[idx_floor] * (1 - frac) + mem[idx_floor + 1] * frac) * gain * slot_fade;
      ref_r = ref_l;
    );
  );
);

// Ref mono control
slider5 == 1 ? (
  ref_mono_val = (ref_l + ref_r) * 0.5;
  ref_l = ref_mono_val;
  ref_r = ref_mono_val;
);

// Premium trigonometric equal-power crossfade
angle = fade_ref * $pi * 0.5;
cos_fade = cos(angle);
sin_fade = sin(angle);

spl0 = spl0 * cos_fade + ref_l * sin_fade;
spl1 = spl1 * cos_fade + ref_r * sin_fade;
]]

local function PathJoin(left, right)
  local sep = package.config:sub(1, 1)
  if left:sub(-1) == sep then
    return left .. right
  end

  return left .. sep .. right
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

function ReferencePlayer.Install()
  local effects_dir = PathJoin(reaper.GetResourcePath(), "Effects")
  local rcc_dir = PathJoin(effects_dir, FX_DIR)
  local fx_path = PathJoin(rcc_dir, REF_PLAYER_FILE)

  reaper.RecursiveCreateDirectory(rcc_dir, 0)
  
  -- Create reference tracks directory: REAPER/Data/ref_tracks
  local data_dir = PathJoin(reaper.GetResourcePath(), "Data")
  local ref_tracks_dir = PathJoin(data_dir, "ref_tracks")
  reaper.RecursiveCreateDirectory(ref_tracks_dir, 0)

  if ReadFile(fx_path) ~= JSFX_REF_PLAYER and not WriteFile(fx_path, JSFX_REF_PLAYER) then
    return false, "Cannot write RCC Reference Player JSFX"
  end

  if not reaper.TrackFX_AddByName then
    return false, "TrackFX_AddByName is unavailable"
  end

  local master = reaper.GetMasterTrack(0)
  local fx_index = -1

  for _, fx_name in ipairs(REF_PLAYER_FX_NAMES) do
    fx_index = reaper.TrackFX_AddByName(master, fx_name, true, 1)
    if fx_index >= 0 then
      break
    end
  end

  if fx_index < 0 then
    return false, "RCC Reference Player was installed, but REAPER did not load it"
  end

  return true, fx_index
end

function ReferencePlayer.EnsureFile()
  if ensure_checked then
    local changed = ensure_changed
    ensure_changed = false
    return ensure_error == nil, ensure_error, changed
  end

  local effects_dir = PathJoin(reaper.GetResourcePath(), "Effects")
  local rcc_dir = PathJoin(effects_dir, FX_DIR)
  local fx_path = PathJoin(rcc_dir, REF_PLAYER_FILE)

  reaper.RecursiveCreateDirectory(rcc_dir, 0)

  local changed = ReadFile(fx_path) ~= JSFX_REF_PLAYER
  if changed and not WriteFile(fx_path, JSFX_REF_PLAYER) then
    ensure_checked = true
    ensure_error = "Cannot write RCC Reference Player JSFX"
    ensure_changed = false
    return false, ensure_error, false
  end

  ensure_checked = true
  ensure_changed = changed
  ensure_changed = false
  return true, nil, changed
end

return ReferencePlayer
