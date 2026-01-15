local Ops = require("super_lazy.ops")
local Source = require("super_lazy.source")
local lockfile = require("super_lazy.lockfile")

-- Helper to wait for async operations to complete
local function wait_for(condition, timeout_ms)
  timeout_ms = timeout_ms or 5000
  local ok = vim.wait(timeout_ms, condition, 10)
  assert(ok, "Timeout waiting for condition")
end

describe("super_lazy ops module", function()
  -- Store original LazyConfig state
  local LazyConfig = require("lazy.core.config")
  local original_plugins = LazyConfig.plugins
  local original_spec = LazyConfig.spec
  local original_options = LazyConfig.options

  -- Reset state before each test to ensure isolation
  before_each(function()
    Source.clear_all()
    -- Reset LazyConfig to defaults
    LazyConfig.plugins = {}
    LazyConfig.spec = { disabled = {}, plugins = {} }
    LazyConfig.options = { lockfile = "/tmp/lazy-lock.json" }
  end)

  -- Clean up after each test
  after_each(function()
    Source.clear_all()
    -- Restore original LazyConfig state
    LazyConfig.plugins = original_plugins
    LazyConfig.spec = original_spec
    LazyConfig.options = original_options
  end)

  describe("setup_lazy_hooks", function()
    it("should hook into LazyLock.update", function()
      local LazyLock = require("lazy.manage.lock")
      local original_update = LazyLock.update

      Ops.setup_lazy_hooks()

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

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1, repo2 },
      })

      -- Mock lazy.nvim structures
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
      Ops.setup_lazy_hooks()

      -- Trigger update (which should call write_lockfiles)
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
      LazyLock.update = original_update
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyGit.info = original_git_info
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should handle errors in original update gracefully", function()
      local LazyLock = require("lazy.manage.lock")
      local original_update = LazyLock.update

      -- Mock original update to fail
      LazyLock.update = function()
        error("Original update failed")
      end

      Ops.setup_lazy_hooks()

      -- Should not error when update is called
      assert.has_no.errors(function()
        pcall(LazyLock.update)
      end)

      -- Restore
      LazyLock.update = original_update
    end)
  end)

  describe("write_lockfiles", function()
    it("should write lockfiles for plugins", function()
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

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures
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

      -- Call write_lockfiles (async)
      Ops.write_lockfiles()

      -- Wait for async completion
      wait_for(function()
        return vim.fn.filereadable(repo1 .. "/lazy-lock.json") == 1
      end)

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
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

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

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures
      local LazyGit = require("lazy.manage.git")

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
      Source.get_plugin_source = function(plugin_name)
        if plugin_name == "lazy.nvim" then
          return repo1, nil, nil -- Not a recipe
        elseif plugin_name == "plenary.nvim" then
          return repo1, "lazy.nvim", nil -- IS a recipe, parent is lazy.nvim
        end
        return nil, nil, "Plugin not found"
      end

      -- Call write_lockfiles (async)
      Ops.write_lockfiles()

      -- Wait for lockfile to be written
      wait_for(function()
        return vim.fn.filereadable(repo1 .. "/lazy-lock.json") == 1
      end)

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
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should restore nested plugins from git lockfile when parent is disabled", function()
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

      Source.clear_all()
      lockfile.clear_cache()

      local Config = require("super_lazy.config")
      Config.setup({ lockfile_repo_dirs = { temp_config } })

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

      Source.get_plugin_source = function(plugin_name)
        if plugin_name == "parent-plugin" then
          return temp_config, nil, nil
        elseif plugin_name == "nested-plugin" then
          return temp_config, "parent-plugin", nil
        end
        return nil, nil, "Plugin not found"
      end

      -- Call write_lockfiles (async)
      Ops.write_lockfiles()

      -- Wait for lockfile to be written
      wait_for(function()
        return vim.fn.filereadable(temp_config .. "/lazy-lock.json") == 1
      end)

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
      Source.clear_all()
      lockfile.clear_cache()
      vim.fn.delete(temp_config, "rf")
      vim.fn.delete(test_cache_dir, "rf")
    end)

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

      -- Setup config
      Source.clear_all()
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
      Source.get_plugin_source = function(plugin_name)
        if plugin_name == "lazy.nvim" then
          return repo1, nil, nil
        end
        return nil, nil, "Plugin not found"
      end

      -- Call write_lockfiles (async)
      Ops.write_lockfiles()

      -- Wait for lockfile to be written
      wait_for(function()
        return vim.fn.filereadable(repo1 .. "/lazy-lock.json") == 1
      end)

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
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
      vim.fn.delete(temp_lazy_lock)
    end)

    it("should skip local plugins with is_local flag", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_local_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures
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
          name = "my-local-plugin",
          dir = "/home/user/projects/my-local-plugin",
          _ = { installed = true, is_local = true },
        },
      }

      LazyConfig.spec = {
        disabled = {},
        plugins = {},
      }

      LazyGit.info = function(dir)
        if dir:match("plenary") then
          return { branch = "master", commit = "abc123" }
        elseif dir:match("my%-local%-plugin") then
          return { branch = "main", commit = "local123" }
        end
        return nil
      end

      -- Call write_lockfiles (async)
      local completed = false
      Ops.write_lockfiles({
        on_complete = function()
          completed = true
        end,
      })

      -- Wait for async completion
      wait_for(function()
        return completed
      end)

      -- Verify lockfile was created
      local lockfile_data = lockfile.read(repo1 .. "/lazy-lock.json")

      -- plenary should be in lockfile
      assert.is_not_nil(lockfile_data["plenary.nvim"])

      -- local plugin should NOT be in lockfile
      assert.is_nil(lockfile_data["my-local-plugin"])

      -- Cleanup
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyGit.info = original_git_info
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should call on_complete callback with table options", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_callback_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures
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

      -- Call write_lockfiles with table options
      local callback_called = false
      Ops.write_lockfiles({
        on_complete = function()
          callback_called = true
        end,
      })

      -- Wait for callback
      wait_for(function()
        return callback_called
      end)

      assert.is_true(callback_called)

      -- Cleanup
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyGit.info = original_git_info
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

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

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures
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

      -- Call write_lockfiles (async)
      Ops.write_lockfiles()

      -- Wait for lockfile to be written
      wait_for(function()
        return vim.fn.filereadable(repo1 .. "/lazy-lock.json") == 1
      end)

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
      Source.clear_all()
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

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Create initial lockfile with plugin entry
      lockfile.write(repo1 .. "/lazy-lock.json", {
        ["plenary.nvim"] = { branch = "master", commit = "abc123" },
      })

      -- Setup hooks
      local LazyLock = require("lazy.manage.lock")
      local original_update = LazyLock.update

      Ops.setup_lazy_hooks()

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
      LazyLock.update = original_update
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should remove lockfile entry when plugin is cleaned and removed from repo config", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_clean_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Create initial lockfile with plugin entry for a plugin NOT in repo
      lockfile.write(repo1 .. "/lazy-lock.json", {
        ["some-removed-plugin.nvim"] = { branch = "main", commit = "xyz789" },
      })

      -- Setup hooks
      local LazyLock = require("lazy.manage.lock")
      local original_update = LazyLock.update

      Ops.setup_lazy_hooks()

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
      LazyLock.update = original_update
      Source.clear_all()
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

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
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

      Ops.setup_lazy_hooks()

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
      LazyLock.update = original_update
      Source.clear_all()
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

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
        debug = true,
      })

      -- Mock lazy.nvim structures
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

      -- Build the index first so there's something to clear
      Source.clear_index()
      local index_built = false
      Source.build_index(function()
        index_built = true
      end)
      wait_for(function()
        return index_built
      end)

      -- Capture notifications
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- Call refresh with empty list (async)
      Ops.refresh({})

      -- Wait for async completion - look for the completion message
      wait_for(function()
        for _, n in ipairs(notifications) do
          if n.msg:match("Refreshed plugin source index") then
            return true
          end
        end
        return false
      end)

      -- Restore
      vim.notify = original_notify
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyGit.info = original_git_info

      -- Verify notifications (fidget fallback shows "Syncing lockfiles..." first)
      assert.is_true(#notifications >= 2)
      assert.is_truthy(notifications[1].msg:match("Syncing lockfiles"))
      -- Last notification should be the completion message
      assert.is_truthy(notifications[#notifications].msg:match("Refreshed plugin source index"))

      -- Cleanup
      Source.clear_all()
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

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
        debug = true,
      })

      -- Mock lazy.nvim structures
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

      -- Build the index first asynchronously (same repo - should be unchanged after refresh)
      Source.clear_index()
      local index_built = false
      Source.build_index(function()
        index_built = true
      end)
      wait_for(function()
        return index_built
      end)

      -- Capture notifications
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- Call refresh with single plugin
      Ops.refresh({ "plenary.nvim" })

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
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should detect when plugin moves to different repo", function()
      -- Create temporary test directories
      local test_dir = "/tmp/super_lazy_refresh_move_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"
      local repo2 = test_dir .. "/repo2"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.mkdir(repo2 .. "/plugins", "p")

      -- Initially put plugin in repo2 (will be "moved" to repo1 later)
      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo2 .. "/plugins/core.lua")

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1, repo2 },
        debug = true,
      })

      -- Mock lazy.nvim structures
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

      -- Build the index with plugin in repo2 (old location)
      Source.clear_index()
      local index_built = false
      Source.build_index(function()
        index_built = true
      end)
      wait_for(function()
        return index_built
      end)

      -- Now "move" the plugin to repo1 by updating files
      vim.fn.delete(repo2 .. "/plugins/core.lua")
      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Capture notifications
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- Call refresh with single plugin
      Ops.refresh({ "plenary.nvim" })

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
      Source.clear_all()
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

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
        debug = true,
      })

      -- Mock lazy.nvim structures
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

      -- Build the index first
      Source.clear_index()
      local index_built = false
      Source.build_index(function()
        index_built = true
      end)
      wait_for(function()
        return index_built
      end)

      -- Capture notifications
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- Call refresh with multiple plugins
      Ops.refresh({ "plenary.nvim", "tokyonight.nvim" })

      -- Wait for async completion - need at least 3 notifications (syncing + 2 results)
      wait_for(function()
        return #notifications >= 3
      end)

      -- Restore
      vim.notify = original_notify
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyGit.info = original_git_info

      -- Verify notifications - should show syncing and results for each
      assert.is_true(#notifications >= 3)
      assert.is_truthy(notifications[1].msg:match("Syncing lockfiles"))

      -- Cleanup
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should report Detected for newly indexed plugin", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_refresh_detected_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures
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

      -- DON'T build the index first - plugin should be "newly detected"
      Source.clear_index()

      -- Capture notifications
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- Call refresh with single plugin
      Ops.refresh({ "plenary.nvim" })

      -- Wait for async completion - look for the "Detected" notification
      wait_for(function()
        for _, n in ipairs(notifications) do
          if n.msg:match("Detected plenary.nvim source") then
            return true
          end
        end
        return false
      end)

      -- Restore
      vim.notify = original_notify
      LazyConfig.plugins = original_plugins
      LazyConfig.spec = original_spec
      LazyGit.info = original_git_info

      -- Verify "Detected" notification was shown
      local found_detected = false
      for _, n in ipairs(notifications) do
        if n.msg:match("Detected plenary.nvim source") then
          found_detected = true
          break
        end
      end
      assert.is_true(found_detected)

      -- Cleanup
      Source.clear_all()
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

      -- Setup config
      Source.clear_all()
      local Config = require("super_lazy.config")
      Config.setup({
        lockfile_repo_dirs = { repo1 },
      })

      -- Mock lazy.nvim structures
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
      Ops.refresh({ "nonexistent-plugin.nvim" })

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
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)
  end)
end)
