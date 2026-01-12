local M = {}

local cached_lockfile_repo_paths = nil -- cache of resolved repo paths
local cached_lazy_plugins = nil -- cache for lazy.plugins()
local git_info_cache = {}

local cache_dir = vim.fn.stdpath("cache") .. "/super_lazy"
local cache_file = cache_dir .. "/plugin_sources.json"
local plugin_source_cache = nil -- will be loaded from disk

local function ensure_cache_dir()
  if vim.fn.isdirectory(cache_dir) == 0 then
    local ok, err = pcall(vim.fn.mkdir, cache_dir, "p")
    if not ok then
      vim.notify(
        string.format("super_lazy: Failed to create cache directory %s: %s", cache_dir, err),
        vim.log.levels.WARN
      )
      return false
    end
  end
  return true
end

local function load_persistent_cache()
  if plugin_source_cache then
    return plugin_source_cache
  end

  if vim.fn.filereadable(cache_file) == 0 then
    plugin_source_cache = { plugin_sources = {}, version = 1 }
    return plugin_source_cache
  end

  local ok, content = pcall(vim.fn.readfile, cache_file)
  if not ok then
    plugin_source_cache = { plugin_sources = {}, version = 1 }
    return plugin_source_cache
  end

  local json_str = table.concat(content, "\n")
  local decode_ok, decoded = pcall(vim.json.decode, json_str)
  if not decode_ok or not decoded or decoded.version ~= 1 then
    plugin_source_cache = { plugin_sources = {}, version = 1 }
    return plugin_source_cache
  end

  plugin_source_cache = decoded
  return plugin_source_cache
end

local function save_persistent_cache()
  if not plugin_source_cache then
    return
  end

  if not ensure_cache_dir() then
    return
  end

  local ok, encoded = pcall(vim.json.encode, plugin_source_cache)
  if not ok then
    return
  end

  pcall(vim.fn.writefile, vim.split(encoded, "\n"), cache_file)
end

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

function M.get_git_info(key)
  return git_info_cache[key]
end

function M.set_git_info(key, value)
  git_info_cache[key] = value
end

function M.get_plugin_source(plugin_name)
  local cache = load_persistent_cache()
  return cache.plugin_sources[plugin_name]
end

function M.set_plugin_source(plugin_name, source_repo, parent_plugin)
  local cache = load_persistent_cache()
  cache.plugin_sources[plugin_name] = {
    repo = source_repo,
    parent = parent_plugin,
  }
  -- Save asynchronously to avoid blocking
  vim.schedule(save_persistent_cache)
end

function M.get_all_plugin_sources()
  local cache = load_persistent_cache()
  return cache.plugin_sources
end

function M.set_all_plugin_sources(sources)
  local cache = load_persistent_cache()
  cache.plugin_sources = sources
  save_persistent_cache()
end

function M.clear_all()
  cached_lockfile_repo_paths = nil
  cached_lazy_plugins = nil
  git_info_cache = {}
  plugin_source_cache = nil
  pcall(vim.fn.delete, cache_file)
end

function M.clear_plugin_source(plugin_name)
  local cache = load_persistent_cache()
  local old_source = cache.plugin_sources[plugin_name]
  cache.plugin_sources[plugin_name] = nil
  save_persistent_cache()
  return old_source
end

return M
