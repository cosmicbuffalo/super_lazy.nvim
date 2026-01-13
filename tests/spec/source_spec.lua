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

    it("should cache git info", function()
      local LazyGit = require("lazy.manage.git")
      local original_info = LazyGit.info
      local call_count = 0

      LazyGit.info = function(dir)
        call_count = call_count + 1
        return { branch = "main", commit = "abc123" }
      end

      local plugin = { name = "test-plugin", dir = "/tmp/lazy/cache-test" }
      local info1 = source.get_git_info(plugin)
      local info2 = source.get_git_info(plugin)

      LazyGit.info = original_info

      -- Should only call LazyGit.info once due to caching
      assert.equals(1, call_count)
      assert.equals(info1.branch, info2.branch)
      assert.equals(info1.commit, info2.commit)
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

    it("should be cleared by clear_all", function()
      local LazyGit = require("lazy.manage.git")
      local original_info = LazyGit.info
      local call_count = 0

      LazyGit.info = function(dir)
        call_count = call_count + 1
        return { branch = "main", commit = "abc123" }
      end

      local plugin = { name = "test-plugin", dir = "/tmp/lazy/clear-test" }
      source.get_git_info(plugin)
      source.clear_all()
      source.get_git_info(plugin)

      LazyGit.info = original_info

      -- Should call LazyGit.info twice because cache was cleared
      assert.equals(2, call_count)
    end)
  end)
end)
