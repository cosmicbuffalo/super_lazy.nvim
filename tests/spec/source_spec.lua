local source = require("super_lazy.source")
local config = require("super_lazy.config")
local cache = require("super_lazy.cache")

describe("source module", function()
  before_each(function()
    cache.clear_all()
  end)

  after_each(function()
    cache.clear_all()
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

      local source_path = source.lookup_plugin_in_index("lazy.nvim")

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

      local repo, parent, err = source.lookup_plugin_in_index("nonexistent-plugin")

      vim.fn.resolve = original_resolve
      vim.fn.isdirectory = original_isdirectory

      assert.is_nil(repo)
      assert.is_not_nil(err)
      assert.is_truthy(err:match("not found"))
    end)
  end)
end)
