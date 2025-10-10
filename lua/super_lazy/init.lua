local LazyConfig = require("lazy.core.config")
local LazyGit = require("lazy.manage.git")
local LazyLock = require("lazy.manage.lock")
local LazyUtil = require("lazy.util")

local M = {}

M.COMPATIBLE_LAZY_VERSION = "11.17.1"

local cached_paths = nil
local cached_lazy_plugins = nil
local plugin_exists_cache = {}
local recipe_cache = {}
local git_info_cache = {}

local default_config = {
  lockfile_repo_dirs = { vim.fn.stdpath("config") },
}

local config = {}

function M.setup(user_config)
  config = vim.tbl_deep_extend("force", default_config, user_config or {})

  if #vim.api.nvim_list_uis() == 0 then -- headless mode
    M.setup_lazy_hooks()
  else
    vim.schedule(function()
      M.setup_lazy_hooks()
    end)
  end
end

function M.notify(msg, level)
  vim.notify("super_lazy.nvim: " .. msg, level or vim.log.levels.INFO, { title = "super_lazy.nvim" })
end

function M.check_lazy_compatibility()
  local ok, result = pcall(function()
    local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
    if vim.fn.isdirectory(lazypath) == 0 then
      M.notify("lazy.nvim directory not found at " .. lazypath, vim.log.levels.WARN)
      return false
    end

    local git_info = LazyGit.info(lazypath, true)
    if git_info and git_info.version then
      local installed_version = tostring(git_info.version)
      if installed_version ~= M.COMPATIBLE_LAZY_VERSION then
        M.notify(
          string.format(
            "requires lazy.nvim == %s, but found %s. Some features may not work correctly.",
            M.COMPATIBLE_LAZY_VERSION,
            installed_version
          ),
          vim.log.levels.WARN
        )
        return false
      end
    else
      -- If we can't determine the version, check for required API functions
      if not LazyConfig.plugins or not LazyConfig.spec or not LazyLock.update then
        M.notify("incompatible lazy.nvim version - missing required APIs", vim.log.levels.WARN)
        return false
      end

      M.notify(
        "Couldn't determine lazy.nvim version (requires == " .. M.COMPATIBLE_LAZY_VERSION .. ")",
        vim.log.levels.WARN
      )
    end
    return true
  end)

  if not ok then
    M.notify("Error checking lazy.nvim version: " .. tostring(result), vim.log.levels.WARN)
    return false
  end

  return result
end

local function create_plugin_patterns(plugin_name)
  local escaped_plugin = plugin_name:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")
  return {
    '["\'][^/"]+/' .. escaped_plugin .. "[\"']",
    "name%s*=%s*[\"']" .. escaped_plugin .. "[\"']",
  }
end

function M.get_lockfile_repo_paths()
  if cached_paths then
    return cached_paths
  end
  local paths = {}
  for _, dir in ipairs(config.lockfile_repo_dirs) do
    local real_path = vim.fn.resolve(dir)
    if vim.fn.isdirectory(real_path) == 1 then
      table.insert(paths, real_path)
    else
      M.notify("lockfile_repo_dirs entry is not a valid directory: " .. tostring(dir), vim.log.levels.WARN)
    end
  end
  cached_paths = paths
  return cached_paths
end

local function search_file_for_plugin(file_path, patterns)
  local content = vim.fn.readfile(file_path)
  if not content then
    return false
  end

  local file_content = table.concat(content, "\n")

  for _, pattern in ipairs(patterns) do
    if file_content:find(pattern) then
      return true
    end
  end

  return false
end

local function plugin_exists_in_repo(plugin_name, repo_path)
  local cache_key = plugin_name .. "|" .. repo_path
  if plugin_exists_cache[cache_key] ~= nil then
    return plugin_exists_cache[cache_key]
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

  plugin_exists_cache[cache_key] = result
  return result
end

local function get_lazy_plugins()
  if cached_lazy_plugins then
    return cached_lazy_plugins
  end

  local success, lazy = pcall(require, "lazy")
  if not success then
    return {}
  end

  cached_lazy_plugins = lazy.plugins()
  return cached_lazy_plugins
end

local function get_cached_git_info(plugin_dir, plugin_name)
  if git_info_cache[plugin_dir] then
    return git_info_cache[plugin_dir]
  end

  local info = LazyGit.info(plugin_dir)

  if info then
    local git_info = {
      branch = info.branch or LazyGit.get_branch({ dir = plugin_dir, name = plugin_name }),
      commit = info.commit,
    }
    git_info_cache[plugin_dir] = git_info
    return git_info
  end

  git_info_cache[plugin_dir] = false
  return nil
end

-- Find a plugin in the lazy.lua files of installed plugins
local function find_plugin_in_recipe(plugin_name, repo_path)
  local cache_key = plugin_name .. "|" .. repo_path
  if recipe_cache[cache_key] ~= nil then
    return recipe_cache[cache_key]
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

  recipe_cache[cache_key] = result
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

  local debug_msg = string.format("Plugin '%s' not found in any configured lockfile repository.\n", plugin_name)
  error(debug_msg)
end

function M.read_lockfile(path)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  local content = vim.fn.readfile(path)
  local json_str = table.concat(content, "\n")

  local ok, decoded = pcall(vim.json.decode, json_str)
  if not ok then
    return {}
  end

  return decoded
end

local function write_lockfile(path, data)
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")

  -- Format lockfile exactly like lazy.nvim does (with pretty indentation)
  local f = assert(io.open(path, "wb"))
  f:write("{\n")

  local names = vim.tbl_keys(data)
  table.sort(names)

  for n, name in ipairs(names) do
    local info = data[name]
    f:write(([[  %q: { "branch": %q, "commit": %q }]]):format(name, info.branch, info.commit))
    if n ~= #names then
      f:write(",\n")
    end
  end
  f:write("\n}\n")
  f:close()
end

function M.setup_lazy_hooks()
  local ok, err = pcall(function()
    -- Notify on mismatched version but continue assuming lazy hasn't changed to be incompatible
    M.check_lazy_compatibility()

    local original_update = LazyLock.update

    -- Override lazy's lockfile update function with error handling
    LazyLock.update = function()
      local original_ok, original_err = pcall(original_update)
      if not original_ok then
        M.notify("Error in original lazy update: " .. tostring(original_err), vim.log.levels.ERROR)
        return -- Don't try our custom logic if original failed
      end

      local lockfile_ok, lockfile_err = pcall(M.write_dual_lockfiles)
      if not lockfile_ok then
        M.notify("Error managing dual lockfiles: " .. tostring(lockfile_err), vim.log.levels.ERROR)
      end
    end

    -- Also hook into the lazy TUI to show shared/personal status (with error handling)
    local ui_ok, ui_err = pcall(M.setup_ui_hooks)
    if not ui_ok then
      M.notify("Error setting up UI hooks: " .. tostring(ui_err), vim.log.levels.WARN)
      -- Continue silently - original lazy UI behavior is preserved
    end
  end)

  if not ok then
    M.notify("Failed to setup hooks: " .. tostring(err), vim.log.levels.ERROR)
    M.notify("Falling back to default lazy.nvim behavior", vim.log.levels.WARN)
  end
end

-- This function is a direct copy of the internals of lazy.view.render.details
local function insert_lazy_props(props, plugin)
  table.insert(props, { "dir", plugin.dir, "LazyDir" })
  if plugin.url then
    table.insert(props, { "url", (plugin.url:gsub("%.git$", "")), "LazyUrl" })
  end

  local git = LazyGit.info(plugin.dir, true)
  if git then
    git.branch = git.branch or LazyGit.get_branch(plugin)
    if git.version then
      table.insert(props, { "version", tostring(git.version) })
    end
    if git.tag then
      table.insert(props, { "tag", git.tag })
    end
    if git.branch then
      table.insert(props, { "branch", git.branch })
    end
    if git.commit then
      table.insert(props, { "commit", git.commit:sub(1, 7), "LazyCommit" })
    end
  end

  local rocks = require("lazy.pkg.rockspec").deps(plugin)
  if rocks then
    table.insert(props, { "rocks", vim.inspect(rocks) })
  end

  if LazyUtil.file_exists(plugin.dir .. "/README.md") then
    table.insert(props, { "readme", "README.md" })
  end
  LazyUtil.ls(plugin.dir .. "/doc", function(path, name)
    if name:sub(-3) == "txt" then
      local data = LazyUtil.read_file(path)
      local tag = data:match("%*(%S-)%*")
      if tag then
        table.insert(props, { "help", "|" .. tag .. "|" })
      end
    end
  end)

  for handler in pairs(plugin._.handlers or {}) do
    table.insert(props, {
      handler,
      function()
        self:handlers(plugin, handler)
      end,
    })
  end
end

function M.setup_ui_hooks()
  local ok, err = pcall(function()
    local render = require("lazy.view.render")
    local original_details = render.details

    render.details = function(self, plugin)
      -- Wrap custom logic in error handling, fall back to original if it fails
      local custom_ok, custom_err = pcall(function()
        -- Build props array like the original function does
        local props = {}

        -- Add our source information at the top
        local source = "unknown"
        local source_ok, result = pcall(M.get_plugin_source, plugin.name, true)
        if source_ok then
          source = result
        end
        table.insert(props, { "source", source, "LazyReasonEvent" })

        -- Put in all the same properties as the original details function
        insert_lazy_props(props, plugin)

        self:props(props, { indent = 6 })
        self:nl()
      end)

      if not custom_ok then
        -- Fall back to original details function if custom details logic fails
        M.notify("Error in UI details hook: " .. tostring(custom_err), vim.log.levels.WARN)
        original_details(self, plugin)
      end
    end
  end)

  if not ok then
    M.notify("Failed to setup UI hooks: " .. tostring(err), vim.log.levels.WARN)
  end
end

function M.write_dual_lockfiles()
  local main_lockfile = LazyConfig.options.lockfile
  local existing_lockfile = M.read_lockfile(main_lockfile)

  local plugins_by_source = {}

  local all_plugins = {}

  local plugin_sources = {
    LazyConfig.plugins or {},
    LazyConfig.spec.disabled or {},
    LazyConfig.spec.plugins or {},
  }

  for _, source in ipairs(plugin_sources) do
    for _, plugin in pairs(source) do
      if plugin.name and not all_plugins[plugin.name] then
        if not (plugin._ and plugin._.is_local) then
          all_plugins[plugin.name] = plugin
        end
      end
    end
  end

  for _, plugin in pairs(all_plugins) do
    local source_repo = M.get_plugin_source(plugin.name)
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
    write_lockfile(lockfile_path, plugins)
  end
end

function M.clear_caches()
  cached_paths = nil
  cached_lazy_plugins = nil
  plugin_exists_cache = {}
  recipe_cache = {}
  git_info_cache = {}
end

return M
