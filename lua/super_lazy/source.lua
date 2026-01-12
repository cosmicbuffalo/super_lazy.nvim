local Cache = require("super_lazy.cache")
local Config = require("super_lazy.config")
local Fs = require("super_lazy.fs")
local Util = require("super_lazy.util")

local M = {}

-- For testing: when true, async functions use sync implementations
M._test_mode = false

-- In-memory index built during async scanning
-- Structure: { [plugin_name] = { repo = path, parent = parent_plugin_or_nil } }
local plugin_index = nil

-- Clear the in-memory index (called when cache is cleared)
function M.clear_index()
  plugin_index = nil
end

-- Get the current index (for lookups after building)
function M.get_index()
  return plugin_index
end

local function create_plugin_patterns(plugin_name)
  local escaped_plugin = plugin_name:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")
  return {
    '["\'][^/"]+/' .. escaped_plugin .. "[\"']",
    "name%s*=%s*[\"']" .. escaped_plugin .. "[\"']",
  }
end

-- Extract all plugin names from file content
-- Returns a list of plugin names found in the content
local function extract_plugin_names(content)
  local plugins = {}
  local seen = {}

  -- Pattern 1: "owner/plugin-name" or 'owner/plugin-name' (GitHub-style)
  -- Note: [^\n] prevents matching across newlines (important for comments with quotes)
  for owner, name in content:gmatch('["\']([^/"\'%s]+)/([^"\'\n]+)["\']') do
    -- Filter out things that don't look like plugin names
    if name and #name > 0 and not seen[name] then
      -- Basic validation: should look like a plugin name
      if name:match("^[%w_%-%.]+$") and not name:match("^%d+$") then
        seen[name] = true
        table.insert(plugins, name)
      end
    end
  end

  -- Pattern 2: name = "plugin-name" or name = 'plugin-name'
  for name in content:gmatch('name%s*=%s*["\']([^"\'\n]+)["\']') do
    if name and #name > 0 and not seen[name] then
      if name:match("^[%w_%-%.]+$") and not name:match("^%d+$") then
        seen[name] = true
        table.insert(plugins, name)
      end
    end
  end

  -- Pattern 3: dir = "path/to/plugin-name" - extract the last path component
  -- This handles local plugins defined with dir = "..."
  for dir_path in content:gmatch('dir%s*=%s*["\']([^"\'\n]+)["\']') do
    if dir_path and #dir_path > 0 then
      -- Extract the last component of the path (the plugin name)
      local name = dir_path:match("([^/]+)/?$")
      if name and #name > 0 and not seen[name] then
        if name:match("^[%w_%-%.]+$") and not name:match("^%d+$") then
          seen[name] = true
          table.insert(plugins, name)
        end
      end
    end
  end

  return plugins
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

  for _, file in ipairs(files) do
    if search_file_for_plugin(file, patterns) then
      return true
    end
  end

  return false
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
  local patterns = create_plugin_patterns(plugin_name)
  local installed_plugins = get_lazy_plugins()
  local lazy_path = vim.fn.stdpath("data") .. "/lazy"

  -- Check each installed plugin to see if it exists in the repo and has a lazy.lua file
  for _, plugin in ipairs(installed_plugins) do
    local plugin_dir_name = plugin.name

    if plugin_exists_in_repo(plugin_dir_name, repo_path) then
      local lazy_file = lazy_path .. "/" .. plugin_dir_name .. "/lazy.lua"
      if vim.fn.filereadable(lazy_file) == 1 then
        if search_file_for_plugin(lazy_file, patterns) then
          return plugin_dir_name
        end
      end
    end
  end

  return nil
end

function M.get_plugin_source(plugin_name, with_recipe)
  local repo_paths = M.get_lockfile_repo_paths()

  if plugin_name == "lazy.nvim" then
    -- Return the first repo path for lazy.nvim
    if with_recipe then
      return repo_paths[1] or vim.fn.stdpath("config"), nil
    end
    return repo_paths[1] or vim.fn.stdpath("config")
  end

  -- Try to get from persistent cache first
  local cached = Cache.get_plugin_source(plugin_name)
  if cached then
    -- Verify the cached repo still exists in our config
    for _, repo_path in ipairs(repo_paths) do
      if repo_path == cached.repo then
        if with_recipe then
          return cached.repo, cached.parent
        end
        return cached.repo
      end
    end
  end

  -- Cache miss or invalid - do the expensive search
  -- For each configured lockfile repo, check in order:
  for _, repo_path in ipairs(repo_paths) do
    -- Step 1: Check if plugin exists directly in this repo
    if plugin_exists_in_repo(plugin_name, repo_path) then
      Cache.set_plugin_source(plugin_name, repo_path, nil)
      if with_recipe then
        return repo_path, nil
      end
      return repo_path
    end

    -- Step 2: Check if plugin is found inside a lazy.lua file of a plugin in this repo
    local recipe_plugin = find_plugin_in_recipe(plugin_name, repo_path)
    if recipe_plugin then
      Cache.set_plugin_source(plugin_name, repo_path, recipe_plugin)
      if with_recipe then
        return repo_path, recipe_plugin
      end
      return repo_path
    end
  end

  local debug_msg = "Plugin " .. plugin_name .. " not found in any configured lockfile repository.\n"
  error(debug_msg)
end

-- ============================================================================
-- ASYNC VERSIONS
-- ============================================================================

-- Async version: Check if plugin exists in repo
-- callback(found)
local function plugin_exists_in_repo_async(plugin_name, repo_path, callback)
  local patterns = create_plugin_patterns(plugin_name)

  -- Get other repos to filter out
  local repo_paths = M.get_lockfile_repo_paths()
  local other_repos = {}
  for _, path in ipairs(repo_paths) do
    if path ~= repo_path then
      table.insert(other_repos, path)
    end
  end

  -- Use async glob to find plugin files
  -- We need to search both patterns
  local all_files = {}
  local globs_pending = 2

  local function on_glob_done(err, files)
    globs_pending = globs_pending - 1
    if files then
      for _, f in ipairs(files) do
        -- Filter out files from other repos
        local real_file_path = vim.fn.resolve(f)
        local is_in_other_repo = false
        for _, other_repo in ipairs(other_repos) do
          if real_file_path:find(other_repo .. "/", 1, true) == 1 then
            is_in_other_repo = true
            break
          end
        end
        if not is_in_other_repo then
          table.insert(all_files, f)
        end
      end
    end

    if globs_pending == 0 then
      -- All globs done, now search files
      Fs.search_files(all_files, patterns, function(found, file_path, line)
        callback(found)
      end)
    end
  end

  Fs.glob_async(repo_path, "plugins/**/*.lua", on_glob_done)
  Fs.glob_async(repo_path, "**/plugins/**/*.lua", on_glob_done)
end

-- Async version: Find plugin in recipe files
-- callback(parent_plugin_name or nil)
local function find_plugin_in_recipe_async(plugin_name, repo_path, callback)
  local patterns = create_plugin_patterns(plugin_name)
  local installed_plugins = get_lazy_plugins()
  local lazy_path = vim.fn.stdpath("data") .. "/lazy"

  if #installed_plugins == 0 then
    callback(nil)
    return
  end

  local index = 1

  local function check_next_plugin()
    if index > #installed_plugins then
      callback(nil)
      return
    end

    local plugin = installed_plugins[index]
    local plugin_dir_name = plugin.name

    -- First check if this plugin exists in the repo (async)
    plugin_exists_in_repo_async(plugin_dir_name, repo_path, function(exists)
      if not exists then
        index = index + 1
        vim.schedule(check_next_plugin)
        return
      end

      -- Check if it has a lazy.lua file
      local lazy_file = lazy_path .. "/" .. plugin_dir_name .. "/lazy.lua"
      Fs.file_exists(lazy_file, function(file_exists)
        if not file_exists then
          index = index + 1
          vim.schedule(check_next_plugin)
          return
        end

        -- Search the lazy.lua file for our plugin
        Fs.search_file(lazy_file, patterns, function(found, line)
          if found then
            callback(plugin_dir_name)
          else
            index = index + 1
            vim.schedule(check_next_plugin)
          end
        end)
      end)
    end)
  end

  check_next_plugin()
end

-- Async version of get_plugin_source
-- callback(repo_path, parent_plugin, err)
function M.get_plugin_source_async(plugin_name, with_recipe, callback)
  -- In test mode, use sync implementation and call callback immediately
  if M._test_mode then
    local ok, repo, parent = pcall(function()
      return M.get_plugin_source(plugin_name, with_recipe)
    end)
    if ok then
      callback(repo, parent, nil)
    else
      callback(nil, nil, repo) -- repo contains error message on failure
    end
    return
  end

  local repo_paths = M.get_lockfile_repo_paths()

  if plugin_name == "lazy.nvim" then
    local repo = repo_paths[1] or vim.fn.stdpath("config")
    if with_recipe then
      callback(repo, nil, nil)
    else
      callback(repo, nil, nil)
    end
    return
  end

  -- Try to get from persistent cache first
  local cached = Cache.get_plugin_source(plugin_name)
  if cached then
    for _, repo_path in ipairs(repo_paths) do
      if repo_path == cached.repo then
        callback(cached.repo, cached.parent, nil)
        return
      end
    end
  end

  -- Cache miss - do async search
  local repo_index = 1

  local function check_next_repo()
    if repo_index > #repo_paths then
      callback(nil, nil, "Plugin " .. plugin_name .. " not found in any configured lockfile repository.")
      return
    end

    local repo_path = repo_paths[repo_index]

    -- Step 1: Check if plugin exists directly in this repo
    plugin_exists_in_repo_async(plugin_name, repo_path, function(exists)
      if exists then
        Cache.set_plugin_source(plugin_name, repo_path, nil)
        callback(repo_path, nil, nil)
        return
      end

      -- Step 2: Check if plugin is found in a lazy.lua file
      find_plugin_in_recipe_async(plugin_name, repo_path, function(recipe_plugin)
        if recipe_plugin then
          Cache.set_plugin_source(plugin_name, repo_path, recipe_plugin)
          callback(repo_path, recipe_plugin, nil)
          return
        end

        -- Not in this repo, try next
        repo_index = repo_index + 1
        vim.schedule(check_next_repo)
      end)
    end)
  end

  check_next_repo()
end

-- ============================================================================
-- INDEX-BASED ASYNC SCANNING (Much faster - scans files once, not per-plugin)
-- ============================================================================

-- Sync version of index building (for testing and sync refresh)
local function build_index_sync()
  local repo_paths = M.get_lockfile_repo_paths()
  local index = {}
  local lazy_path = vim.fn.stdpath("data") .. "/lazy"

  for _, repo_path in ipairs(repo_paths) do
    -- Get other repos to filter out nested repos
    -- We need to resolve both the current repo and other repos for consistent comparison
    local resolved_repo_path = vim.fn.resolve(repo_path)
    local other_repos = {}
    for _, path in ipairs(repo_paths) do
      local resolved_path = vim.fn.resolve(path)
      if resolved_path ~= resolved_repo_path then
        table.insert(other_repos, resolved_path)
      end
    end

    -- Find all plugin lua files
    local files = vim.list_extend(
      vim.fn.glob(repo_path .. "/plugins/**/*.lua", true, true),
      vim.fn.glob(repo_path .. "/**/plugins/**/*.lua", true, true)
    )

    -- Filter out files from nested repos
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
      end
    end

    -- Track which plugins are directly in this repo
    local direct_plugins = {}

    -- Read and parse each file
    for _, file in ipairs(filtered_files) do
      local f = io.open(file, "r")
      if f then
        local content = f:read("*a")
        f:close()
        if content then
          local plugins = extract_plugin_names(content)
          for _, plugin_name in ipairs(plugins) do
            if not index[plugin_name] then
              index[plugin_name] = { repo = repo_path, parent = nil }
              direct_plugins[plugin_name] = true
            end
          end
        end
      end
    end

    -- Check recipe files for plugins in this repo
    for plugin_name, _ in pairs(direct_plugins) do
      local lazy_file = lazy_path .. "/" .. plugin_name .. "/lazy.lua"
      if vim.fn.filereadable(lazy_file) == 1 then
        local f = io.open(lazy_file, "r")
        if f then
          local content = f:read("*a")
          f:close()
          if content then
            local nested_plugins = extract_plugin_names(content)
            for _, nested_name in ipairs(nested_plugins) do
              if not index[nested_name] then
                index[nested_name] = { repo = repo_path, parent = plugin_name }
              end
            end
          end
        end
      end
    end
  end

  plugin_index = index
  return index
end

-- Build an index of all plugins found in all repos
-- This scans each file once and extracts all plugin names
-- callback(index) where index is { [plugin_name] = { repo = path, parent = nil_or_parent } }
function M.build_index_async(callback)
  -- In test mode, use sync implementation
  if M._test_mode then
    local index = build_index_sync()
    callback(index)
    return
  end

  local repo_paths = M.get_lockfile_repo_paths()
  local index = {}
  local lazy_path = vim.fn.stdpath("data") .. "/lazy"

  -- Track pending operations
  local repos_pending = #repo_paths
  if repos_pending == 0 then
    plugin_index = index
    callback(index)
    return
  end

  -- For each repo, we need to:
  -- 1. Find all plugin lua files (sync glob is fast enough)
  -- 2. Read and parse each file async
  -- 3. Also check lazy.lua files for recipe plugins

  local function process_repo(repo_path, on_repo_done)
    -- Get other repos to filter out nested repos
    -- We need to resolve both the current repo and other repos for consistent comparison
    local resolved_repo_path = vim.fn.resolve(repo_path)
    local other_repos = {}
    for _, path in ipairs(repo_paths) do
      local resolved_path = vim.fn.resolve(path)
      if resolved_path ~= resolved_repo_path then
        table.insert(other_repos, resolved_path)
      end
    end

    -- Use sync glob - it's actually fast, the slow part is reading files
    local files = vim.list_extend(
      vim.fn.glob(repo_path .. "/plugins/**/*.lua", true, true),
      vim.fn.glob(repo_path .. "/**/plugins/**/*.lua", true, true)
    )

    -- Filter out files from nested repos
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
      end
    end

    if #filtered_files == 0 then
      on_repo_done()
      return
    end

    -- Track which plugins are directly in this repo (for recipe parent detection)
    local direct_plugins = {}

    local files_pending = #filtered_files
    local function on_file_done()
      files_pending = files_pending - 1
      if files_pending == 0 then
        -- Now check recipe files for plugins in this repo
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

        -- Process recipe files
        local recipes_pending = #recipe_plugins_to_check
        for _, recipe in ipairs(recipe_plugins_to_check) do
          Fs.read_file(recipe.file, function(err, content)
            if not err and content then
              local nested_plugins = extract_plugin_names(content)
              for _, nested_name in ipairs(nested_plugins) do
                -- Only add if not already indexed (first repo wins)
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

    -- Read all plugin files async
    for _, file in ipairs(filtered_files) do
      Fs.read_file(file, function(err, content)
        if not err and content then
          local plugins = extract_plugin_names(content)
          for _, plugin_name in ipairs(plugins) do
            -- Only add if not already indexed (first repo wins)
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

  -- Process repos SEQUENTIALLY to maintain priority order (first repo wins)
  local repo_index = 1
  local function process_next_repo()
    if repo_index > #repo_paths then
      -- All repos done
      plugin_index = index
      callback(index)
      return
    end

    local repo_path = repo_paths[repo_index]
    process_repo(repo_path, function()
      repo_index = repo_index + 1
      -- Use vim.schedule to avoid stack overflow with many repos
      vim.schedule(process_next_repo)
    end)
  end

  process_next_repo()
end

-- Lookup a plugin in the pre-built index
-- Returns repo_path, parent_plugin, err
function M.lookup_plugin_in_index(plugin_name, with_recipe)
  local repo_paths = M.get_lockfile_repo_paths()

  if plugin_name == "lazy.nvim" then
    local repo = repo_paths[1] or vim.fn.stdpath("config")
    if with_recipe then
      return repo, nil, nil
    end
    return repo, nil, nil
  end

  -- Check persistent cache first
  local cached = Cache.get_plugin_source(plugin_name)
  if cached then
    for _, repo_path in ipairs(repo_paths) do
      if repo_path == cached.repo then
        return cached.repo, cached.parent, nil
      end
    end
  end

  -- Check in-memory index
  if plugin_index and plugin_index[plugin_name] then
    local entry = plugin_index[plugin_name]
    -- Update persistent cache
    Cache.set_plugin_source(plugin_name, entry.repo, entry.parent)
    return entry.repo, entry.parent, nil
  end

  return nil, nil, "Plugin " .. plugin_name .. " not found in any configured lockfile repository."
end

return M
