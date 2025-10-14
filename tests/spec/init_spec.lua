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
        'return {',
        '  { "folke/lazy.nvim" },',
        '  { "nvim-lua/plenary.nvim" },',
        '}',
      }, repo1 .. "/plugins/core.lua")

      vim.fn.writefile({
        'return {',
        '  { "folke/tokyonight.nvim" },',
        '}',
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
end)
