local super_lazy = require("super_lazy")
local Ops = require("super_lazy.ops")
local Source = require("super_lazy.source")
local lockfile = require("super_lazy.lockfile")

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

  describe("module exports", function()
    it("should export setup function", function()
      assert.is_function(super_lazy.setup)
    end)

    it("should export refresh function", function()
      assert.is_function(super_lazy.refresh)
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

      Source.clear_all()
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
      local called_write_lockfiles = false
      local original_write_lockfiles = Ops.write_lockfiles
      Ops.write_lockfiles = function()
        called_write_lockfiles = true
      end

      super_lazy.setup({ lockfile_repo_dirs = { repo1, repo2 } })
      -- Verify Ops.write_lockfiles was called (which means needs sync returned true)
      assert.is_true(called_write_lockfiles)

      -- Cleanup
      Ops.write_lockfiles = original_write_lockfiles
      LazyConfig.options.lockfile = original_lockfile
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should detect when split lockfile is missing", function()
      local test_dir = "/tmp/super_lazy_missing_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"
      local repo2 = test_dir .. "/repo2"
      local main_lockfile = test_dir .. "/lazy-lock.json"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.mkdir(repo2 .. "/plugins", "p")

      Source.clear_all()
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
      local called_write_lockfiles = false
      local original_write_lockfiles = Ops.write_lockfiles
      Ops.write_lockfiles = function()
        called_write_lockfiles = true
      end

      super_lazy.setup({ lockfile_repo_dirs = { repo1, repo2 } })
      assert.is_true(called_write_lockfiles)

      -- Cleanup
      Ops.write_lockfiles = original_write_lockfiles
      LazyConfig.options.lockfile = original_lockfile
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)

    it("should not sync when lockfiles are already in sync", function()
      local test_dir = "/tmp/super_lazy_sync_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"
      local repo2 = test_dir .. "/repo2"
      local main_lockfile = test_dir .. "/lazy-lock.json"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.mkdir(repo2 .. "/plugins", "p")

      Source.clear_all()
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
      local called_write_lockfiles = false
      local original_write_lockfiles = Ops.write_lockfiles
      Ops.write_lockfiles = function()
        called_write_lockfiles = true
      end

      super_lazy.setup({ lockfile_repo_dirs = { repo1, repo2 } })

      -- Verify write_lockfiles was NOT called (because lockfiles were in sync)
      assert.is_false(called_write_lockfiles)

      -- Cleanup
      Ops.write_lockfiles = original_write_lockfiles
      LazyConfig.options.lockfile = original_lockfile
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)
  end)

  describe("SuperLazyRefresh command", function()
    it("should be registered after setup", function()
      Source.clear_all()
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

      Source.clear_all()
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
      Source.clear_all()
      vim.fn.delete(test_dir, "rf")
    end)
  end)
end)
