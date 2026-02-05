local source = require("super_lazy.source")
local config = require("super_lazy.config")

describe("source module", function()
  before_each(function()
    source.clear_all()
  end)

  after_each(function()
    source.clear_all()
  end)

  describe("get_lockfile_repo_paths", function()
    it("should return configured paths", function()
      config.setup({ lockfile_repo_dirs = { "/test/path1", "/test/path2" } })

      -- Mock vim.fn functions
      local original_resolve = vim.fn.resolve
      local original_isdirectory = vim.fn.isdirectory

      vim.fn.resolve = function(path)
        return path
      end
      vim.fn.isdirectory = function(path)
        return 1
      end

      local paths = source.get_lockfile_repo_paths()

      vim.fn.resolve = original_resolve
      vim.fn.isdirectory = original_isdirectory

      assert.equals(2, #paths)
      assert.equals("/test/path1", paths[1])
      assert.equals("/test/path2", paths[2])
    end)

    it("should cache paths", function()
      config.setup({ lockfile_repo_dirs = { "/test/path" } })

      local original_resolve = vim.fn.resolve
      local original_isdirectory = vim.fn.isdirectory

      vim.fn.resolve = function(path)
        return path
      end
      vim.fn.isdirectory = function(path)
        return 1
      end

      local paths1 = source.get_lockfile_repo_paths()
      local paths2 = source.get_lockfile_repo_paths()

      vim.fn.resolve = original_resolve
      vim.fn.isdirectory = original_isdirectory

      -- Should be the same cached instance
      assert.equals(paths1, paths2)
    end)

    it("should skip invalid directories", function()
      config.setup({ lockfile_repo_dirs = { "/valid", "/invalid" } })

      local original_resolve = vim.fn.resolve
      local original_isdirectory = vim.fn.isdirectory

      vim.fn.resolve = function(path)
        return path
      end
      vim.fn.isdirectory = function(path)
        if path == "/valid" then
          return 1
        else
          return 0
        end
      end

      local paths = source.get_lockfile_repo_paths()

      vim.fn.resolve = original_resolve
      vim.fn.isdirectory = original_isdirectory

      assert.equals(1, #paths)
      assert.equals("/valid", paths[1])
    end)

    it("should resolve symlinks", function()
      config.setup({ lockfile_repo_dirs = { "/symlink" } })

      local original_resolve = vim.fn.resolve
      local original_isdirectory = vim.fn.isdirectory

      vim.fn.resolve = function(path)
        if path == "/symlink" then
          return "/real/path"
        end
        return path
      end
      vim.fn.isdirectory = function(path)
        return 1
      end

      local paths = source.get_lockfile_repo_paths()

      vim.fn.resolve = original_resolve
      vim.fn.isdirectory = original_isdirectory

      assert.equals("/real/path", paths[1])
    end)
  end)

  describe("lookup_plugin_in_index", function()
    it("should return first repo path for lazy.nvim", function()
      config.setup({ lockfile_repo_dirs = { "/path1", "/path2" } })

      local original_resolve = vim.fn.resolve
      local original_isdirectory = vim.fn.isdirectory

      vim.fn.resolve = function(path)
        return path
      end
      vim.fn.isdirectory = function(path)
        return 1
      end

      local source_path = source.get_plugin_source("lazy.nvim")

      vim.fn.resolve = original_resolve
      vim.fn.isdirectory = original_isdirectory

      assert.equals("/path1", source_path)
    end)

    it("should return error when plugin not found in index", function()
      config.setup({ lockfile_repo_dirs = { "/test" } })

      local original_resolve = vim.fn.resolve
      local original_isdirectory = vim.fn.isdirectory

      vim.fn.resolve = function(path)
        return path
      end
      vim.fn.isdirectory = function(path)
        return 1
      end

      -- Clear the index so plugin won't be found
      source.clear_index()

      local repo, parent, err = source.get_plugin_source("nonexistent-plugin")

      vim.fn.resolve = original_resolve
      vim.fn.isdirectory = original_isdirectory

      assert.is_nil(repo)
      assert.is_not_nil(err)
      assert.is_truthy(err:match("not found"))
    end)
  end)

  describe("build_index", function()
    -- Helper to wait for async operations
    local function wait_for(condition, timeout_ms)
      timeout_ms = timeout_ms or 5000
      local ok = vim.wait(timeout_ms, condition, 10)
      assert(ok, "Timeout waiting for condition")
    end

    it("should call on_progress callback during indexing", function()
      local test_dir = "/tmp/super_lazy_build_index_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        '  { "folke/tokyonight.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      config.setup({ lockfile_repo_dirs = { repo1 } })

      local progress_calls = {}
      local done = false

      source.build_index(function(index)
        done = true
      end, {
        on_progress = function(current, total, message)
          table.insert(progress_calls, { current = current, total = total, message = message })
        end,
      })

      wait_for(function()
        return done
      end)

      -- Should have received progress callbacks
      assert.is_true(#progress_calls >= 1)
      -- First call should indicate starting scan
      assert.is_truthy(progress_calls[1].message:match("scan") or progress_calls[1].message:match("Scan"))

      vim.fn.delete(test_dir, "rf")
    end)

    it("should return empty index when no repo paths configured", function()
      config.setup({ lockfile_repo_dirs = {} })

      local done = false
      local result_index = nil

      source.build_index(function(index)
        result_index = index
        done = true
      end)

      wait_for(function()
        return done
      end)

      assert.is_not_nil(result_index)
      -- Empty index
      local count = 0
      for _ in pairs(result_index) do
        count = count + 1
      end
      assert.equals(0, count)
    end)

    it("should return empty index when repo has no plugin files", function()
      local test_dir = "/tmp/super_lazy_empty_repo_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1, "p")
      -- No plugins directory

      config.setup({ lockfile_repo_dirs = { repo1 } })

      local done = false
      local result_index = nil

      source.build_index(function(index)
        result_index = index
        done = true
      end)

      wait_for(function()
        return done
      end)

      assert.is_not_nil(result_index)
      local count = 0
      for _ in pairs(result_index) do
        count = count + 1
      end
      assert.equals(0, count)

      vim.fn.delete(test_dir, "rf")
    end)

    it("should index plugins from multiple files", function()
      local test_dir = "/tmp/super_lazy_multi_file_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.writefile({
        "return {",
        '  { "nvim-lua/plenary.nvim" },',
        "}",
      }, repo1 .. "/plugins/core.lua")
      vim.fn.writefile({
        "return {",
        '  { "folke/tokyonight.nvim" },',
        "}",
      }, repo1 .. "/plugins/theme.lua")

      config.setup({ lockfile_repo_dirs = { repo1 } })

      local done = false
      local result_index = nil

      source.build_index(function(index)
        result_index = index
        done = true
      end)

      wait_for(function()
        return done
      end)

      assert.is_not_nil(result_index["plenary.nvim"])
      assert.is_not_nil(result_index["tokyonight.nvim"])
      assert.equals(repo1, result_index["plenary.nvim"].repo)
      assert.equals(repo1, result_index["tokyonight.nvim"].repo)

      vim.fn.delete(test_dir, "rf")
    end)

    it("should detect plugins using name= syntax", function()
      local test_dir = "/tmp/super_lazy_name_syntax_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.writefile({
        "return {",
        '  { "some/repo", name = "custom-name" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      config.setup({ lockfile_repo_dirs = { repo1 } })

      local done = false
      local result_index = nil

      source.build_index(function(index)
        result_index = index
        done = true
      end)

      wait_for(function()
        return done
      end)

      assert.is_not_nil(result_index["custom-name"])
      assert.equals(repo1, result_index["custom-name"].repo)

      vim.fn.delete(test_dir, "rf")
    end)

    it("should detect plugins using dir= syntax", function()
      local test_dir = "/tmp/super_lazy_dir_syntax_test_" .. os.time()
      local repo1 = test_dir .. "/repo1"

      vim.fn.mkdir(repo1 .. "/plugins", "p")
      vim.fn.writefile({
        "return {",
        '  { dir = "/path/to/local-plugin" },',
        "}",
      }, repo1 .. "/plugins/core.lua")

      config.setup({ lockfile_repo_dirs = { repo1 } })

      local done = false
      local result_index = nil

      source.build_index(function(index)
        result_index = index
        done = true
      end)

      wait_for(function()
        return done
      end)

      assert.is_not_nil(result_index["local-plugin"])
      assert.equals(repo1, result_index["local-plugin"].repo)

      vim.fn.delete(test_dir, "rf")
    end)
  end)

  describe("get_git_info", function()
    it("should return git info for a plugin", function()
      local LazyGit = require("lazy.manage.git")
      local original_info = LazyGit.info

      LazyGit.info = function(dir)
        if dir == "/tmp/lazy/test-plugin" then
          return { branch = "main", commit = "abc123" }
        end
        return nil
      end

      local plugin = { name = "test-plugin", dir = "/tmp/lazy/test-plugin" }
      local git_info = source.get_git_info(plugin)

      LazyGit.info = original_info

      assert.is_not_nil(git_info)
      assert.equals("main", git_info.branch)
      assert.equals("abc123", git_info.commit)
    end)

    it("should return nil for plugins without git info", function()
      local LazyGit = require("lazy.manage.git")
      local original_info = LazyGit.info

      LazyGit.info = function(dir)
        return nil
      end

      local plugin = { name = "no-git-plugin", dir = "/tmp/lazy/no-git" }
      local git_info = source.get_git_info(plugin)

      LazyGit.info = original_info

      assert.is_nil(git_info)
    end)

    it("should work after clear_all", function()
      local LazyGit = require("lazy.manage.git")
      local original_info = LazyGit.info

      LazyGit.info = function(dir)
        return { branch = "main", commit = "abc123" }
      end

      local plugin = { name = "test-plugin", dir = "/tmp/lazy/clear-test" }
      source.get_git_info(plugin)
      source.clear_all()
      local git_info = source.get_git_info(plugin)

      LazyGit.info = original_info

      -- Should still return valid git info after clear_all
      assert.is_not_nil(git_info)
      assert.equals("main", git_info.branch)
    end)
  end)
end)
