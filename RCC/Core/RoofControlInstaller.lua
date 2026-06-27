local RoofControlInstaller = {}

local sep = package.config:sub(1, 1)

local function PathJoin(...)
  local parts = {...}
  local result = ""
  for i, part in ipairs(parts) do
    if part ~= "" then
      if result == "" then
        result = part
      else
        local ends_with_sep = result:sub(-1) == sep
        local starts_with_sep = part:sub(1, 1) == sep
        if ends_with_sep and starts_with_sep then
          result = result .. part:sub(2)
        elseif not ends_with_sep and not starts_with_sep then
          result = result .. sep .. part
        else
          result = result .. part
        end
      end
    end
  end
  return result
end

local function FileExists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local function CopyFile(src, dst)
  local infile = io.open(src, "rb")
  if not infile then return false, "Cannot open source file: " .. src end
  
  local src_data = infile:read("*a")
  infile:close()

  local existing = io.open(dst, "rb")
  if existing then
    local dst_data = existing:read("*a")
    existing:close()
    if dst_data == src_data then
      return true
    end
  end

  local outfile = io.open(dst, "wb")
  if not outfile then
    return false, "Cannot open destination file: " .. dst
  end
  
  outfile:write(src_data)
  outfile:close()
  return true
end

-- Full list of roof_control files to install dynamically
local INSTALL_MANIFEST = {
  effects = {
    src_sub = PathJoin("Effects", "roof_control"),
    dst_sub = PathJoin("Effects", "roof_control"),
    files = {
      "roof_control"
    }
  },
  icons = {
    src_sub = PathJoin("Data", "toolbar_icons"),
    dst_sub = PathJoin("Data", "toolbar_icons"),
    files = {
      "toolbar_roof_control_cube.png",
      "toolbar_roof_control_full.png",
      "toolbar_roof_control_main.png",
      "toolbar_roof_control_slew.png",
      "toolbar_roof_control_smartphone.png",
      "toolbar_roof_control_sub.png",
      "toolbar_roof_control_vinyl.png"
    }
  },
  gui = {
    src_sub = PathJoin("Data", "roof_control", "gui"),
    dst_sub = PathJoin("Data", "roof_control", "gui"),
    files = {
      "background.png",
      "background_dark.png",
      "bypass.png",
      "bypass_select.png",
      "config.png",
      "cubes.png",
      "cubes_on.png",
      "fullrange.png",
      "fullrange_on.png",
      "fullrange_select.png",
      "main.png",
      "main_on.png",
      "slew.png",
      "slew_on.png",
      "smartphone.png",
      "smartphone_on.png",
      "sub.png",
      "sub_on.png",
      "vinyl.png",
      "vinyl_on.png"
    }
  },
  hp_db = {
    src_sub = PathJoin("Data", "roof_control"),
    dst_sub = PathJoin("Data", "roof_control"),
    files = {
      "hp.db"
    }
  },
  phones_eq = {
    src_sub = PathJoin("Data", "roof_control", "phones_eq"),
    dst_sub = PathJoin("Data", "roof_control", "phones_eq"),
    files = {}
  },
  scripts = {
    src_sub = PathJoin("Scripts", "roof_control"),
    dst_sub = PathJoin("Scripts", "roof_control"),
    files = {
      "roof_bubrik.lua",
      "roof_control_bypass.lua",
      "roof_control_cubes.lua",
      "roof_control_enable.lua",
      "roof_control_fullrange.lua",
      "roof_control_main.lua",
      "roof_control_slew.lua",
      "roof_control_smartphone.lua",
      "roof_control_subwoofer.lua",
      "roof_control_vinyl.lua"
    }
  }
}

function RoofControlInstaller.IsInstalled()
  local res_path = reaper.GetResourcePath()
  local jsfx_path = PathJoin(res_path, "Effects", "roof_control", "roof_control")
  local bubrik_path = PathJoin(res_path, "Scripts", "roof_control", "roof_bubrik.lua")
  
  return FileExists(jsfx_path) and FileExists(bubrik_path)
end

function RoofControlInstaller.Install()
  local rcc_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
  -- RCC/Core/.. to RCC/ThirdParty/roof_control
  local src_root = PathJoin(rcc_path, "..", "ThirdParty", "roof_control")
  local dst_root = reaper.GetResourcePath()

  -- 1. Create target directories in REAPER resources
  reaper.RecursiveCreateDirectory(PathJoin(dst_root, "Effects", "roof_control"), 0)
  reaper.RecursiveCreateDirectory(PathJoin(dst_root, "Data", "roof_control", "gui"), 0)
  reaper.RecursiveCreateDirectory(PathJoin(dst_root, "Data", "roof_control", "phones_eq"), 0)
  reaper.RecursiveCreateDirectory(PathJoin(dst_root, "Data", "toolbar_icons"), 0)
  reaper.RecursiveCreateDirectory(PathJoin(dst_root, "Scripts", "roof_control"), 0)

  -- 2. Recursive file copying based on manifest
  for section_name, manifest in pairs(INSTALL_MANIFEST) do
    local src_dir = PathJoin(src_root, manifest.src_sub)
    local dst_dir = PathJoin(dst_root, manifest.dst_sub)
    
    for _, file_name in ipairs(manifest.files) do
      local src_file = PathJoin(src_dir, file_name)
      local dst_file = PathJoin(dst_dir, file_name)
      
      if section_name ~= "hp_db" or not FileExists(dst_file) then
        local ok, err = CopyFile(src_file, dst_file)
        if not ok then
          return false, "Failed to copy " .. file_name .. ": " .. tostring(err)
        end
      end
    end
  end

  -- 3. Register scripts in REAPER Action List
  local scripts_manifest = INSTALL_MANIFEST.scripts
  local dst_scripts_dir = PathJoin(dst_root, scripts_manifest.dst_sub)
  
  for _, file_name in ipairs(scripts_manifest.files) do
    local script_path = PathJoin(dst_scripts_dir, file_name)
    -- Add to REAPER Actions List (0 = Main Section)
    reaper.AddRemoveReaScript(true, 0, script_path, true)
  end

  return true
end

function RoofControlInstaller.RunBackend()
  local dst_root = reaper.GetResourcePath()
  local bubrik_path = PathJoin(dst_root, "Scripts", "roof_control", "roof_bubrik.lua")
  
  if FileExists(bubrik_path) then
    -- Register to get command ID
    local cmd_id = reaper.AddRemoveReaScript(true, 0, bubrik_path, true)
    if cmd_id and cmd_id > 0 then
      -- Run script (0 = Main section)
      reaper.Main_OnCommand(cmd_id, 0)
      return true
    end
  end
  return false
end

return RoofControlInstaller
