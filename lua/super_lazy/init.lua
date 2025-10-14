local Cache = require("super_lazy.cache")
local Config = require("super_lazy.config")
local Lockfile = require("super_lazy.lockfile")
local Source = require("super_lazy.source")
local UI = require("super_lazy.ui")
local Util = require("super_lazy.util")

local LazyConfig = require("lazy.core.config")
local LazyGit = require("lazy.manage.git")
local LazyLock = require("lazy.manage.lock")

local M = {}

function M.setup(user_config)
  Config.setup(user_config)

  if #vim.api.nvim_list_uis() == 0 then -- headless mode
    M.setup_lazy_hooks()
  else
    vim.schedule(function()
      M.setup_lazy_hooks()
    end)
  end
end

local function get_cached_git_info(plugin_dir, plugin_name)
  local cached = Cache.get_git_info(plugin_dir)
  if cached ~= nil then
    return cached
  end

  local info = LazyGit.info(plugin_dir)

  if info then
    local git_info = {
      branch = info.branch or LazyGit.get_branch({ dir = plugin_dir, name = plugin_name }),
      commit = info.commit,
    }
    Cache.set_git_info(plugin_dir, git_info)
    return git_info
  end

  Cache.set_git_info(plugin_dir, false)
  return nil
end

function M.write_lockfiles()
  local main_lockfile = LazyConfig.options.lockfile
  local existing_lockfile = Lockfile.read(main_lockfile)

  local plugins_by_source = {}

  local all_plugins = {}

  local plugin_sources = {
    LazyConfig.plugins or {},
    LazyConfig.spec.disabled or {},
    LazyConfig.spec.plugins or {},
  }

  for _, plugin_source in ipairs(plugin_sources) do
    for _, plugin in pairs(plugin_source) do
      if plugin.name and not all_plugins[plugin.name] then
        if not (plugin._ and plugin._.is_local) then
          all_plugins[plugin.name] = plugin
        end
      end
    end
  end

  for _, plugin in pairs(all_plugins) do
    local source_repo = Source.get_plugin_source(plugin.name)
    local lockfile_entry = nil

    if plugin._ and plugin._.installed then
      local git_info = get_cached_git_info(plugin.dir, plugin.name)
      if git_info then
        lockfile_entry = {
          branch = git_info.branch,
          commit = git_info.commit,
        }
      end
    else
      -- For disabled plugins, use existing lockfile entry if available
      lockfile_entry = existing_lockfile[plugin.name]
    end

    if lockfile_entry then
      if not plugins_by_source[source_repo] then
        plugins_by_source[source_repo] = {}
      end
      plugins_by_source[source_repo][plugin.name] = lockfile_entry
    end
  end

  for source_repo, plugins in pairs(plugins_by_source) do
    local lockfile_path = source_repo .. "/lazy-lock.json"
    Lockfile.write(lockfile_path, plugins)
  end
end

function M.setup_lazy_hooks()
  local ok, err = pcall(function()
    local original_update = LazyLock.update

    -- Override lazy's lockfile update function with error handling
    LazyLock.update = function()
      local original_ok, original_err = pcall(original_update)
      if not original_ok then
        Util.notify("Error in original lazy update: " .. tostring(original_err), vim.log.levels.ERROR)
        return -- Don't try our custom logic if original failed
      end

      local lockfile_ok, lockfile_err = pcall(M.write_lockfiles)
      if not lockfile_ok then
        Util.notify("Error managing lockfiles: " .. tostring(lockfile_err), vim.log.levels.ERROR)
      end
    end

    -- Also hook into the lazy TUI to show shared/personal status (with error handling)
    local ui_ok, ui_err = pcall(UI.setup_hooks)
    if not ui_ok then
      Util.notify("Error setting up UI hooks: " .. tostring(ui_err), vim.log.levels.WARN)
      -- Continue silently - original lazy UI behavior is preserved
    end
  end)

  if not ok then
    Util.notify("Failed to setup hooks: " .. tostring(err), vim.log.levels.ERROR)
    Util.notify("Falling back to default lazy.nvim behavior", vim.log.levels.WARN)
  end
end

return M
