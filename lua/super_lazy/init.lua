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

  M.setup_lazy_hooks()
  M.ensure_lockfiles_updated()
end

function M.ensure_lockfiles_updated()
  -- Write lockfiles asynchronously to handle any plugins that were installed
  -- before our hooks were set up (e.g., during initial lazy.nvim install)
  -- Scheduled to avoid blocking startup
  vim.schedule(function()
    local ok, err = pcall(M.write_lockfiles)
    if not ok then
      Util.notify("Error updating lockfiles after setup: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
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
    local source_repo, parent_plugin = Source.get_plugin_source(plugin.name, true)
    local lockfile_entry = nil

    if plugin._ and plugin._.installed then
      local git_info = get_cached_git_info(plugin.dir, plugin.name)
      if git_info then
        lockfile_entry = {
          branch = git_info.branch,
          commit = git_info.commit,
        }
        if parent_plugin then
          -- add source for nested plugins
          lockfile_entry.source = parent_plugin
        end
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

  -- Preserve nested plugins whose parent is still in the lockfile
  -- This handles the case where a recipe plugin (parent) is disabled
  for source_repo, plugins in pairs(plugins_by_source) do
    local lockfile_path = source_repo .. "/lazy-lock.json"
    local existing_repo_lockfile = Lockfile.read(lockfile_path)

    for plugin_name, plugin_entry in pairs(existing_repo_lockfile) do
      if not plugins[plugin_name] then
        if plugin_entry.source then
          if plugins[plugin_entry.source] then
            plugins[plugin_name] = plugin_entry
          end
        end
      end
    end
  end

  for source_repo, plugins in pairs(plugins_by_source) do
    local lockfile_path = source_repo .. "/lazy-lock.json"
    Lockfile.write(lockfile_path, plugins)
  end
end

-- This function restores plugins that were uninstalled and removed
-- from the lockfile but are still present in the config
function M.restore_cleaned_plugins(pre_clean_lockfiles)
  local repo_paths = Source.get_lockfile_repo_paths()

  for _, repo_path in ipairs(repo_paths) do
    local lockfile_path = repo_path .. "/lazy-lock.json"
    local current_lockfile = Lockfile.read(lockfile_path)
    local pre_clean_lockfile = pre_clean_lockfiles[repo_path] or {}

    for plugin_name, plugin_entry in pairs(pre_clean_lockfile) do
      if not current_lockfile[plugin_name] then
        local should_keep = false

        local ok, result = pcall(Source.get_plugin_source, plugin_name)
        if ok and result == repo_path then
          should_keep = true
        end

        if not should_keep and plugin_entry.source then
          if current_lockfile[plugin_entry.source] then
            should_keep = true
          end
        end

        if should_keep then
          current_lockfile[plugin_name] = plugin_entry
        end
      end
    end

    Lockfile.write(lockfile_path, current_lockfile)
  end
end

function M.setup_lazy_hooks()
  local ok, err = pcall(function()
    local original_update = LazyLock.update
    local pre_clean_lockfiles = {}

    -- Override lazy's lockfile update function with error handling
    LazyLock.update = function()
      local original_ok, original_err = pcall(original_update)
      if not original_ok then
        Util.notify("Error in lazy update: " .. tostring(original_err), vim.log.levels.ERROR)
        return -- Don't try additional lockfile handling if lazy update failed
      end

      local lockfile_ok, lockfile_err = pcall(M.write_lockfiles)
      if not lockfile_ok then
        Util.notify("Error managing lockfiles: " .. tostring(lockfile_err), vim.log.levels.ERROR)
      end

      -- After LazyLock.update completes during clean, restore entries for plugins still in config
      if next(pre_clean_lockfiles) ~= nil then
        local restore_ok, restore_err = pcall(M.restore_cleaned_plugins, pre_clean_lockfiles)
        if not restore_ok then
          Util.notify("Error restoring cleaned plugins: " .. tostring(restore_err), vim.log.levels.ERROR)
        end
        pre_clean_lockfiles = {} -- Clear the state
      end
    end

    -- Hook into clean operations to capture lockfile state before clean
    vim.api.nvim_create_autocmd("User", {
      pattern = "LazyCleanPre",
      callback = function()
        -- Capture lockfile state before clean
        pre_clean_lockfiles = {}
        local repo_paths_ok, repo_paths = pcall(Source.get_lockfile_repo_paths)
        if repo_paths_ok then
          for _, repo_path in ipairs(repo_paths) do
            local lockfile_path = repo_path .. "/lazy-lock.json"
            pre_clean_lockfiles[repo_path] = Lockfile.read(lockfile_path)
          end
        end
      end,
    })

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
