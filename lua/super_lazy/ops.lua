local Lockfile = require("super_lazy.lockfile")
local Source = require("super_lazy.source")
local UI = require("super_lazy.ui")
local Util = require("super_lazy.util")

local LazyConfig = require("lazy.core.config")
local LazyLock = require("lazy.manage.lock")

local M = {}

local function finalize_lockfiles(results, existing_lockfile, original_lockfile)
  local plugins_by_source = {}

  for plugin_name, result in pairs(results) do
    if result.entry then
      if not plugins_by_source[result.repo] then
        plugins_by_source[result.repo] = {}
      end
      plugins_by_source[result.repo][plugin_name] = result.entry
    end
  end

  -- Preserve nested plugins whos parent is still in the lockfile
  for source_repo, plugins in pairs(plugins_by_source) do
    local lockfile_path = source_repo .. "/lazy-lock.json"
    local existing_repo_lockfile = Lockfile.read(lockfile_path)

    for plugin_name, plugin_entry in pairs(existing_repo_lockfile) do
      if not plugins[plugin_name] and plugin_entry.source and plugins[plugin_entry.source] then
        plugins[plugin_name] = plugin_entry
      end
    end
  end

  -- Restore entries from original lockfile (git HEAD) for plugins from disabled parents' lazy.lua files
  if original_lockfile then
    for plugin_name, lock_entry in pairs(original_lockfile) do
      if lock_entry.source then
        local parent_plugin = lock_entry.source

        for source_repo, plugins in pairs(plugins_by_source) do
          if plugins[parent_plugin] and not plugins[plugin_name] then
            plugins[plugin_name] = lock_entry
            break
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

-- opts = {
--   on_complete = function(),  -- Called when all done (optional)
--   on_cancel = function(),    -- Called if cancelled (optional)
--   silent = bool,             -- If true, suppress progress notifications (optional)
-- }
function M.write_lockfiles(opts)
  local on_complete, on_cancel, silent
  if type(opts) == "function" then
    on_complete = opts
    on_cancel = nil
    silent = false
  elseif type(opts) == "table" then
    on_complete = opts.on_complete
    on_cancel = opts.on_cancel
    silent = opts.silent or false
  else
    on_complete = nil
    on_cancel = nil
    silent = false
  end

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

  local main_lockfile = LazyConfig.options.lockfile
  local existing_lockfile = Lockfile.read(main_lockfile)
  local original_lockfile = Lockfile.get_cached()

  local progress = nil
  if not silent then
    local ok, fidget = pcall(require, "fidget")
    if ok and fidget.progress and fidget.progress.handle then
      progress = fidget.progress.handle.create({
        title = "Lockfile Sync",
        message = "Scanning plugins...",
        lsp_client = { name = "super_lazy.nvim" },
        percentage = 0,
      })
    else
      Util.notify("Syncing lockfiles...")
    end
  end

  -- Progress animation queue - shows each update for a minimum duration
  local progress_queue = {}
  local is_animating = false
  local work_complete = false
  local pending_finish_callback = nil
  local UPDATE_INTERVAL_MS = 100

  local function process_progress_queue()
    if #progress_queue == 0 then
      is_animating = false
      -- Work finished and queue is empty - call the finish callback
      if work_complete and pending_finish_callback then
        pending_finish_callback()
        pending_finish_callback = nil
      end
      return
    end

    local update = table.remove(progress_queue, 1)
    if progress then
      progress:report({ message = update.message, percentage = update.pct })
    end

    vim.defer_fn(process_progress_queue, UPDATE_INTERVAL_MS)
  end

  local function queue_progress_update(pct, message)
    table.insert(progress_queue, { pct = pct, message = message })
    if not is_animating then
      is_animating = true
      process_progress_queue()
    end
  end

  local function on_index_progress(current, total, message)
    if progress and total > 0 then
      local pct = math.floor((current / total) * 100)
      queue_progress_update(pct, message)
    end
  end

  local function finish_with_animation(finish_callback)
    -- Queue the final 100% update
    queue_progress_update(100, "Writing lockfiles...")
    work_complete = true
    pending_finish_callback = finish_callback
    -- If not currently animating, start processing (will call finish_callback when done)
    if not is_animating and pending_finish_callback then
      pending_finish_callback()
      pending_finish_callback = nil
    end
  end

  Source.build_index(function(index)
    local function do_post_index_work()
      local results = {}
      for _, plugin in pairs(all_plugins) do
        local source_repo, parent_plugin, err = Source.get_plugin_source(plugin.name, true)

        if not err then
          local entry = nil
          if plugin._ and plugin._.installed then
            local git_info = Source.get_git_info(plugin)
            if git_info then
              entry = {
                branch = git_info.branch,
                commit = git_info.commit,
              }
              if parent_plugin then
                entry.source = parent_plugin
              end
            end
          else
            -- For disabled/uninstalled plugins, try to restore from existing lockfile or git HEAD
            entry = existing_lockfile[plugin.name]
            if not entry and original_lockfile then
              entry = original_lockfile[plugin.name]
            end
          end

          results[plugin.name] = {
            repo = source_repo,
            parent = parent_plugin,
            entry = entry,
          }
        end
      end

      local write_ok, write_err = pcall(finalize_lockfiles, results, existing_lockfile, original_lockfile)
      if not write_ok then
        Util.notify("Error writing lockfiles: " .. tostring(write_err), vim.log.levels.ERROR)
      end

      -- Finish progress animation, then call completion callbacks
      finish_with_animation(function()
        if progress then
          progress:finish()
        elseif not silent then
          Util.notify("Lockfiles synced")
        end

        if on_complete then
          on_complete()
        end
      end)
    end

    vim.schedule(do_post_index_work)
  end, { on_progress = on_index_progress })
end

-- Restores plugins that were uninstalled and removed from the lockfile
-- but are still present in the config
local function restore_cleaned_plugins(pre_clean_lockfiles)
  local repo_paths = Source.get_lockfile_repo_paths()

  for _, repo_path in ipairs(repo_paths) do
    local lockfile_path = repo_path .. "/lazy-lock.json"
    local current_lockfile = Lockfile.read(lockfile_path)
    local pre_clean_lockfile = pre_clean_lockfiles[repo_path] or {}

    for plugin_name, plugin_entry in pairs(pre_clean_lockfile) do
      if not current_lockfile[plugin_name] then
        local should_keep = false

        -- Use index-based lookup (index was built during write_lockfiles)
        local source_repo = Source.get_plugin_source(plugin_name)
        if source_repo == repo_path then
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

function M.refresh(plugin_names)
  if #plugin_names == 0 then
    Source.clear_all()

    M.write_lockfiles({
      silent = false,
      on_complete = function()
        Util.notify("Refreshed plugin source index and regenerated lockfiles")
      end,
    })
  else
    -- Capture old sources from current index before rebuilding
    local old_sources = {}
    local idx = Source.get_index()
    if idx then
      for _, name in ipairs(plugin_names) do
        old_sources[name] = idx[name]
      end
    end

    -- Clear and rebuild index
    Source.clear_index()

    M.write_lockfiles({
      silent = false,
      on_complete = function()
        local new_idx = Source.get_index()
        for _, name in ipairs(plugin_names) do
          local old_entry = old_sources[name]
          local old_repo = old_entry and old_entry.repo or nil
          local new_entry = new_idx and new_idx[name]
          local new_repo = new_entry and new_entry.repo or nil

          if not new_repo then
            Util.notify("Plugin '" .. name .. "' not found in any configured repository", vim.log.levels.WARN)
          elseif not old_repo then
            Util.notify("Detected " .. name .. " source: " .. Util.format_path(new_repo))
          elseif old_repo ~= new_repo then
            Util.notify(
              "Moved " .. name .. " from " .. Util.format_path(old_repo) .. " to " .. Util.format_path(new_repo)
            )
          else
            Util.notify(name .. " source unchanged (" .. Util.format_path(new_repo) .. ")")
          end
        end
      end,
    })
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

      M.write_lockfiles({
        on_complete = function()
          -- After write completes, restore entries for plugins still in config (during clean)
          if next(pre_clean_lockfiles) ~= nil then
            local restore_ok, restore_err = pcall(restore_cleaned_plugins, pre_clean_lockfiles)
            if not restore_ok then
              Util.notify("Error restoring cleaned plugins: " .. tostring(restore_err), vim.log.levels.ERROR)
            end
            pre_clean_lockfiles = {}
          end
        end,
      })
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

    -- Defer UI hooks setup until the Lazy UI is actually opened
    -- This avoids loading UI code during startup
    local ui_setup_done = false
    vim.api.nvim_create_autocmd("User", {
      pattern = "LazyRender",
      once = false,
      callback = function()
        if not ui_setup_done then
          ui_setup_done = true
          local ui_ok, ui_err = pcall(UI.setup_hooks)
          if not ui_ok then
            Util.notify("Error setting up UI hooks: " .. tostring(ui_err), vim.log.levels.WARN)
            -- Continue silently - original lazy UI behavior is preserved
          end
        end
      end,
    })
  end)

  if not ok then
    Util.notify("Failed to setup hooks: " .. tostring(err), vim.log.levels.ERROR)
    Util.notify("Falling back to default lazy.nvim behavior", vim.log.levels.WARN)
  end
end

return M
