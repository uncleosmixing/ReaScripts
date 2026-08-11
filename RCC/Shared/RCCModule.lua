local RCCModule = {}
local Config = require("RCCConfig")

local function NormalizeDir(path)
  if not path or path == "" then return "" end
  return path:match("[\\/]$") and path or (path .. package.config:sub(1, 1))
end

local function AddPath(path)
  path = NormalizeDir(path)
  if path == "" then return end
  local pattern = path .. "?.lua;"
  if not package.path:find(pattern, 1, true) then
    package.path = pattern .. package.path
  end
end

function RCCModule.AddSharedPaths(script_dir, shared_dir)
  script_dir = NormalizeDir(script_dir)
  AddPath(script_dir)
  AddPath(shared_dir)
  AddPath(script_dir .. "../Shared")
  AddPath(script_dir .. "../../Shared")
end

function RCCModule.RequireImGui(version)
  if not reaper.ImGui_GetBuiltinPath then
    return nil, "Requires ReaImGui extension"
  end

  AddPath(reaper.ImGui_GetBuiltinPath())
  return require("imgui")(version or "0.9.3")
end

function RCCModule.CreateFonts(ImGui, ctx)
  local fonts = {
    main = ImGui.CreateFont(Config.UI.font_family, Config.UI.font_size_main),
    large = ImGui.CreateFont(Config.UI.font_family, Config.UI.font_size_large),
    small = ImGui.CreateFont(Config.UI.font_family, Config.UI.font_size_small),
    small_bold = ImGui.CreateFont(Config.UI.font_family_bold, Config.UI.font_size_small_bold),
  }

  ImGui.Attach(ctx, fonts.main)
  ImGui.Attach(ctx, fonts.large)
  ImGui.Attach(ctx, fonts.small)
  ImGui.Attach(ctx, fonts.small_bold)
  return fonts
end

function RCCModule.ApplyTheme(ImGui, ctx)
  local UI = require("RCCUI")
  UI.UpdateTheme(UI.C)
  UI.PushTheme(ImGui, ctx, UI.C)
  return UI
end

function RCCModule.PopTheme(ImGui, ctx)
  require("RCCUI").PopTheme(ImGui, ctx)
end

local RCC_MODULE_NAMES = {
  "RCCConfig", "RCCTheme", "RCCUI", "RCCUIUtils", "RCCUIKit", "RCCModule",
  "MonitorPanel", "MonitorManager", "MonitorMatrix", "MonitorFxChain",
  "GmemBridge", "GmemRead", "AnalyzerTap", "PostCalMeter",
  "ReferencePlayer", "ReferenceWaveform", "ReferencePanel",
  "LevelPanel", "LevelBar", "WaveformPanel", "SpectrumPanel", "SpatialPanel",
  "MonitorControlPanel", "HeadphoneCalPanel", "HeadphoneCalibrationManager",
  "MeteringSpec", "MeteringConfig",
  "RoofControlInstaller", "RoofControlManager", "UIUtils", "UIKit",
}

function RCCModule.ReloadAll()
  for _, name in ipairs(RCC_MODULE_NAMES) do
    package.loaded[name] = nil
  end
end

return RCCModule
