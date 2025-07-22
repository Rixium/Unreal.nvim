local uv = vim.loop
local M = {}

-- Utility: Run a command asynchronously and capture output
local function run_command(cmd, args, on_exit)
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  local handle

  handle = uv.spawn(cmd, {
    args = args,
    stdio = {nil, stdout, stderr},
  },
  function(code, signal)
    stdout:close()
    stderr:close()
    handle:close()
    if on_exit then on_exit(code, signal) end
  end)

  stdout:read_start(function(err, data)
    assert(not err, err)
    if data then
      vim.schedule(function()
        vim.api.nvim_out_write(data)
      end)
    end
  end)

  stderr:read_start(function(err, data)
    assert(not err, err)
    if data then
      vim.schedule(function()
        vim.api.nvim_err_writeln(data)
      end)
    end
  end)
end

-- Returns Unreal project root directory by locating *.uproject upwards
function M.find_project_root()
  local cwd = vim.fn.getcwd()
  local dir = cwd

  while dir and dir ~= "/" do
    local files = vim.fn.globpath(dir, "*.uproject", 0, 1)
    if #files > 0 then
      return dir
    end
    dir = vim.fn.fnamemodify(dir, ":h")
  end

  return nil
end

-- Linux: Use ./GenerateProjectFiles.sh
function M.generate_project_files()
  local root = M.find_project_root()
  if not root then
    vim.api.nvim_err_writeln("Unreal project root not found.")
    return
  end

  local script_path = root .. "/GenerateProjectFiles.sh"
  if vim.fn.filereadable(script_path) == 0 then
    vim.api.nvim_err_writeln("GenerateProjectFiles.sh not found in project root.")
    return
  end

  vim.api.nvim_out_write("Generating project files...\n")
  run_command(script_path, {}, function(code)
    if code == 0 then
      vim.api.nvim_out_write("Project files generated successfully.\n")
    else
      vim.api.nvim_err_writeln("Failed to generate project files.")
    end
  end)
end

-- Linux: Use make or ninja for building instead of MSBuild.exe
function M.build()
  local root = M.find_project_root()
  if not root then
    vim.api.nvim_err_writeln("Unreal project root not found.")
    return
  end

  local build_dir = root .. "/Intermediate/Build/Linux"
  if vim.fn.isdirectory(build_dir) == 0 then
    vim.api.nvim_err_writeln("Build directory does not exist. Run generate_project_files first.")
    return
  end

  -- Build command - adjust if your project uses ninja or makefiles
  local build_cmd = "make"
  local args = {}

  vim.api.nvim_out_write("Building project using 'make'...\n")
  run_command(build_cmd, args, function(code)
    if code == 0 then
      vim.api.nvim_out_write("Build succeeded.\n")
    else
      vim.api.nvim_err_writeln("Build failed.")
    end
  end)
end

-- Linux: Run the game binary from Binaries/Linux/
function M.run_game()
  local root = M.find_project_root()
  if not root then
    vim.api.nvim_err_writeln("Unreal project root not found.")
    return
  end

  local project_name = nil
  local uproject_files = vim.fn.globpath(root, "*.uproject", 0, 1)
  if #uproject_files > 0 then
    project_name = vim.fn.fnamemodify(uproject_files[1], ":t:r")
  else
    vim.api.nvim_err_writeln("Could not determine project name.")
    return
  end

  local binary_path = string.format("%s/Binaries/Linux/%s", root, project_name)
  if vim.fn.executable(binary_path) == 0 then
    vim.api.nvim_err_writeln("Game binary not found or not executable: " .. binary_path)
    return
  end

  vim.api.nvim_out_write("Running game: " .. binary_path .. "\n")
  run_command(binary_path, {}, function(code)
    vim.api.nvim_out_write("Game process exited with code: " .. code .. "\n")
  end)
end

-- Register Neovim commands
function M.setup_commands()
  vim.api.nvim_create_user_command("UnrealGenerateProjectFiles", M.generate_project_files, {})
  vim.api.nvim_create_user_command("UnrealBuild", M.build, {})
  vim.api.nvim_create_user_command("UnrealRunGame", M.run_game, {})
end

return M

