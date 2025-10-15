local super_lazy = require("super_lazy")
local cache = require("super_lazy.cache")
local lockfile = require("super_lazy.lockfile")

describe("super_lazy init module", function()
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

      -- Trigger update (which should call write_lockfiles)
      local ok = pcall(LazyLock.update)
      assert.is_true(ok)

      -- Verify both lockfiles were created
      assert.equals(1, vim.fn.filereadable(repo1 .. "/lazy-lock.json"))
      assert.equals(1, vim.fn.filereadable(repo2 .. "/lazy-lock.json"))

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

      -- Verify lockfile still contains the plugin entry
      local lockfile_data = lockfile.read(repo1 .. "/lazy-lock.json")
      assert.is_not_nil(lockfile_data["plenary.nvim"])
      assert.equals("master", lockfile_data["plenary.nvim"].branch)
      assert.equals("abc123", lockfile_data["plenary.nvim"].commit)

      -- Cleanup
      LazyLock.update = original_update
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should remove lockfile entry when plugin is cleaned and removed from repo config", function()
      -- Create temporary test directory
      local test_dir = "/tmp/super_lazy_clean_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")

      -- Setup super_lazy
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
      cache.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)
  end)
end)
