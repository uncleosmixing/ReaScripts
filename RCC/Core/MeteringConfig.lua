local MeteringConfig = {}
local UIUtils = require("UIUtils")

MeteringConfig.METERING_MODES = {
  { id = "dbfs", label = "dBFS" },
  { id = "lufs", label = "LUFS" },
  { id = "spotify", label = "Spotify -14" },
  { id = "youtube", label = "YouTube -14" },
  { id = "apple", label = "Apple -16" },
  { id = "aes18", label = "AES -18" },
  { id = "netflix", label = "Netflix -27" },
  { id = "ebu", label = "EBU -23" },
  { id = "k14", label = "K-14" },
  { id = "k12", label = "K-12" },
  { id = "k20", label = "K-20" },
}

MeteringConfig.METERING_MODE_LABELS = {}
for _, item in ipairs(MeteringConfig.METERING_MODES) do
  MeteringConfig.METERING_MODE_LABELS[item.id] = item.label
end

MeteringConfig.STREAMING_TARGETS = {
  lufs = { target = -14.0, tp = -1.0 },
  spotify = { target = -14.0, tp = -2.0 },
  youtube = { target = -14.0, tp = -1.0 },
  apple = { target = -16.0, tp = -1.0 },
  aes18 = { target = -18.0, tp = -1.0 },
  netflix = { target = -27.0, tp = -2.0 },
}

local function MakeLoudnessModeConfig(target, true_peak_limit)
  return {
    ticks = {-40, target, -6},
    to_norm = function(val_linear)
      local db = UIUtils.Db(val_linear)
      if db <= -40 then return 0.0 end
      if db >= -6 then return 1.0 end
      return (db + 40) / 34
    end,
    to_norm_db = function(lufs)
      if lufs <= -40 then return 0.0 end
      if lufs >= -6 then return 1.0 end
      return (lufs + 40) / 34
    end,
    format_db = function(lufs)
      return string.format("%.1f", lufs) .. " LUFS"
    end,
    is_clip = function(_, true_peak_db)
      return true_peak_db and (true_peak_db >= true_peak_limit)
    end,
    label_color = function(lufs, clip)
      if clip then return 0xFF4F4EFF end
      if lufs > target + 1.0 then return UIUtils.COLOR.red end
      if lufs > target then return UIUtils.COLOR.amber end
      return UIUtils.COLOR.green
    end,
    target = target,
    true_peak_limit = true_peak_limit,
  }
end

local mode_config = {
  dbfs = {
    ticks = {-60, -18, 0},
    to_norm = function(val_linear)
      local db = UIUtils.Db(val_linear)
      if db <= -60 then return 0.0 end
      if db >= 3 then return 1.0 end
      return (db + 60) / 63
    end,
    to_norm_db = function(db)
      if db <= -60 then return 0.0 end
      if db >= 3 then return 1.0 end
      return (db + 60) / 63
    end,
    format_db = function(db)
      return string.format("%.1f", db) .. " dB"
    end,
    is_clip = function(state_val)
      return UIUtils.Db(state_val) >= 0.0
    end,
    label_color = function(db, clip)
      if clip then return 0xFF4F4EFF end
      if db >= -3.0 then return UIUtils.COLOR.red
      elseif db >= -12.0 then return UIUtils.COLOR.amber
      else return UIUtils.COLOR.green
      end
    end
  },
  k14 = {
    ticks = {-34, 0, 4},
    to_norm = function(val_linear)
      local dBr = UIUtils.Db(val_linear) + 14.0
      if dBr <= -34 then return 0.0 end
      if dBr >= 4 then return 1.0 end
      return (dBr + 34) / 38
    end,
    to_norm_db = function(db)
      local dBr = db + 14.0
      if dBr <= -34 then return 0.0 end
      if dBr >= 4 then return 1.0 end
      return (dBr + 34) / 38
    end,
    format_db = function(db)
      local dBr = db + 14.0
      return string.format("%+.1f", dBr) .. " dBr"
    end,
    is_clip = function(state_val)
      return (UIUtils.Db(state_val) + 14.0) >= 4.0
    end,
    label_color = function(db, clip)
      local dBr = db + 14.0
      if clip then return 0xFF4F4EFF end
      if dBr >= 2.0 then return UIUtils.COLOR.red
      elseif dBr >= 0.0 then return UIUtils.COLOR.amber
      else return UIUtils.COLOR.green
      end
    end
  },
  k12 = {
    ticks = {-32, 0, 4},
    to_norm = function(val_linear)
      local dBr = UIUtils.Db(val_linear) + 12.0
      if dBr <= -32 then return 0.0 end
      if dBr >= 4 then return 1.0 end
      return (dBr + 32) / 36
    end,
    to_norm_db = function(db)
      local dBr = db + 12.0
      if dBr <= -32 then return 0.0 end
      if dBr >= 4 then return 1.0 end
      return (dBr + 32) / 36
    end,
    format_db = function(db)
      local dBr = db + 12.0
      return string.format("%+.1f", dBr) .. " dBr"
    end,
    is_clip = function(state_val)
      return (UIUtils.Db(state_val) + 12.0) >= 4.0
    end,
    label_color = function(db, clip)
      local dBr = db + 12.0
      if clip then return 0xFF4F4EFF end
      if dBr >= 2.0 then return UIUtils.COLOR.red
      elseif dBr >= 0.0 then return UIUtils.COLOR.amber
      else return UIUtils.COLOR.green
      end
    end
  },
  k20 = {
    ticks = {-40, 0, 4},
    to_norm = function(val_linear)
      local dBr = UIUtils.Db(val_linear) + 20.0
      if dBr <= -40 then return 0.0 end
      if dBr >= 4 then return 1.0 end
      return (dBr + 40) / 44
    end,
    to_norm_db = function(db)
      local dBr = db + 20.0
      if dBr <= -40 then return 0.0 end
      if dBr >= 4 then return 1.0 end
      return (dBr + 40) / 44
    end,
    format_db = function(db)
      local dBr = db + 20.0
      return string.format("%+.1f", dBr) .. " dBr"
    end,
    is_clip = function(state_val)
      return (UIUtils.Db(state_val) + 20.0) >= 4.0
    end,
    label_color = function(db, clip)
      local dBr = db + 20.0
      if clip then return 0xFF4F4EFF end
      if dBr >= 2.0 then return UIUtils.COLOR.red
      elseif dBr >= 0.0 then return UIUtils.COLOR.amber
      else return UIUtils.COLOR.green
      end
    end
  },
  ebu = {
    ticks = {-40, -23, -10},
    to_norm = function(val_linear)
      local lufs = UIUtils.Db(val_linear)
      if lufs <= -40 then return 0.0 end
      if lufs >= -10 then return 1.0 end
      return (lufs + 40) / 30
    end,
    to_norm_db = function(lufs)
      if lufs <= -40 then return 0.0 end
      if lufs >= -10 then return 1.0 end
      return (lufs + 40) / 30
    end,
    format_db = function(lufs)
      return string.format("%.1f", lufs) .. " LUFS"
    end,
    is_clip = function(state_val, true_peak_db)
      return true_peak_db and (true_peak_db >= -1.0)
    end,
    label_color = function(lufs, clip)
      if clip then return 0xFF4F4EFF end
      if lufs >= -18.0 then return UIUtils.COLOR.red
      elseif lufs >= -23.0 then return UIUtils.COLOR.amber
      else return UIUtils.COLOR.green
      end
    end
  }
}

function MeteringConfig.Get(mode)
  local cfg = mode_config[mode]
  local streaming_target = MeteringConfig.STREAMING_TARGETS[mode]
  if not cfg and streaming_target then
    cfg = MakeLoudnessModeConfig(streaming_target.target, streaming_target.tp)
  end
  if not cfg then
    cfg = mode_config.dbfs
  end
  return cfg
end

return MeteringConfig
