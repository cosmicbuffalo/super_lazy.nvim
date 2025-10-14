local Cache = require("super_lazy.cache")
local Config = require("super_lazy.config")
local Util = require("super_lazy.util")

local M = {}

local function create_plugin_patterns(plugin_name)
  local escaped_plugin = plugin_name:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")
  return {
    '["\'][^/"]+/' .. escaped_plugin .. "[\"']",
    "name%s*=%s*[\"']" .. escaped_plugin .. "[\"']",
  }
end

function M.get_lockfile_repo_paths()
  local cached = Cache.get_lockfile_repo_paths()
  if cached then
    return cached
  end

  local paths = {}
  for _, dir in ipairs(Config.options.lockfile_repo_dirs) do
    local real_path = vim.fn.resolve(dir)
    if vim.fn.isdirectory(real_path) == 1 then
      table.insert(paths, real_path)
    else
      Util.notify("lockfile_repo_dirs entry is not a valid directory: " .. tostring(dir), vim.log.levels.WARN)
    end
  end

  Cache.set_lockfile_repo_paths(paths)
  return paths
end

local function search_file_for_plugin(file_path, patterns)
  local file = io.open(file_path, "r")
  if not file then
    return false
  end

  for line in file:lines() do
    for _, pattern in ipairs(patterns) do
      if line:find(pattern) then
        file:close()
        return true
      end
    end
  end

  file:close()
  return false
end

local function plugin_exists_in_repo(plugin_name, repo_path)
  local cache_key = plugin_name .. "|" .. repo_path
  local cached = Cache.get_plugin_exists(cache_key)
  if cached ~= nil then
    return cached
  end

  local patterns = create_plugin_patterns(plugin_name)

  local files = vim.list_extend(
    vim.fn.glob(repo_path .. "/plugins/**/*.lua", true, true),
    vim.fn.glob(repo_path .. "/**/plugins/**/*.lua", true, true)
  )

  -- Filter out files from any other lockfile repos that may be nested under the current repo
  local repo_paths = M.get_lockfile_repo_paths()
  local other_repos = {}
  for _, path in ipairs(repo_paths) do
    if path ~= repo_path then
      table.insert(other_repos, path)
    end
  end

  local filtered_files = {}
  for _, file in ipairs(files) do
    -- Resolve the file path to handle symlinks correctly
    local real_file_path = vim.fn.resolve(file)
    local is_in_other_repo = false
    for _, other_repo in ipairs(other_repos) do
      -- Check if the resolved file path is within any other repo's path
      if real_file_path:find(other_repo .. "/", 1, true) == 1 then
        is_in_other_repo = true
        break
      end
    end
    if not is_in_other_repo then
      table.insert(filtered_files, file)
    end
  end
  files = filtered_files

  local result = false
  for _, file in ipairs(files) do
    if search_file_for_plugin(file, patterns) then
      result = true
      break
    end
  end

  Cache.set_plugin_exists(cache_key, result)
  return result
end

local function get_lazy_plugins()
  local cached = Cache.get_lazy_plugins()
  if cached then
    return cached
  end

  local success, lazy = pcall(require, "lazy")
  if not success then
    return {}
  end

  local plugins = lazy.plugins()
  Cache.set_lazy_plugins(plugins)
  return plugins
end

-- Find a plugin in the lazy.lua files of installed plugins
local function find_plugin_in_recipe(plugin_name, repo_path)
  local cache_key = plugin_name .. "|" .. repo_path
  local cached = Cache.get_recipe(cache_key)
  if cached ~= nil then
    return cached
  end

  local patterns = create_plugin_patterns(plugin_name)
  local installed_plugins = get_lazy_plugins()
  local lazy_path = vim.fn.stdpath("data") .. "/lazy"

  local result = nil

  -- Check each installed plugin to see if it exists in the repo and has a lazy.lua file
  for _, plugin in ipairs(installed_plugins) do
    local plugin_dir_name = plugin.name

    if plugin_exists_in_repo(plugin_dir_name, repo_path) then
      local lazy_file = lazy_path .. "/" .. plugin_dir_name .. "/lazy.lua"
      if vim.fn.filereadable(lazy_file) == 1 then
        if search_file_for_plugin(lazy_file, patterns) then
          result = plugin_dir_name
          break
        end
      end
    end
  end

  Cache.set_recipe(cache_key, result)
  return result
end

function M.get_plugin_source(plugin_name, with_recipe)
  local repo_paths = M.get_lockfile_repo_paths()

  if plugin_name == "lazy.nvim" then
    -- Return the first repo path for lazy.nvim
    return repo_paths[1] or vim.fn.stdpath("config")
  end

  -- For each configured lockfile repo, check in order:
  for _, repo_path in ipairs(repo_paths) do
    -- Step 1: Check if plugin exists directly in this repo
    if plugin_exists_in_repo(plugin_name, repo_path) then
      return repo_path
    end

    -- Step 2: Check if plugin is found inside a lazy.lua file of a plugin in this repo
    local recipe_plugin = find_plugin_in_recipe(plugin_name, repo_path)
    if recipe_plugin then
      if with_recipe then
        return repo_path .. " (" .. recipe_plugin .. ")"
      end
      return repo_path
    end
  end

  local debug_msg = "Plugin " .. plugin_name .. " not found in any configured lockfile repository.\n"
  error(debug_msg)
end

return M
