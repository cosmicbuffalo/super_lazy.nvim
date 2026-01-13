local Config = require("super_lazy.config")
local Ops = require("super_lazy.ops")
local Source = require("super_lazy.source")
local Util = require("super_lazy.util")

local LazyConfig = require("lazy.core.config")

local M = {}

-- Check if main lockfile is newer than our split lockfiles
-- This detects when lazy.nvim updated the main lockfile
-- before our hooks were set up
local function needs_lockfile_sync()
  local main_lockfile = LazyConfig.options.lockfile
  local main_stat = vim.loop.fs_stat(main_lockfile)

  -- If main lockfile doesn't exist, nothing to sync
  if not main_stat then
    return false
  end

  -- Check if main lockfile has uncommitted changes
  -- This will catch lazy making updates to the main lockfile even if split lockfiles don't exist
  local lockfile_dir = vim.fn.fnamemodify(main_lockfile, ":h")
  local git_check = vim.fn.system({ "git", "-C", lockfile_dir, "rev-parse", "--git-dir" })
  if vim.v.shell_error == 0 then
    local git_diff = vim.fn.system({ "git", "-C", lockfile_dir, "diff", "--quiet", "HEAD", main_lockfile })
    if vim.v.shell_error ~= 0 then
      return true
    end
  end

  local main_mtime = main_stat.mtime.sec

  -- Check each of our split lockfiles
  local repo_paths = Source.get_lockfile_repo_paths()
  for _, repo_path in ipairs(repo_paths) do
    local lockfile_path = repo_path .. "/lazy-lock.json"
    local stat = vim.loop.fs_stat(lockfile_path)

    -- If our lockfile doesn't exist, we need to sync
    if not stat then
      return true
    end

    -- If main lockfile is newer than our lockfile, we need to sync
    if main_mtime > stat.mtime.sec then
      return true
    end
  end

  -- All lockfiles are in sync
  return false
end

local function setup_user_commands()
  local function get_plugin_names_completion()
    local ok, lazy = pcall(require, "lazy")
    if not ok then
      return {}
    end
    local plugins = lazy.plugins()
    local names = {}
    for _, plugin in ipairs(plugins) do
      table.insert(names, plugin.name)
    end
    table.sort(names)
    return names
  end

  local function parse_plugin_names(args)
    local plugin_names = {}
    if args ~= "" then
      for name in args:gmatch("%S+") do
        table.insert(plugin_names, name)
      end
    end
    return plugin_names
  end

  vim.api.nvim_create_user_command("SuperLazyRefresh", function(opts)
    local plugin_names = parse_plugin_names(opts.args)
    M.refresh(plugin_names)
  end, {
    nargs = "*",
    force = true,
    complete = get_plugin_names_completion,
  })

  vim.api.nvim_create_user_command("SuperLazyDebug", function(opts)
    local plugin_name = opts.args
    if plugin_name == "" then
      local idx = Source.get_index()
      if not idx then
        Util.notify("No index built yet. Run :SuperLazyRefresh first.", vim.log.levels.WARN)
        return
      end
      local count = 0
      for _ in pairs(idx) do
        count = count + 1
      end
      Util.notify("Index contains " .. count .. " plugins")
      local repo_paths = Source.get_lockfile_repo_paths()
      for i, path in ipairs(repo_paths) do
        Util.notify("Repo " .. i .. ": " .. path)
      end
    else
      local idx = Source.get_index()

      local lines = { "Plugin: " .. plugin_name }
      if idx and idx[plugin_name] then
        local entry = idx[plugin_name]
        table.insert(lines, "  Index: repo=" .. (entry.repo or "nil") .. ", parent=" .. (entry.parent or "nil"))
      else
        table.insert(lines, "  Index: (not in index)")
      end

      for _, line in ipairs(lines) do
        print(line)
      end
    end
  end, {
    nargs = "?",
    force = true,
    complete = get_plugin_names_completion,
  })
end

function M.setup(user_config)
  Config.setup(user_config)

  Ops.setup_lazy_hooks()
  setup_user_commands()

  -- Check if lazy.nvim updated the main lockfile before our hooks were set up
  -- (e.g., during bootstrap/initial install). Only sync if timestamps indicate it's needed.
  if needs_lockfile_sync() then
    Ops.write_lockfiles()
  end
end

M.refresh = Ops.refresh

return M
