local kConfigFileName = "UnrealNvim.json"
local kCurrentVersion = "0.0.2"

local kLogLevel_Error = 1
local kLogLevel_Warning = 2
local kLogLevel_Log = 3
local kLogLevel_Verbose = 4
local kLogLevel_VeryVerbose = 5

local TaskState = {
    scheduled = "scheduled",
    inprogress = "inprogress",
    completed = "completed"
}

if not vim then vim = {} end

local logFilePath = vim.fn.stdpath("data") .. '/unrealnvim.log'

local function logWithVerbosity(verbosity, message)
    if not vim.g.unrealnvim_debug then return end
    local cfgVerbosity = vim.g.unrealnvim_loglevel or kLogLevel_Log
    if verbosity > cfgVerbosity then return end

    local file = Commands and Commands.logFile or io.open(logFilePath, "a")
    if file then
        local time = os.date('%m/%d/%y %H:%M:%S')
        file:write("[" .. time .. "][" .. verbosity .. "]: " .. message .. '\n')
    end
end

local function log(msg) 
  if msg then 
    logWithVerbosity(kLogLevel_Log, msg) 
  end 
end

local function logError(msg) 
  logWithVerbosity(kLogLevel_Error, msg) 
end

local function MakeUnixPath(path)
    return path and path:gsub("\\", "/"):gsub("//+", "/")
end

local function FuncBind(func, data)
    return 
      function() 
        func(data) 
      end
end

if not vim.g.unrealnvim_loaded then
    Commands = {}
    CurrentGenData = {
        config = {}, target = nil, prjName = nil,
        targetNameSuffix = nil, prjDir = nil, tasks = {},
        currentTask = "", ubtPath = "",
        ueBuildBat = "", projectPath = "", logFile = nil
    }

    CurrentGenData.logFile = io.open(logFilePath, "w")
    if CurrentGenData.logFile then
        CurrentGenData.logFile:write("")
        CurrentGenData.logFile:close()
        CurrentGenData.logFile = io.open(logFilePath, "a")
    end

    vim.g.unrealnvim_loaded = true
end

function EnsureDirPath(path)
    PrintAndLogMessage("Ensuring path exists: " .. path)
    os.execute("mkdir -p \"" .. path .. "\"")
end

function EscapePath(path)
    return path:gsub("\\", "/"):gsub("\"", "\\\"")
end

function Commands.BuildCoroutine()
    Commands.buildAutocmdid = vim.api.nvim_create_autocmd("ShellCmdPost", {
        pattern = "*",
        callback = BuildComplete
    })

    local cmd = CurrentGenData.ueBuildBat .. " " ..
        CurrentGenData.prjName .. CurrentGenData.targetNameSuffix .. " " ..
        CurrentGenData.target.PlatformName .. " " ..
        CurrentGenData.target.Configuration .. " " ..
        CurrentGenData.projectPath .. " -waitmutex"

    vim.cmd("Dispatch " .. cmd)
end

function Commands.run(opts)
    CurrentGenData:ClearTasks()
    PrintAndLogMessage("Running uproject")

    if not InitializeCurrentGenData() then 
      return 
    end

    Commands.ScheduleTask("run")

    local cmd = ""
    if CurrentGenData.target.withEditor then
        local editorSuffix = ""
        if CurrentGenData.target.Configuration ~= "Development" then
            editorSuffix = "-" .. CurrentGenData.target.PlatformName .. "-" .. CurrentGenData.target.Configuration
        end

        local executablePath = CurrentGenData.config.EngineDir .. "/Engine/Binaries/" ..
            CurrentGenData.target.PlatformName .. "/UnrealEditor" .. editorSuffix

        cmd = executablePath .. " " .. CurrentGenData.projectPath .. " -skipcompile"
    else
      PrintAndLogMessage("Using engine at:" .. CurrentGenData.config.EngineDir)
    end
    return true
end

return Commands
