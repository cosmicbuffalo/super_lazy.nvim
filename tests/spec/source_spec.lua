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

  describe("get_plugin_source", function()
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

    it("should error when plugin not found", function()
      config.setup({ lockfile_repo_dirs = { "/test" } })

      local original_resolve = vim.fn.resolve
      local original_isdirectory = vim.fn.isdirectory
      local original_glob = vim.fn.glob

      vim.fn.resolve = function(path)
        return path
      end
      vim.fn.isdirectory = function(path)
        return 1
      end
      vim.fn.glob = function(pattern, nosuf, list)
        return {}
      end

      local original_require = require
      _G.require = function(name)
        if name == "lazy" then
          return {
            plugins = function()
              return {}
            end,
          }
        end
        return original_require(name)
      end

      assert.has_error(function()
        source.get_plugin_source("nonexistent-plugin")
      end)

      vim.fn.resolve = original_resolve
      vim.fn.isdirectory = original_isdirectory
      vim.fn.glob = original_glob
      _G.require = original_require
    end)
  end)
end)
