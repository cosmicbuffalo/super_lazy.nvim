local Config = require("super_lazy.config")
local Fs = require("super_lazy.fs")
local Util = require("super_lazy.util")

local LazyGit = require("lazy.manage.git")

local M = {}

local plugin_index = nil
local cached_lockfile_repo_paths = nil

function M.clear_all()
  plugin_index = nil
  cached_lockfile_repo_paths = nil
end

function M.clear_index()
  plugin_index = nil
end

function M.get_index()
  return plugin_index
end

local function is_valid_plugin_name(name)
  return name and #name > 0 and name:match("^[%w_%-%.]+$") and not name:match("^%d+$")
end

local function extract_plugin_names(content)
  local plugins = {}
  local seen = {}

  local function add_plugin(name)
    if not seen[name] and is_valid_plugin_name(name) then
      seen[name] = true
      table.insert(plugins, name)
    end
  end

  for owner, name in content:gmatch("[\"']([^/\"'%s]+)/([^\"'\n]+)[\"']") do
    add_plugin(name)
  end

  for name in content:gmatch("name%s*=%s*[\"']([^\"'\n]+)[\"']") do
    add_plugin(name)
  end

  for dir_path in content:gmatch("dir%s*=%s*[\"']([^\"'\n]+)[\"']") do
    if dir_path and #dir_path > 0 then
      local name = dir_path:match("([^/]+)/?$")
      add_plugin(name)
    end
  end

  return plugins
end

function M.get_lockfile_repo_paths()
  if cached_lockfile_repo_paths then
    return cached_lockfile_repo_paths
  end

  local paths = {}
  for _, dir in ipairs(Config.options.lockfile_repo_dirs) do
    local real_path = vim.fn.resolve(dir)
    if vim.fn.isdirectory(real_path) == 1 then
      table.insert(paths, real_path)
    else
      if Config.options.debug then
        Util.notify("lockfile_repo_dirs entry is not a valid directory: " .. tostring(dir), vim.log.levels.WARN)
      end
    end
  end

  cached_lockfile_repo_paths = paths
  return paths
end

-- opts = {
--   on_progress = function(current, total, message),  -- Progress callback (optional)
-- }
function M.build_index(callback, opts)
  opts = opts or {}
  local on_progress = opts.on_progress

  local repo_paths = M.get_lockfile_repo_paths()
  local index = {}
  local lazy_path = vim.fn.stdpath("data") .. "/lazy"

  if #repo_paths == 0 then
    plugin_index = index
    callback(index)
    return
  end

  -- Count total files across all repos for progress tracking
  local total_files = 0
  local files_completed = 0
  local all_repo_files = {}

  for _, repo_path in ipairs(repo_paths) do
    local other_repos = {}
    local resolved_exclude = vim.fn.resolve(repo_path)
    for _, path in ipairs(repo_paths) do
      local resolved_path = vim.fn.resolve(path)
      if resolved_path ~= resolved_exclude then
        table.insert(other_repos, resolved_path)
      end
    end

    local files = vim.list_extend(
      vim.fn.glob(repo_path .. "/plugins/**/*.lua", true, true),
      vim.fn.glob(repo_path .. "/**/plugins/**/*.lua", true, true)
    )
    local filtered_files = {}
    for _, file in ipairs(files) do
      local real_file_path = vim.fn.resolve(file)
      local is_in_other_repo = false
      for _, other_repo in ipairs(other_repos) do
        if real_file_path:find(other_repo .. "/", 1, true) == 1 then
          is_in_other_repo = true
          break
        end
      end
      if not is_in_other_repo then
        table.insert(filtered_files, file)
        total_files = total_files + 1
      end
    end
    all_repo_files[repo_path] = filtered_files
  end

  if total_files == 0 then
    plugin_index = index
    callback(index)
    return
  end

  local function report_progress(message)
    if on_progress then
      on_progress(files_completed, total_files, message)
    end
  end

  local function process_repo(repo_path, on_repo_done)
    local filtered_files = all_repo_files[repo_path]

    if #filtered_files == 0 then
      on_repo_done()
      return
    end

    local direct_plugins = {}

    local files_pending = #filtered_files
    local function on_file_done()
      files_pending = files_pending - 1
      files_completed = files_completed + 1
      report_progress("Scanning plugin files...")

      if files_pending == 0 then
        local recipe_plugins_to_check = {}
        for plugin_name, _ in pairs(direct_plugins) do
          local lazy_file = lazy_path .. "/" .. plugin_name .. "/lazy.lua"
          if vim.fn.filereadable(lazy_file) == 1 then
            table.insert(recipe_plugins_to_check, { name = plugin_name, file = lazy_file })
          end
        end

        if #recipe_plugins_to_check == 0 then
          on_repo_done()
          return
        end

        local recipes_pending = #recipe_plugins_to_check
        for _, recipe in ipairs(recipe_plugins_to_check) do
          Fs.read_file(recipe.file, function(err, content)
            if not err and content then
              local nested_plugins = extract_plugin_names(content)
              for _, nested_name in ipairs(nested_plugins) do
                if not index[nested_name] then
                  index[nested_name] = { repo = repo_path, parent = recipe.name }
                end
              end
            end
            recipes_pending = recipes_pending - 1
            if recipes_pending == 0 then
              on_repo_done()
            end
          end)
        end
      end
    end

    for _, file in ipairs(filtered_files) do
      Fs.read_file(file, function(err, content)
        if not err and content then
          local plugins = extract_plugin_names(content)
          for _, plugin_name in ipairs(plugins) do
            if not index[plugin_name] then
              index[plugin_name] = { repo = repo_path, parent = nil }
              direct_plugins[plugin_name] = true
            end
          end
        end
        on_file_done()
      end)
    end
  end

  local repo_index = 1
  local function process_next_repo()
    if repo_index > #repo_paths then
      plugin_index = index
      callback(index)
      return
    end

    local repo_path = repo_paths[repo_index]
    process_repo(repo_path, function()
      repo_index = repo_index + 1
      vim.schedule(process_next_repo)
    end)
  end

  report_progress("Starting scan...")
  process_next_repo()
end

function M.get_plugin_source(plugin_name)
  local repo_paths = M.get_lockfile_repo_paths()

  -- Return the first repo path for lazy.nvim
  if plugin_name == "lazy.nvim" then
    return repo_paths[1] or vim.fn.stdpath("config"), nil, nil
  end

  -- Look up in the in-memory index
  if plugin_index and plugin_index[plugin_name] then
    local entry = plugin_index[plugin_name]
    return entry.repo, entry.parent, nil
  end

  -- note that if the in-memory index hasn't been built yet we'll return nil here
  return nil, nil, "Plugin " .. plugin_name .. " not found in source index."
end

-- Get git info for a plugin directory
function M.get_git_info(plugin)
  local info = LazyGit.info(plugin.dir)
  if info then
    return {
      branch = info.branch or LazyGit.get_branch({ dir = plugin.dir, name = plugin.name }),
      commit = info.commit,
    }
  end
  return nil
end

return M
