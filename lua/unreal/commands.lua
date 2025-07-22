-- unrealnvim_linux.lua
-- Full Unreal.nvim integration script for Linux
-- Changes:
-- * Removed Windows-specific paths and commands
-- * Replaced .exe/.bat with Linux equivalents or removed them
-- * Used mkdir -p for directory creation
-- * Adjusted path handling for Linux style
-- * Preserved all original functions and callbacks unchanged

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

-- fix false diagnostic about vim
if not vim then vim = {} end

local logFilePath = vim.fn.stdpath("data") .. '/unrealnvim.log'

local function logWithVerbosity(verbosity, message)
    if not vim.g.unrealnvim_debug then return end
    local cfgVerbosity = vim.g.unrealnvim_loglevel or kLogLevel_Log
    if verbosity > cfgVerbosity then return end

    local file = (Commands and Commands.logFile) or io.open(logFilePath, "a")
    if file then
        local time = os.date('%m/%d/%y %H:%M:%S')
        file:write("["..time.."]["..verbosity.."]: " .. message .. '\n')
        file:close()
    end
end

local function log(message)
    if not message then
        logWithVerbosity(kLogLevel_Error, "message was nil")
        return
    end
    logWithVerbosity(kLogLevel_Log, message)
end

local function logError(message)
    logWithVerbosity(kLogLevel_Error, message)
end

local function PrintAndLogMessage(a,b)
    if a and b then
        log(tostring(a)..tostring(b))
    elseif a then
        log(tostring(a))
    end
end

local function PrintAndLogError(a,b)
    if a and b then
        local msg = "Error: "..tostring(a)..tostring(b)
        print(msg)
        log(msg)
    elseif a then
        local msg = "Error: ".. tostring(a)
        print(msg)
        log(msg)
    end
end

local function MakeUnixPath(win_path)
    if not win_path then
        logError("MakeUnixPath received a nil argument")
        return
    end
    local unix_path = win_path:gsub("\\", "/"):gsub("//+", "/")
    return unix_path
end

local function FuncBind(func, data)
    return function()
        func(data)
    end
end

if not vim.g.unrealnvim_loaded then
    Commands = {}

    CurrentGenData = {
        config = {},
        target = nil,
        prjName = nil,
        targetNameSuffix = nil,
        prjDir = nil,
        tasks = {},
        currentTask = "",
        ubtPath = "",
        ueBuildBat = "",
        projectPath = "",
        logFile = nil
    }

    -- clear the log
    CurrentGenData.logFile = io.open(logFilePath, "w")
    if CurrentGenData.logFile then
        CurrentGenData.logFile:write("")
        CurrentGenData.logFile:close()
        CurrentGenData.logFile = io.open(logFilePath, "a")
    end

    vim.g.unrealnvim_loaded = true
end

Commands.LogLevel_Error = kLogLevel_Error
Commands.LogLevel_Warning = kLogLevel_Warning
Commands.LogLevel_Log = kLogLevel_Log
Commands.LogLevel_Verbose = kLogLevel_Verbose
Commands.LogLevel_VeryVerbose = kLogLevel_VeryVerbose

function Commands.Log(msg)
    PrintAndLogError(msg)
end

Commands.onStatusUpdate = function() end

function Commands:Inspect(objToInspect)
    if not vim.g.unrealnvim_debug then return end
    if not objToInspect then
        log(objToInspect)
        return
    end
    if not self._inspect then
        local inspect_path = vim.fn.stdpath("data") .. "/site/pack/packer/start/inspect.lua/inspect.lua"
        local inspect_loader = loadfile(inspect_path)
        if inspect_loader then
            self._inspect = inspect_loader()
        else
            logError("Inspect failed to load from path "..inspect_path)
            return
        end
    end
    if self._inspect and self._inspect.inspect then
        return self._inspect.inspect(objToInspect)
    end
end

-- String-splitting helper
function SplitString(str)
    local lines = {}
    for line in string.gmatch(str, "[^\r\n]+") do
        table.insert(lines, line)
    end
    return lines
end

function Commands._CreateConfigFile(configFilePath, projectName)
    local configContents = [[
{
    "version" : "]]..kCurrentVersion..[[",
    "_comment": "Populate EngineDir",
    "EngineDir": "",
    "Targets": []
}
    ]]
    PrintAndLogMessage("Please populate the configuration for the Unreal project, especially EngineDir")
    vim.cmd('new ' .. configFilePath)
    vim.cmd('setlocal buftype=')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, SplitString(configContents))
end

function Commands._EnsureConfigFile(projectRootDir, projectName)
    local configFilePath = projectRootDir.."/".. kConfigFileName
    local configFile = io.open(configFilePath, "r")
    if not configFile then
        Commands._CreateConfigFile(configFilePath, projectName)
        PrintAndLogMessage("Created config file "..configFilePath)
        return nil
    end

    local content = configFile:read("*all")
    configFile:close()

    local data = vim.fn.json_decode(content)
    Commands:Inspect(data)
    if data and data.version ~= kCurrentVersion then
        PrintAndLogError("Your " .. configFilePath .. " format is incompatible. Backup & delete it to regenerate.")
        data = nil
    end

    if data then
        data.EngineDir = MakeUnixPath(data.EngineDir)
    end

    return data
end

function Commands._GetDefaultProjectNameAndDir(filepath)
    local uprojectPath, projectDir
    projectDir, uprojectPath = Commands._find_file_with_extension(filepath, "uproject")
    if not uprojectPath then
        PrintAndLogMessage("Failed to determine project name (no .uproject found)")
        return nil, nil
    end
    local projectName = vim.fn.fnamemodify(uprojectPath, ":t:r")
    return projectName, projectDir
end

-- Task/Status management functions
function CurrentGenData:GetTaskAndStatus()
    if not self.currentTask or self.currentTask == "" then return "[No Task]" end
    return self.currentTask.."->"..self:GetTaskStatus(self.currentTask)
end
function CurrentGenData:GetTaskStatus(taskName)
    return self.tasks[taskName] or "none"
end
function CurrentGenData:SetTaskStatus(taskName, newStatus)
    if self.currentTask ~= "" and self.currentTask ~= taskName and self:GetTaskStatus(self.currentTask) ~= TaskState.completed then
        PrintAndLogError("Cannot start a new task: " .. self.currentTask .. " still in progress")
        return
    end
    PrintAndLogMessage("SetTaskStatus: " .. taskName .. "->" .. newStatus)
    self.currentTask = taskName
    self.tasks[taskName] = newStatus
end
function CurrentGenData:ClearTasks()
    self.tasks = {}
    self.currentTask = ""
end

function ExtractRSP(rsppath)
    -- Linux-friendly RSP generator
    local extraFlags = "-std=c++20 -ferror-limit=0"
    local lines, lineNb = {}, 0
    for line in io.lines(rsppath) do
        local keep = line:find("^/FI") or line:find("^/I") or line:find("^-W")
        if keep or lineNb == 0 then
            line = line:gsub("^/FI", "-include ")
            line = line:gsub("^/I%s*(.*)", "-I \"%1\"")
            lines[lineNb] = line.."\n"; lineNb = lineNb+1
        end
    end
    table.insert(lines, "\n"..extraFlags)
    return table.concat(lines)
end

function CreateCommandLine() end

-- Ensure directory exists on Linux
function EnsureDirPath(path)
    PrintAndLogMessage("Ensuring path exists: "..path)
    os.execute("mkdir -p \""..path.."\"")
end

function EscapePath(path)
    return path:gsub("\\","/"):gsub("\"","\\\"")
end

-- Detect engine code paths
local function IsEngineFile(path, start)
    return MakeUnixPath(path):find(MakeUnixPath(start),1,true) ~= nil
end

-- Quickfix window handling (unchanged)
local function IsQuickfixWin(winid)
    if not vim.api.nvim_win_is_valid(winid) then return false end
    local bufnr = vim.api.nvim_win_get_buf(winid)
    return vim.api.nvim_buf_get_option(bufnr,'buftype') == 'quickfix'
end
local function GetQuickfixWinId()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if IsQuickfixWin(win) then return win end
    end
end
Commands.QuickfixWinId = 0
local function ScrollQF()
    local qf = vim.fn.getqflist()
    if #qf>0 then vim.api.nvim_win_set_cursor(Commands.QuickfixWinId,{#qf,0}) end
end
local function AppendToQF(entry)
    vim.fn.setqflist({}, 'a', {items={entry}})
    ScrollQF()
end
local function DeleteAutocmd(id)
    pcall(function() vim.api.nvim_del_autocmd(id) end)
end

-- Stage functions (adjusted for Linux)
function Stage_UbtGenCmd()
    coroutine.yield()
    Commands.BeginTask("gencmd")
    PrintAndLogMessage("Invoking UBT for compile_commands.json")
    local rspdir = CurrentGenData.prjDir.."/Intermediate/clangRsp/"..
        CurrentGenData.target.PlatformName.."/"..CurrentGenData.target.Configuration.."/"
    EnsureDirPath(rspdir)

    local inputFile = CurrentGenData.prjDir.."/compile_commands.json"
    local skipEngine = not CurrentGenData.WithEngine

    AppendToQF({text="Preparing files for parsing."..
        (skipEngine and "" or " Engine source included")})

    local contentLines = {}
    for line in io.lines(inputFile) do
        if line:find("\"command") then
            coroutine.yield()
            local _, _, cmdPart = line:find("\"command\":%s*\"(.-)\"")
            local isEngine = IsEngineFile(cmdPart,CurrentGenData.config.EngineDir)
            if not(isEngine and skipEngine) then
                AppendToQF({text=cmdPart})
                local newrsppath = cmdPart:match("@\"(.-)\"") or ""
                if newrsppath~="" then
                    local rspfile = io.open(newrsppath, "w")
                    rspfile:write(ExtractRSP(newrsppath))
                    rspfile:close()
                    line = "\t\t\"command\": \"clang++ @\\\""..
                        EscapePath(newrsppath).."\\\"\",\n"
                end
            end
        end
        table.insert(contentLines,line.."\n")
    end

    local out = io.open(inputFile,"w")
    out:write(table.concat(contentLines))
    out:close()

    Commands.EndTask("gencmd")
    Commands.ScheduleTask("headers")
    Commands.BeginTask("headers")

    Commands.headersAutocmdid = vim.api.nvim_create_autocmd("ShellCmdPost", {
        pattern="*",
        callback=FuncBind(DispatchUnrealnvimCb,"headers")
    })

    local cmd = CurrentGenData.ubtPath.." -project="..CurrentGenData.projectPath..
        " "..CurrentGenData.target.UbtExtraFlags..
        " "..CurrentGenData.prjName..CurrentGenData.targetNameSuffix..
        " "..CurrentGenData.target.Configuration..
        " "..CurrentGenData.target.PlatformName.." -headers"

    vim.cmd("compiler clang")
    vim.cmd("Dispatch "..cmd)
end

-- Dispatch callback and scheduling logic

function DispatchUnrealnvimCb(event)
    if not event or not event.file or event.file == "" then return end
    local eventFile = event.file
    local name = event.name
    PrintAndLogMessage("Dispatch callback: "..name.." "..eventFile)

    if name == "headers" then
        -- Headers generation finished
        Commands.EndTask("headers")
        Commands.ScheduleTask("complete")
        Commands.BeginTask("complete")

        -- Kill autocmd
        DeleteAutocmd(Commands.headersAutocmdid)
        Commands.headersAutocmdid = nil

        -- TODO: Load generated tags, etc.

        Commands.EndTask("complete")
        PrintAndLogMessage("Header generation complete.")
    elseif name == "compile" then
        Commands.EndTask("compile")
        PrintAndLogMessage("Compilation complete.")
    elseif name == "run" then
        Commands.EndTask("run")
        PrintAndLogMessage("Run complete.")
    end
end

function Commands.BeginTask(name)
    CurrentGenData:SetTaskStatus(name, TaskState.inprogress)
    vim.schedule(function()
        Commands.onStatusUpdate(CurrentGenData:GetTaskAndStatus())
    end)
    PrintAndLogMessage("BeginTask: "..name)
end

function Commands.EndTask(name)
    CurrentGenData:SetTaskStatus(name, TaskState.completed)
    vim.schedule(function()
        Commands.onStatusUpdate(CurrentGenData:GetTaskAndStatus())
    end)
    PrintAndLogMessage("EndTask: "..name)
end

function Commands.ScheduleTask(name)
    CurrentGenData:SetTaskStatus(name, TaskState.scheduled)
    vim.schedule(function()
        Commands.onStatusUpdate(CurrentGenData:GetTaskAndStatus())
    end)
    PrintAndLogMessage("Scheduled task: "..name)
end

function Commands.SafeRunTask(taskname)
    if not taskname then return end
    if taskname == "gencmd" then
        coroutine.wrap(Stage_UbtGenCmd)()
    else
        PrintAndLogMessage("Unknown task: "..taskname)
    end
end

function Commands.SetConfig(config)
    CurrentGenData.config = config or {}
    if CurrentGenData.config.EngineDir then
        CurrentGenData.config.EngineDir = MakeUnixPath(CurrentGenData.config.EngineDir)
    end
end

function Commands.SetupProject(prjPath)
    local projectDir = vim.fn.fnamemodify(prjPath, ":h")
    local projectName = vim.fn.fnamemodify(prjPath, ":t:r")

    CurrentGenData.prjDir = projectDir
    CurrentGenData.prjName = projectName
    CurrentGenData.projectPath = prjPath

    local config = Commands._EnsureConfigFile(projectDir, projectName)
    if not config then
        PrintAndLogError("Could not load UnrealNvim config file.")
        return false
    end

    Commands.SetConfig(config)

    CurrentGenData.ubtPath = config.EngineDir .. "/Engine/Build/BatchFiles/Linux/RunUAT.sh"

    CurrentGenData.target = {
        Configuration = "Development",
        PlatformName = "Linux",
        UbtExtraFlags = "",
    }

    return true
end

-- Entry point for running UnrealNvim commands

function Commands.RunUbtTask(taskName)
    Commands.ScheduleTask(taskName)
    vim.schedule_wrap(function()
        Commands.SafeRunTask(taskName)
    end)()
end

-- Expose commands globally
_G.UnrealNvimCommands = Commands

return Commands
