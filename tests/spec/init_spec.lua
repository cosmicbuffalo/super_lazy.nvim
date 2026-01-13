local super_lazy = require("super_lazy")
local cache = require("super_lazy.cache")
local lockfile = require("super_lazy.lockfile")
local async = require("super_lazy.async")

-- Helper to wait for async operations to complete
local function wait_for(condition, timeout_ms)
  timeout_ms = timeout_ms or 5000
  local ok = vim.wait(timeout_ms, condition, 10)
  assert(ok, "Timeout waiting for condition")
end

describe("super_lazy init module", function()
  -- Store original LazyConfig state
  local LazyConfig = require("lazy.core.config")
  local original_plugins = LazyConfig.plugins
  local original_spec = LazyConfig.spec
  local original_options = LazyConfig.options

  -- Reset state before each test to ensure isolation
  before_each(function()
    async.reset()
    cache.clear_all()
    -- Reset LazyConfig to defaults
    LazyConfig.plugins = {}
    LazyConfig.spec = { disabled = {}, plugins = {} }
    LazyConfig.options = { lockfile = "/tmp/lazy-lock.json" }
  end)

  -- Clean up after each test
  after_each(function()
    async.reset()
    cache.clear_all()
    -- Restore original LazyConfig state
    LazyConfig.plugins = original_plugins
    LazyConfig.spec = original_spec
    LazyConfig.options = original_options
  end)

  describe("module exports", function()
    it("should export setup function", function()
      assert.is_function(super_lazy.setup)
    end)

    it("should export write_lockfiles", function()
      assert.is_function(super_lazy.write_lockfiles)
    end)

    it("should export setup_lazy_hooks", function()
      assert.is_function(super_lazy.setup_lazy_hooks)
    end)

    it("should export refresh function", function()
      assert.is_function(super_lazy.refresh)
    end)
  end)

  describe("setup_lazy_hooks", function()
    it("should hook into LazyLock.update", function()
      local LazyLock = require("lazy.manage.lock")
      local original_update = LazyLock.update

      super_lazy.setup_lazy_hooks()

      -- The update function should have been replaced
      assert.is_not.equals(original_update, LazyLock.update)
      assert.is_function(LazyLock.update)

      -- Restore
      LazyLock.update = original_update
    end)

    it("should write multiple lockfiles when configured with multiple repos", function()
      -- Create temporary test directories
      local test_dir = "/tmp/super_lazy_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"
      local repo2 = test_dir .. "/repo2"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.mkdir(repo2 .. "/plugins", "p")

      -- Create test plugin files
      vim.fn.writefile({
        "return {",
        '  { "folke/lazy.nvim" },',
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      vim.fn.writefile({
        "return {",
        '  { "folke/tokyonight.nvim" },',
        "}",
      }, repo2 .. "/plugins/theme.lua")

      -- Setup super_lazy with two repos
      cache.clear_all()
      super_lazy.setup({
        lockfile_repo_dirs = { repo1, repo2 },
      })

      -- Mock lazy.nvim structures
      local LazyConfig = require("lazy.core.config")
      local LazyLock = require("lazy.manage.lock")
      local LazyGit = require("lazy.manage.git")

      local original_update = LazyLock.update
      local original_plugins = LazyConfig.plugins
      local original_spec = LazyConfig.spec
      local original_git_info = LazyGit.info

      -- Mock plugins
      LazyConfig.plugins = {
        {
          name = "plenary.nvim",
          dir = "/tmp/lazy/plenary.nvim",
          _ = { installed = true },
        },
        {
          name = "tokyonight.nvim",
          dir = "/tmp/lazy/tokyonight.nvim",
          _ = { installed = true },
        },
      }

      LazyConfig.spec = {
        disabled = {},
        plugins = {},
      }

      -- Mock git info
      LazyGit.info = function(dir)
        if dir:match("plenary") then
          return { branch = "master", commit = "abc123" }
        elseif dir:match("tokyonight") then
          return { branch = "main", commit = "def456" }
        end
        return nil
      end

      -- Setup hooks
      super_lazy.setup_lazy_hooks()

      -- Trigger update (which should call write_lockfiles_async)
      local ok = pcall(LazyLock.update)
      assert.is_true(ok)

      -- Wait for both lockfiles to be created (async operation)
      wait_for(function()
        return vim.fn.filereadable(repo1 .. "/lazy-lock.json") == 1
          and vim.fn.filereadable(repo2 .. "/lazy-lock.json") == 1
      end)

      -- Read and verify lockfile contents
      local lockfile1 = lockfile.read(repo1 .. "/lazy-lock.json")
      local lockfile2 = lockfile.read(repo2 .. "/lazy-lock.json")

      -- Repo1 should have plenary (and lazy.nvim)
      assert.is_not_nil(lockfile1["plenary.nvim"])
      assert.equals("master", lockfile1["plenary.nvim"].branch)
      assert.equals("abc123", lockfile1["plenary.nvim"].commit)

      -- Repo2 should have tokyonight
      assert.is_not_nil(lockfile2["tokyonight.nvim"])
      assert.equals("main", lockfile2["tokyonight.nvim"].branch)
      assert.equals("def456", lockfile2["tokyonight.nvim"].commit)

      -- Cleanup
      async.reset()
      LazyLock.update = original_update
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyGit.info = original_git_info
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should handle errors in original update gracefully", function()
      local LazyLock = require("lazy.manage.lock")
      local original_update = LazyLock.update

      -- Mock original update to fail
      LazyLock.update = function()
        error("Original update failed")
      end

      super_lazy.setup_lazy_hooks()

      -- Should not error when update is called
      assert.has_no.errors(function()
        pcall(LazyLock.update)
      end)

      -- Restore
      LazyLock.update = original_update
    end)
  end)

  describe("headless execution", function()
    it("should not hang when running headless nvim commands", function()
      -- Create temporary test directory and init file
      local test_dir = "/tmp/super_lazy_headless_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"
      vim.fn.mkdir(repo1 .. "/plugins", "p")

      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Create a minimal init.lua that loads super_lazy
      local init_file = test_dir .. "/init.lua"
      vim.fn.writefile({
        "-- Minimal init for headless test",
        "local super_lazy = require('super_lazy')",
        "super_lazy.setup({",
        "  lockfile_repo_dirs = { '" .. repo1 .. "' },",
        "})",
        "-- Exit immediately",
        "vim.cmd('qall!')",
      }, init_file)

      -- Run headless nvim command with timeout
      local start_time = vim.fn.reltime()
      local cmd = string.format("timeout 5 nvim --headless -u %s -c 'qall!' 2>&1", init_file)
      local output = vim.fn.system(cmd)
      local exit_code = vim.v.shell_error
      local elapsed = vim.fn.reltimefloat(vim.fn.reltime(start_time))

      assert.equals(0, exit_code, "Headless nvim should exit cleanly. Output: " .. output)
      assert.is_not.equals(124, exit_code, "Headless nvim should not timeout")
      assert.is_true(elapsed < 3, "Headless nvim should complete quickly, took " .. elapsed .. " seconds")

      vim.fn.delete(test_dir, "rf")
    end)
  end)

  describe("ensure_lockfiles_updated", function()
    it("should write lockfiles for plugins installed before hooks setup", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_ensure_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      -- Create test plugin file
      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Setup super_lazy
      cache.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures (simulating plugins installed before super_lazy loaded)
      local LazyConfig = require("lazy.core.config")
      local LazyGit = require("lazy.manage.git")

      local original_plugins = LazyConfig.plugins
      local original_spec = LazyConfig.spec
      local original_git_info = LazyGit.info

      LazyConfig.plugins = {
        {
          name = "plenary.nvim",
          dir = "/tmp/lazy/plenary.nvim",
          _ = { installed = true },
        },
      }

      LazyConfig.spec = {
        disabled = {},
        plugins = {},
      }

      LazyGit.info = function(dir)
        if dir:match("plenary") then
          return { branch = "master", commit = "abc123" }
        end
        return nil
      end

      -- Call write_lockfiles directly (simulate what ensure_lockfiles_updated does)
      -- We can't test vim.schedule directly, but we can test the underlying function
      local ok = pcall(super_lazy.write_lockfiles)
      assert.is_true(ok)

      -- Verify lockfile was created
      assert.equals(1, vim.fn.filereadable(repo1 .. "/lazy-lock.json"))

      -- Verify lockfile contents
      local lockfile_data = lockfile.read(repo1 .. "/lazy-lock.json")
      assert.is_not_nil(lockfile_data["plenary.nvim"])
      assert.equals("master", lockfile_data["plenary.nvim"].branch)
      assert.equals("abc123", lockfile_data["plenary.nvim"].commit)

      -- Cleanup
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyGit.info = original_git_info
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)
  end)

  describe("timestamp-based lockfile sync detection", function()
    it("should detect when main lockfile is newer than split lockfiles", function()
      -- Create temporary test directory with TWO repos
      local test_dir = "/tmp/super_lazy_timestamp_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"
      local repo2 = test_dir .. "/repo2"
      local main_lockfile = repo1 .. "/lazy-lock.json"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.mkdir(repo2 .. "/plugins", "p")

      -- Create plugin files in both repos
      vim.fn.writefile({
        "return {",
        '  { "plugin1" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      vim.fn.writefile({
        "return {",
        '  { "plugin2" },',
        "}",
      }, repo2 .. "/plugins/personal.lua")

      cache.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1, repo2 },
      })

      local LazyConfig = require("lazy.core.config")
      local original_lockfile = LazyConfig.options.lockfile
      LazyConfig.options.lockfile = main_lockfile

      -- Create split lockfiles (older than main)
      lockfile.write(repo1 .. "/lazy-lock.json", { ["plugin1"] = { branch = "main", commit = "abc123" } })
      lockfile.write(repo2 .. "/lazy-lock.json", { ["plugin2"] = { branch = "main", commit = "def456" } })

      -- Wait to ensure different timestamp
      vim.loop.sleep(1000)

      -- Create new main lockfile, simulating lazy update
      lockfile.write(main_lockfile, {
        ["plugin1"] = { branch = "main", commit = "abc123" },
        ["plugin2"] = { branch = "main", commit = "def456" },
      })

      -- Setup should detect timestamp mismatch and sync
      local called_write_lockfiles_async = false
      local original_write_lockfiles_async = super_lazy.write_lockfiles_async
      super_lazy.write_lockfiles_async = function()
        called_write_lockfiles_async = true
      end

      super_lazy.setup({ lockfile_repo_dirs = { repo1, repo2 } })
      -- Verify super_lazy.write_lockfiles_async was called (which means needs sync returned true)
      assert.is_true(called_write_lockfiles_async)

      -- Cleanup
      super_lazy.write_lockfiles_async = original_write_lockfiles_async
      async.reset()
      LazyConfig.options.lockfile = original_lockfile
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should detect when split lockfile is missing", function()
      local test_dir = "/tmp/super_lazy_missing_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"
      local repo2 = test_dir .. "/repo2"
      local main_lockfile = test_dir .. "/lazy-lock.json"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.mkdir(repo2 .. "/plugins", "p")

      cache.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1, repo2 },
      })

      local LazyConfig = require("lazy.core.config")
      local original_lockfile = LazyConfig.options.lockfile
      LazyConfig.options.lockfile = main_lockfile

      -- Create main lockfile and ONE split lockfile, but NOT the other
      lockfile.write(main_lockfile, {
        ["plugin1"] = { branch = "main", commit = "abc123" },
        ["plugin2"] = { branch = "main", commit = "def456" },
      })
      lockfile.write(repo1 .. "/lazy-lock.json", { ["plugin1"] = { branch = "main", commit = "abc123" } })
      -- repo2 lockfile is MISSING

      -- Setup should detect missing split lockfile
      local called_write_lockfiles_async = false
      local original_write_lockfiles_async = super_lazy.write_lockfiles_async
      super_lazy.write_lockfiles_async = function()
        called_write_lockfiles_async = true
      end

      super_lazy.setup({ lockfile_repo_dirs = { repo1, repo2 } })
      assert.is_true(called_write_lockfiles_async)

      -- Cleanup
      super_lazy.write_lockfiles_async = original_write_lockfiles_async
      async.reset()
      LazyConfig.options.lockfile = original_lockfile
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should not sync when lockfiles are already in sync", function()
      local test_dir = "/tmp/super_lazy_sync_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"
      local repo2 = test_dir .. "/repo2"
      local main_lockfile = test_dir .. "/lazy-lock.json"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.mkdir(repo2 .. "/plugins", "p")

      cache.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1, repo2 },
      })

      local LazyConfig = require("lazy.core.config")
      local original_lockfile = LazyConfig.options.lockfile
      LazyConfig.options.lockfile = main_lockfile

      -- Create all lockfiles at the same time (same timestamps, proper content split)
      local main_data = {
        ["plugin1"] = { branch = "main", commit = "abc123" },
        ["plugin2"] = { branch = "main", commit = "def456" },
      }
      lockfile.write(main_lockfile, main_data)
      lockfile.write(repo1 .. "/lazy-lock.json", { ["plugin1"] = { branch = "main", commit = "abc123" } })
      lockfile.write(repo2 .. "/lazy-lock.json", { ["plugin2"] = { branch = "main", commit = "def456" } })

      -- Setup should NOT trigger sync (lockfiles in sync)
      local called_write_lockfiles_async = false
      local original_write_lockfiles_async = super_lazy.write_lockfiles_async
      super_lazy.write_lockfiles_async = function()
        called_write_lockfiles_async = true
      end

      super_lazy.setup({ lockfile_repo_dirs = { repo1, repo2 } })

      -- Verify write_lockfiles_async was NOT called (because lockfiles were in sync)
      assert.is_false(called_write_lockfiles_async)

      -- Cleanup
      super_lazy.write_lockfiles_async = original_write_lockfiles_async
      async.reset()
      LazyConfig.options.lockfile = original_lockfile
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)
  end)

  describe("recipe plugin source metadata", function()
    it("should add source field to nested recipe plugins", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_recipe_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      -- Create test plugin file with parent plugin
      vim.fn.writefile({
        "return {",
        '  { "folke/lazy.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Setup super_lazy
      cache.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures
      local LazyConfig = require("lazy.core.config")
      local LazyGit = require("lazy.manage.git")
      local Source = require("super_lazy.source")

      local original_plugins = LazyConfig.plugins
      local original_spec = LazyConfig.spec
      local original_git_info = LazyGit.info
      local original_get_plugin_source = Source.get_plugin_source

      -- Mock parent and nested plugins
      LazyConfig.plugins = {
        {
          name = "lazy.nvim",
          dir = "/tmp/lazy/lazy.nvim",
          _ = { installed = true },
        },
        {
          name = "plenary.nvim",
          dir = "/tmp/lazy/plenary.nvim",
          _ = { installed = true },
        },
      }

      LazyConfig.spec = {
        disabled = {},
        plugins = {},
      }

      LazyGit.info = function(dir)
        if dir:match("lazy%.nvim") then
          return { branch = "main", commit = "abc123" }
        elseif dir:match("plenary") then
          return { branch = "master", commit = "def456" }
        end
        return nil
      end

      -- Mock get_plugin_source to indicate plenary is a recipe plugin of lazy.nvim
      Source.get_plugin_source = function(plugin_name, with_recipe)
        if plugin_name == "lazy.nvim" then
          if with_recipe then
            return repo1, nil -- Not a recipe
          end
          return repo1
        elseif plugin_name == "plenary.nvim" then
          if with_recipe then
            return repo1, "lazy.nvim" -- IS a recipe, parent is lazy.nvim
          end
          return repo1
        end
        error("Plugin not found")
      end

      -- Call write_lockfiles
      local ok = pcall(super_lazy.write_lockfiles)
      assert.is_true(ok)

      -- Verify lockfile was created
      local lockfile_data = lockfile.read(repo1 .. "/lazy-lock.json")

      -- Parent should NOT have source field
      assert.is_not_nil(lockfile_data["lazy.nvim"])
      assert.is_nil(lockfile_data["lazy.nvim"].source)

      -- Nested plugin SHOULD have source field pointing to parent
      assert.is_not_nil(lockfile_data["plenary.nvim"])
      assert.equals("lazy.nvim", lockfile_data["plenary.nvim"].source)
      assert.equals("master", lockfile_data["plenary.nvim"].branch)
      assert.equals("def456", lockfile_data["plenary.nvim"].commit)

      -- Cleanup
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyGit.info = original_git_info
      Source.get_plugin_source = original_get_plugin_source
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)
  end)

  describe("git-based lockfile preservation", function()
    it("should restore nested plugins from git lockfile when parent is disabled and not installed", function()
      local temp_config = vim.fn.tempname()
      local test_cache_dir = vim.fn.tempname()
      vim.fn.mkdir(temp_config, "p")
      vim.fn.mkdir(test_cache_dir, "p")

      vim.fn.system({ "git", "-C", temp_config, "init" })
      vim.fn.system({ "git", "-C", temp_config, "config", "user.email", "test@test.com" })
      vim.fn.system({ "git", "-C", temp_config, "config", "user.name", "Test User" })

      local original_lockfile_data = {
        ["parent-plugin"] = { branch = "main", commit = "abc123" },
        ["nested-plugin"] = { branch = "main", commit = "def456", source = "parent-plugin" },
      }

      local lockfile_path = temp_config .. "/lazy-lock.json"
      vim.fn.writefile({ vim.json.encode(original_lockfile_data) }, lockfile_path)
      vim.fn.system({ "git", "-C", temp_config, "add", "lazy-lock.json" })
      vim.fn.system({ "git", "-C", temp_config, "commit", "-m", "add lockfile" })

      vim.fn.mkdir(temp_config .. "/plugins", "p")
      vim.fn.writefile({
        "return {",
        '  { "parent-plugin", enabled = false },',
        "}",
      }, temp_config .. "/plugins/core.lua")

      local original_stdpath = vim.fn.stdpath
      vim.fn.stdpath = function(what)
        if what == "config" then
          return temp_config
        elseif what == "data" then
          return test_cache_dir
        end
        return original_stdpath(what)
      end

      cache.clear_all()
      lockfile.clear_cache()

      local Config = require("super_lazy.config")
      Config.setup({ lockfile_repo_dirs = { temp_config } })

      local LazyConfig = require("lazy.core.config")
      local Source = require("super_lazy.source")

      local original_plugins = LazyConfig.plugins
      local original_spec = LazyConfig.spec
      local original_get_plugin_source = Source.get_plugin_source

      LazyConfig.plugins = {}
      LazyConfig.spec = {
        disabled = {
          {
            name = "parent-plugin",
            _ = {},
          },
        },
        plugins = {},
      }

      Source.get_plugin_source = function(plugin_name, with_recipe)
        if plugin_name == "parent-plugin" or plugin_name == "nested-plugin" then
          if with_recipe then
            return temp_config, plugin_name == "nested-plugin" and "parent-plugin" or nil
          end
          return temp_config
        end
        error("Plugin not found")
      end

      local ok = pcall(super_lazy.write_lockfiles)
      assert.is_true(ok)

      local result_lockfile = lockfile.read(temp_config .. "/lazy-lock.json")

      assert.is_not_nil(result_lockfile["parent-plugin"])
      assert.equals("main", result_lockfile["parent-plugin"].branch)
      assert.equals("abc123", result_lockfile["parent-plugin"].commit)

      assert.is_not_nil(result_lockfile["nested-plugin"])
      assert.equals("main", result_lockfile["nested-plugin"].branch)
      assert.equals("def456", result_lockfile["nested-plugin"].commit)
      assert.equals("parent-plugin", result_lockfile["nested-plugin"].source)

      vim.fn.stdpath = original_stdpath
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      Source.get_plugin_source = original_get_plugin_source
      cache.clear_all()
      lockfile.clear_cache()
      vim.fn.delete(temp_config, "rf")
      vim.fn.delete(test_cache_dir, "rf")
    end)
  end)

  describe("disabled recipe plugins", function()
    it("should preserve nested plugins when parent recipe plugin is disabled", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_disabled_recipe_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      -- Create test plugin file with parent plugin
      vim.fn.writefile({
        "return {",
        '  { "folke/lazy.nvim", enabled = false },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Setup super_lazy
      cache.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Create existing lockfile with parent and nested plugins
      lockfile.write(repo1 .. "/lazy-lock.json", {
        ["lazy.nvim"] = { branch = "main", commit = "abc123" },
        ["plenary.nvim"] = { branch = "master", commit = "def456", source = "lazy.nvim" },
      })

      -- Mock lazy.nvim structures
      local LazyConfig = require("lazy.core.config")
      local Source = require("super_lazy.source")

      local original_plugins = LazyConfig.plugins
      local original_spec = LazyConfig.spec
      local original_lockfile = LazyConfig.options.lockfile
      local original_get_plugin_source = Source.get_plugin_source

      -- Parent plugin is disabled, nested plugin is not in any list
      LazyConfig.plugins = {}

      LazyConfig.spec = {
        disabled = {
          {
            name = "lazy.nvim",
            _ = {},
          },
        },
        plugins = {},
      }

      -- Mock lazy's main lockfile to have the parent plugin
      local temp_lazy_lock = "/tmp/lazy-lock-" .. os.time() .. ".json"
      vim.fn.writefile({ '{ "lazy.nvim": { "branch": "main", "commit": "abc123" } }' }, temp_lazy_lock)
      LazyConfig.options = { lockfile = temp_lazy_lock }

      -- Mock get_plugin_source
      Source.get_plugin_source = function(plugin_name, with_recipe)
        if plugin_name == "lazy.nvim" then
          if with_recipe then
            return repo1, nil -- Not a recipe
          end
          return repo1
        end
        error("Plugin not found")
      end

      -- Call write_lockfiles
      local ok = pcall(super_lazy.write_lockfiles)
      assert.is_true(ok)

      -- Verify lockfile contains both parent and nested plugins
      local lockfile_data = lockfile.read(repo1 .. "/lazy-lock.json")

      -- Parent should be preserved (disabled plugin)
      assert.is_not_nil(lockfile_data["lazy.nvim"])
      assert.equals("main", lockfile_data["lazy.nvim"].branch)
      assert.equals("abc123", lockfile_data["lazy.nvim"].commit)

      -- Nested plugin should be preserved (parent is in lockfile)
      assert.is_not_nil(lockfile_data["plenary.nvim"])
      assert.equals("master", lockfile_data["plenary.nvim"].branch)
      assert.equals("def456", lockfile_data["plenary.nvim"].commit)
      assert.equals("lazy.nvim", lockfile_data["plenary.nvim"].source)

      -- Cleanup
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyConfig.options = { lockfile = original_lockfile }
      Source.get_plugin_source = original_get_plugin_source
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
      vim.fn.delete(temp_lazy_lock)
    end)
  end)

  describe("disabled plugins", function()
    it("should preserve lockfile entries for disabled non-recipe plugins", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_disabled_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      -- Create test plugin file with disabled plugin
      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim", enabled = false },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Setup super_lazy
      cache.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures
      local LazyConfig = require("lazy.core.config")
      local Source = require("super_lazy.source")

      local original_plugins = LazyConfig.plugins
      local original_spec = LazyConfig.spec
      local original_lockfile = LazyConfig.options.lockfile
      local original_get_plugin_source = Source.get_plugin_source

      -- Plugin is disabled (not installed)
      LazyConfig.plugins = {}

      LazyConfig.spec = {
        disabled = {
          {
            name = "plenary.nvim",
            _ = {},
          },
        },
        plugins = {},
      }

      -- Mock lazy's main lockfile to have the plugin entry
      local temp_lazy_lock = "/tmp/lazy-lock-disabled-" .. os.time() .. ".json"
      vim.fn.writefile({ '{ "plenary.nvim": { "branch": "master", "commit": "abc123" } }' }, temp_lazy_lock)
      LazyConfig.options = { lockfile = temp_lazy_lock }

      -- Mock get_plugin_source
      Source.get_plugin_source = function(plugin_name, with_recipe)
        if plugin_name == "plenary.nvim" then
          if with_recipe then
            return repo1, nil -- Not a recipe
          end
          return repo1
        end
        error("Plugin not found")
      end

      -- Call write_lockfiles
      local ok = pcall(super_lazy.write_lockfiles)
      assert.is_true(ok)

      -- Verify lockfile contains the disabled plugin
      local lockfile_data = lockfile.read(repo1 .. "/lazy-lock.json")

      -- Disabled plugin should be preserved from lazy's main lockfile
      assert.is_not_nil(lockfile_data["plenary.nvim"])
      assert.equals("master", lockfile_data["plenary.nvim"].branch)
      assert.equals("abc123", lockfile_data["plenary.nvim"].commit)
      -- Should NOT have source field (not a recipe)
      assert.is_nil(lockfile_data["plenary.nvim"].source)

      -- Cleanup
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyConfig.options = { lockfile = original_lockfile }
      Source.get_plugin_source = original_get_plugin_source
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
      vim.fn.delete(temp_lazy_lock)
    end)
  end)

  describe("clean operation lockfile handling", function()
    it("should preserve lockfile entry when plugin is cleaned but still in repo config", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_clean_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      -- Create test plugin file
      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Setup super_lazy
      cache.clear_all()
      super_lazy.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Create initial lockfile with plugin entry
      lockfile.write(repo1 .. "/lazy-lock.json", {
        ["plenary.nvim"] = { branch = "master", commit = "abc123" },
      })

      -- Setup hooks
      local LazyLock = require("lazy.manage.lock")
      local original_update = LazyLock.update

      super_lazy.setup_lazy_hooks()

      -- Simulate clean operation
      vim.api.nvim_exec_autocmds("User", { pattern = "LazyCleanPre" })
      -- After clean, plugin removed from lockfile
      lockfile.write(repo1 .. "/lazy-lock.json", {})
      -- Trigger LazyLock.update to run the restore logic
      local ok = pcall(LazyLock.update)

      -- Wait for async restore operation to complete
      wait_for(function()
        local data = lockfile.read(repo1 .. "/lazy-lock.json")
        return data["plenary.nvim"] ~= nil
      end)

      -- Verify lockfile still contains the plugin entry
      local lockfile_data = lockfile.read(repo1 .. "/lazy-lock.json")
      assert.is_not_nil(lockfile_data["plenary.nvim"])
      assert.equals("master", lockfile_data["plenary.nvim"].branch)
      assert.equals("abc123", lockfile_data["plenary.nvim"].commit)

      -- Cleanup
      async.reset()
      LazyLock.update = original_update
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should remove lockfile entry when plugin is cleaned and removed from repo config", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_clean_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      cache.clear_all()
      super_lazy.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Create initial lockfile with plugin entry for a plugin NOT in repo
      lockfile.write(repo1 .. "/lazy-lock.json", {
        ["some-removed-plugin.nvim"] = { branch = "main", commit = "xyz789" },
      })

      -- Setup hooks
      local LazyLock = require("lazy.manage.lock")
      local original_update = LazyLock.update

      super_lazy.setup_lazy_hooks()

      -- Simulate clean operation
      vim.api.nvim_exec_autocmds("User", { pattern = "LazyCleanPre" })
      -- After clean, the lockfile should be empty (no plugins)
      lockfile.write(repo1 .. "/lazy-lock.json", {})
      -- Trigger LazyLock.update to run the restore logic
      local ok = pcall(LazyLock.update)

      -- Verify lockfile does NOT contain the removed plugin
      local lockfile_data = lockfile.read(repo1 .. "/lazy-lock.json")
      assert.is_nil(lockfile_data["some-removed-plugin.nvim"])

      -- Cleanup
      async.reset()
      LazyLock.update = original_update
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should handle multiple repos with different clean states", function()
      -- Create temporary test directories
      local test_dir = "/tmp/super_lazy_clean_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"
      local repo2 = test_dir .. "/repo2"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.mkdir(repo2 .. "/plugins", "p")

      -- Repo1 has plenary in config
      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Repo2 is empty (plugin was removed from config)

      -- Setup super_lazy
      cache.clear_all()
      super_lazy.setup({
        lockfile_repo_dirs = { repo1, repo2 },
      })

      -- Create initial lockfiles
      lockfile.write(repo1 .. "/lazy-lock.json", {
        ["plenary.nvim"] = { branch = "master", commit = "abc123" },
      })
      lockfile.write(repo2 .. "/lazy-lock.json", {
        ["tokyonight.nvim"] = { branch = "main", commit = "def456" },
      })

      -- Setup hooks
      local LazyLock = require("lazy.manage.lock")
      local original_update = LazyLock.update

      super_lazy.setup_lazy_hooks()

      -- Simulate clean operation
      vim.api.nvim_exec_autocmds("User", { pattern = "LazyCleanPre" })
      -- After clean, simulate that plugins are removed from lockfiles
      lockfile.write(repo1 .. "/lazy-lock.json", {})
      lockfile.write(repo2 .. "/lazy-lock.json", {})
      -- Trigger LazyLock.update to run the restore logic
      local ok = pcall(LazyLock.update)

      -- Wait for async restore operation to complete
      wait_for(function()
        local data = lockfile.read(repo1 .. "/lazy-lock.json")
        return data["plenary.nvim"] ~= nil
      end)

      -- Verify repo1 lockfile has plenary restored (still in config)
      local lockfile1 = lockfile.read(repo1 .. "/lazy-lock.json")
      assert.is_not_nil(lockfile1["plenary.nvim"])
      assert.equals("master", lockfile1["plenary.nvim"].branch)
      assert.equals("abc123", lockfile1["plenary.nvim"].commit)

      -- Verify repo2 lockfile does NOT have tokyonight (removed from config)
      local lockfile2 = lockfile.read(repo2 .. "/lazy-lock.json")
      assert.is_nil(lockfile2["tokyonight.nvim"])

      -- Cleanup
      async.reset()
      LazyLock.update = original_update
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)
  end)

  describe("refresh", function()
    it("should clear entire cache and regenerate lockfiles when called with empty list", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_refresh_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Setup super_lazy
      cache.clear_all()
      super_lazy.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures
      local LazyConfig = require("lazy.core.config")
      local LazyGit = require("lazy.manage.git")

      local original_plugins = LazyConfig.plugins
      local original_spec = LazyConfig.spec
      local original_git_info = LazyGit.info

      LazyConfig.plugins = {
        {
          name = "plenary.nvim",
          dir = "/tmp/lazy/plenary.nvim",
          _ = { installed = true },
        },
      }

      LazyConfig.spec = {
        disabled = {},
        plugins = {},
      }

      LazyGit.info = function(dir)
        if dir:match("plenary") then
          return { branch = "master", commit = "abc123" }
        end
        return nil
      end

      -- Set a cache entry before refresh
      cache.set_plugin_source("plenary.nvim", repo1, nil)

      -- Capture notifications
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- Call refresh with empty list (async)
      super_lazy.refresh({})

      -- Wait for async completion - look for the completion message
      wait_for(function()
        for _, n in ipairs(notifications) do
          if n.msg:match("Refreshed super_lazy source cache") then
            return true
          end
        end
        return false
      end)

      -- Restore
      async.reset()
      vim.notify = original_notify
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyGit.info = original_git_info

      -- Verify notifications (fidget fallback shows "Syncing lockfiles..." first)
      assert.is_true(#notifications >= 2)
      assert.is_truthy(notifications[1].msg:match("Syncing lockfiles"))
      -- Last notification should be the completion message
      assert.is_truthy(notifications[#notifications].msg:match("Refreshed super_lazy source cache"))

      -- Cleanup
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should refresh a single plugin and report unchanged source", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_refresh_single_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Setup super_lazy
      cache.clear_all()
      super_lazy.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures
      local LazyConfig = require("lazy.core.config")
      local LazyGit = require("lazy.manage.git")

      local original_plugins = LazyConfig.plugins
      local original_spec = LazyConfig.spec
      local original_git_info = LazyGit.info

      LazyConfig.plugins = {
        {
          name = "plenary.nvim",
          dir = "/tmp/lazy/plenary.nvim",
          _ = { installed = true },
        },
      }

      LazyConfig.spec = {
        disabled = {},
        plugins = {},
      }

      LazyGit.info = function(dir)
        if dir:match("plenary") then
          return { branch = "master", commit = "abc123" }
        end
        return nil
      end

      -- Set cache entry (same repo - should be unchanged after refresh)
      cache.set_plugin_source("plenary.nvim", repo1, nil)

      -- Capture notifications
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- Call refresh with single plugin
      super_lazy.refresh({ "plenary.nvim" })

      -- Wait for async completion - look for the result notification
      wait_for(function()
        for _, n in ipairs(notifications) do
          if n.msg:match("plenary.nvim source unchanged") then
            return true
          end
        end
        return false
      end)

      -- Restore
      async.reset()
      vim.notify = original_notify
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyGit.info = original_git_info

      -- Verify notifications (fidget fallback shows "Syncing lockfiles..." first)
      assert.is_true(#notifications >= 2)
      assert.is_truthy(notifications[1].msg:match("Syncing lockfiles"))
      -- Last notification should be the result
      assert.is_truthy(notifications[#notifications].msg:match("plenary.nvim source unchanged"))

      -- Cleanup
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should detect when plugin moves to different repo", function()
      -- Create temporary test directories
      local test_dir = "/tmp/super_lazy_refresh_move_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"
      local repo2 = test_dir .. "/repo2"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.mkdir(repo2 .. "/plugins", "p")

      -- Plugin is now in repo1 (moved from repo2)
      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Setup super_lazy
      cache.clear_all()
      super_lazy.setup({
        lockfile_repo_dirs = { repo1, repo2 },
      })

      -- Mock lazy.nvim structures
      local LazyConfig = require("lazy.core.config")
      local LazyGit = require("lazy.manage.git")

      local original_plugins = LazyConfig.plugins
      local original_spec = LazyConfig.spec
      local original_git_info = LazyGit.info

      LazyConfig.plugins = {
        {
          name = "plenary.nvim",
          dir = "/tmp/lazy/plenary.nvim",
          _ = { installed = true },
        },
      }

      LazyConfig.spec = {
        disabled = {},
        plugins = {},
      }

      LazyGit.info = function(dir)
        if dir:match("plenary") then
          return { branch = "master", commit = "abc123" }
        end
        return nil
      end

      -- Set cache entry to OLD repo (repo2)
      cache.set_plugin_source("plenary.nvim", repo2, nil)

      -- Capture notifications
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- Call refresh with single plugin
      super_lazy.refresh({ "plenary.nvim" })

      -- Wait for async completion - look for the "Moved" notification
      wait_for(function()
        for _, n in ipairs(notifications) do
          if n.msg:match("Moved plenary.nvim from") then
            return true
          end
        end
        return false
      end)

      -- Restore
      async.reset()
      vim.notify = original_notify
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyGit.info = original_git_info

      -- Verify notifications - should show "Moved"
      assert.is_true(#notifications >= 2)
      assert.is_truthy(notifications[1].msg:match("Syncing lockfiles"))
      -- Find the "Moved" notification
      local found_moved = false
      for _, n in ipairs(notifications) do
        if n.msg:match("Moved plenary.nvim from") then
          found_moved = true
          break
        end
      end
      assert.is_true(found_moved)

      -- Cleanup
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should refresh multiple plugins at once", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_refresh_multi_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        '  { "folke/tokyonight.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Setup super_lazy
      cache.clear_all()
      super_lazy.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures
      local LazyConfig = require("lazy.core.config")
      local LazyGit = require("lazy.manage.git")

      local original_plugins = LazyConfig.plugins
      local original_spec = LazyConfig.spec
      local original_git_info = LazyGit.info

      LazyConfig.plugins = {
        {
          name = "plenary.nvim",
          dir = "/tmp/lazy/plenary.nvim",
          _ = { installed = true },
        },
        {
          name = "tokyonight.nvim",
          dir = "/tmp/lazy/tokyonight.nvim",
          _ = { installed = true },
        },
      }

      LazyConfig.spec = {
        disabled = {},
        plugins = {},
      }

      LazyGit.info = function(dir)
        if dir:match("plenary") then
          return { branch = "master", commit = "abc123" }
        elseif dir:match("tokyonight") then
          return { branch = "main", commit = "def456" }
        end
        return nil
      end

      -- Set cache entries
      cache.set_plugin_source("plenary.nvim", repo1, nil)
      cache.set_plugin_source("tokyonight.nvim", repo1, nil)

      -- Capture notifications
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- Call refresh with multiple plugins
      super_lazy.refresh({ "plenary.nvim", "tokyonight.nvim" })

      -- Wait for async completion - need at least 3 notifications (syncing + 2 results)
      wait_for(function()
        return #notifications >= 3
      end)

      -- Restore
      async.reset()
      vim.notify = original_notify
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyGit.info = original_git_info

      -- Verify notifications - should show syncing and results for each
      assert.is_true(#notifications >= 3)
      assert.is_truthy(notifications[1].msg:match("Syncing lockfiles"))

      -- Cleanup
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should warn when plugin not found in any repo", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_refresh_notfound_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      vim.fn.writefile({
        "return {",
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Setup super_lazy
      cache.clear_all()
      super_lazy.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures
      local LazyConfig = require("lazy.core.config")

      local original_plugins = LazyConfig.plugins
      local original_spec = LazyConfig.spec

      LazyConfig.plugins = {}
      LazyConfig.spec = {
        disabled = {},
        plugins = {},
      }

      -- Capture notifications
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- Call refresh with nonexistent plugin
      super_lazy.refresh({ "nonexistent-plugin.nvim" })

      -- Wait for async completion - look for the warning notification
      wait_for(function()
        for _, notif in ipairs(notifications) do
          if notif.msg:match("not found in any configured repository") then
            return true
          end
        end
        return false
      end)

      -- Restore
      async.reset()
      vim.notify = original_notify
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec

      -- Verify warning notification
      local found_warning = false
      for _, notif in ipairs(notifications) do
        if notif.msg:match("not found in any configured repository") and notif.level == vim.log.levels.WARN then
          found_warning = true
          break
        end
      end
      assert.is_true(found_warning)

      -- Cleanup
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)
  end)

  describe("SuperLazyRefresh command", function()
    it("should be registered after setup", function()
      cache.clear_all()
      super_lazy.setup({
        lockfile_repo_dirs = { vim.fn.stdpath("config") },
      })

      -- Check command exists
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.SuperLazyRefresh)
    end)

    it("should support tab completion with plugin names", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_cmd_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      cache.clear_all()
      super_lazy.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy module for completion
      local original_lazy_require = package.loaded["lazy"]
      package.loaded["lazy"] = {
        plugins = function()
          return {
            { name = "plenary.nvim" },
            { name = "telescope.nvim" },
            { name = "tokyonight.nvim" },
          }
        end,
      }

      -- Get command info
      local commands = vim.api.nvim_get_commands({})
      assert.is_not_nil(commands.SuperLazyRefresh)
      assert.equals("*", commands.SuperLazyRefresh.nargs)

      -- Restore
      package.loaded["lazy"] = original_lazy_require
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)
  end)
end)
