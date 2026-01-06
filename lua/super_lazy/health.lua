local M = {}

local Config = require("super_lazy.config")

-- Use the recommended health functions (with fallback for older Neovim)
local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error
local info = vim.health.info or vim.health.report_info

function M.check()
  start("Compatibility")

  -- Check Neovim version
  local nvim_version = vim.version()
  if nvim_version.major == 0 and nvim_version.minor < 8 then
    error(
      ("Neovim >= 0.8.0 is required (found `%d.%d.%d`)"):format(
        nvim_version.major,
        nvim_version.minor,
        nvim_version.patch
      ),
      {
        "Please upgrade Neovim to version 0.8.0 or higher",
      }
    )
  else
    ok(("Neovim version `%d.%d.%d`"):format(nvim_version.major, nvim_version.minor, nvim_version.patch))
  end

  -- Check if lazy.nvim is installed
  local lazy_ok = pcall(require, "lazy")
  if not lazy_ok then
    error("{lazy.nvim}  is not installed", {
      "super_lazy.nvim requires lazy.nvim to be installed",
      "See: https://github.com/folke/lazy.nvim",
    })
    return
  else
    ok("{lazy.nvim}  is installed")
  end

  -- Check lazy.nvim version
  local LazyGit = require("lazy.manage.git")
  local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

  if vim.fn.isdirectory(lazypath) == 0 then
    warn("lazy.nvim directory not found at `" .. lazypath .. "`")
  else
    local git_info = LazyGit.info(lazypath, true)
    if git_info and git_info.version then
      local installed_version = tostring(git_info.version)
      if installed_version == Config.COMPATIBLE_LAZY_VERSION then
        ok(("lazy.nvim version `%s` (compatible)"):format(installed_version))
      else
        warn(
          ("lazy.nvim version mismatch: expected `%s`, found `%s`"):format(
            Config.COMPATIBLE_LAZY_VERSION,
            installed_version
          ),
          {
            "Some features may not work correctly",
            "Consider pinning to lazy.nvim " .. Config.COMPATIBLE_LAZY_VERSION .. " if you run into lockfile issues",
          }
        )
      end
    else
      warn(
        ("Could not determine lazy.nvim version"),
        {
          "Expected version: `" .. Config.COMPATIBLE_LAZY_VERSION .. "`",
          "If hooks checks below are OK then this may be safe to ignore"
        }
      )
    end
  end

  start("Hooks")
  local LazyConfig = require("lazy.core.config")
  if LazyConfig.plugins then
    ok("{lazy.core.config.plugins}  is available")
  else
    error("{lazy.core.config.plugins}  is not available", {
      "This is required for super_lazy.nvim to work",
      "Please ensure lazy.nvim is properly installed",
    })
  end

  if LazyConfig.spec then
    ok("{lazy.core.config.spec}  is available")
  else
    error("{lazy.core.config.spec}  is not available", {
      "This is required for super_lazy.nvim to work",
      "Please ensure lazy.nvim is properly installed",
    })
  end

  local LazyLock = require("lazy.manage.lock")
  if LazyLock.update then
    ok("{lazy.manage.lock.update}  is available")
  else
    error("{lazy.manage.lock.update}  is not available", {
      "This is required for super_lazy.nvim to work",
      "Please ensure lazy.nvim is properly installed",
    })
  end

  local LazyRender = require("lazy.view.render")
  if LazyRender.details then
    ok("{lazy.view.render.details}  is available")
  else
    error("{lazy.view.render.details}  is not available", {
      "This is required for super_lazy.nvim to work",
      "Please ensure lazy.nvim is properly installed",
    })
  end

  -- Check configuration
  start("Configuration")

  if not Config.options or not Config.options.lockfile_repo_dirs then
    warn("super_lazy.nvim is not configured", {
      "Run require('super_lazy').setup() in your config",
    })
    return
  end

  local repo_dirs = Config.options.lockfile_repo_dirs
  if type(repo_dirs) ~= "table" or #repo_dirs == 0 then
    error("{lockfile_repo_dirs} is empty or invalid", {
      "Please configure at least one repository directory",
      "Example: lockfile_repo_dirs = { vim.fn.stdpath('config') }",
    })
  else
    ok(("Configured with `%d` lockfile repository directory(s)"):format(#repo_dirs))

    -- Check each repository directory
    for i, dir in ipairs(repo_dirs) do
      local real_path = vim.fn.resolve(dir)
      if vim.fn.isdirectory(real_path) == 1 then
        ok(("  [%d] `%s` (exists)"):format(i, real_path))

        -- Check for lockfile
        local lockfile_path = real_path .. "/lazy-lock.json"
        if vim.fn.filereadable(lockfile_path) == 1 then
          info("      `" .. lockfile_path .. "` exists")
        else
          info("      `" .. lockfile_path .. "` will be created on next update")
        end
        -- Check for plugins directory (both path/plugins and path/lua/plugins)
        local plugins_dir = real_path .. "/plugins"
        local lua_plugins_dir = real_path .. "/lua/plugins"
        local plugins_dir_exists = vim.fn.isdirectory(plugins_dir) == 1
        local lua_plugins_dir_exists = vim.fn.isdirectory(lua_plugins_dir) == 1

        if plugins_dir_exists or lua_plugins_dir_exists then
          local total_files = 0
          local locations = {}

          if plugins_dir_exists then
            local plugin_files = vim.fn.glob(plugins_dir .. "/**/*.lua", true, true)
            total_files = total_files + #plugin_files
            table.insert(locations, ("`" .. real_path .. "/plugins/`"))
          end

          if lua_plugins_dir_exists then
            local lua_plugin_files = vim.fn.glob(lua_plugins_dir .. "/**/*.lua", true, true)
            total_files = total_files + #lua_plugin_files
            table.insert(locations, ("`" .. real_path .. "/lua/plugins/`"))
          end

          info(("      Found `%d` plugin file(s) in: %s"):format(total_files, table.concat(locations, ", ")))
        else
          warn("      No `plugins/` or `lua/plugins/` directory found", {
            "Create a `plugins/` or `lua/plugins/` directory and add your plugin specifications there",
          })
        end
      else
        error(("  [%d] `%s` (does not exist)"):format(i, dir), {
          "Please ensure the directory exists",
        })
      end
    end
  end
end

return M
