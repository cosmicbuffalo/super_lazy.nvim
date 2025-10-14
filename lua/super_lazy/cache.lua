local M = {}

local cached_lockfile_repo_paths = nil -- cache of resolved repo paths
local cached_lazy_plugins = nil -- cache for lazy.plugins()
local plugin_exists_cache = {}
local recipe_cache = {}
local git_info_cache = {}

function M.get_lockfile_repo_paths()
  return cached_lockfile_repo_paths
end

function M.set_lockfile_repo_paths(paths)
  cached_lockfile_repo_paths = paths
end

function M.get_lazy_plugins()
  return cached_lazy_plugins
end

function M.set_lazy_plugins(plugins)
  cached_lazy_plugins = plugins
end

function M.get_plugin_exists(key)
  return plugin_exists_cache[key]
end

function M.set_plugin_exists(key, value)
  plugin_exists_cache[key] = value
end

function M.get_recipe(key)
  return recipe_cache[key]
end

function M.set_recipe(key, value)
  recipe_cache[key] = value
end

function M.get_git_info(key)
  return git_info_cache[key]
end

function M.set_git_info(key, value)
  git_info_cache[key] = value
end

function M.clear_all()
  cached_lockfile_repo_paths = nil
  cached_lazy_plugins = nil
  plugin_exists_cache = {}
  recipe_cache = {}
  git_info_cache = {}
end

return M
