local GmemBridge = {}

local AnalyzerTap = require("AnalyzerTap")
local ReferencePlayer = require("ReferencePlayer")
local GmemRead = require("GmemRead")

function GmemBridge.InstallAnalyzerTap()
  return AnalyzerTap.Install()
end

function GmemBridge.InstallRefPlayer()
  return ReferencePlayer.Install()
end

function GmemBridge.ReadAnalyzer()
  return GmemRead.ReadAnalyzer()
end

return GmemBridge
