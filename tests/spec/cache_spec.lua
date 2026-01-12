local cache = require("super_lazy.cache")

describe("cache module", function()
  before_each(function()
    cache.clear_all()
  end)

  describe("paths cache", function()
    it("should return nil when not set", function()
      assert.is_nil(cache.get_lockfile_repo_paths())
    end)

    it("should store and retrieve paths", function()
      local paths = { "/path/one", "/path/two" }
      cache.set_lockfile_repo_paths(paths)
      assert.same(paths, cache.get_lockfile_repo_paths())
    end)
  end)

  describe("lazy_plugins cache", function()
    it("should return nil when not set", function()
      assert.is_nil(cache.get_lazy_plugins())
    end)

    it("should store and retrieve lazy plugins", function()
      local plugins = { { name = "plugin1" }, { name = "plugin2" } }
      cache.set_lazy_plugins(plugins)
      assert.same(plugins, cache.get_lazy_plugins())
    end)
  end)

  describe("git_info cache", function()
    it("should return nil for non-existent key", function()
      assert.is_nil(cache.get_git_info("/some/path"))
    end)

    it("should store and retrieve git info", function()
      local git_info = { branch = "main", commit = "abc123" }
      cache.set_git_info("/plugin/path", git_info)
      assert.same(git_info, cache.get_git_info("/plugin/path"))
    end)

    it("should handle false values", function()
      cache.set_git_info("/plugin/path", false)
      assert.is_false(cache.get_git_info("/plugin/path"))
    end)
  end)

  describe("persistent plugin_source cache", function()
    it("should return nil for non-existent plugin", function()
      assert.is_nil(cache.get_plugin_source("nonexistent-plugin"))
    end)

    it("should store and retrieve plugin source without parent", function()
      cache.set_plugin_source("test-plugin", "/path/to/repo", nil)
      local result = cache.get_plugin_source("test-plugin")
      assert.is_not_nil(result)
      assert.equals("/path/to/repo", result.repo)
      assert.is_nil(result.parent)
    end)

    it("should store and retrieve plugin source with parent", function()
      cache.set_plugin_source("nested-plugin", "/path/to/repo", "parent-plugin")
      local result = cache.get_plugin_source("nested-plugin")
      assert.is_not_nil(result)
      assert.equals("/path/to/repo", result.repo)
      assert.equals("parent-plugin", result.parent)
    end)

    it("should handle multiple plugins", function()
      cache.set_plugin_source("plugin1", "/repo1", nil)
      cache.set_plugin_source("plugin2", "/repo2", "parent1")
      cache.set_plugin_source("plugin3", "/repo1", nil)

      local p1 = cache.get_plugin_source("plugin1")
      local p2 = cache.get_plugin_source("plugin2")
      local p3 = cache.get_plugin_source("plugin3")

      assert.equals("/repo1", p1.repo)
      assert.is_nil(p1.parent)

      assert.equals("/repo2", p2.repo)
      assert.equals("parent1", p2.parent)

      assert.equals("/repo1", p3.repo)
      assert.is_nil(p3.parent)
    end)
  end)

  describe("get_all_plugin_sources", function()
    it("should return empty table when no sources cached", function()
      local sources = cache.get_all_plugin_sources()
      assert.is_table(sources)
      assert.equals(0, vim.tbl_count(sources))
    end)

    it("should return all cached plugin sources", function()
      cache.set_plugin_source("plugin1", "/repo1", nil)
      cache.set_plugin_source("plugin2", "/repo2", "parent")

      local sources = cache.get_all_plugin_sources()
      assert.is_not_nil(sources.plugin1)
      assert.is_not_nil(sources.plugin2)
      assert.equals("/repo1", sources.plugin1.repo)
      assert.equals("/repo2", sources.plugin2.repo)
      assert.equals("parent", sources.plugin2.parent)
    end)
  end)

  describe("set_all_plugin_sources", function()
    it("should replace all plugin sources at once", function()
      -- Set initial values
      cache.set_plugin_source("old-plugin", "/old/repo", nil)

      -- Replace with new values
      local new_sources = {
        ["plugin1"] = { repo = "/repo1", parent = nil },
        ["plugin2"] = { repo = "/repo2", parent = "parent1" },
      }
      cache.set_all_plugin_sources(new_sources)

      -- Old value should be gone
      assert.is_nil(cache.get_plugin_source("old-plugin"))

      -- New values should be present
      local p1 = cache.get_plugin_source("plugin1")
      local p2 = cache.get_plugin_source("plugin2")
      assert.equals("/repo1", p1.repo)
      assert.equals("/repo2", p2.repo)
      assert.equals("parent1", p2.parent)
    end)

    it("should handle empty sources table", function()
      cache.set_plugin_source("test", "/test", nil)
      cache.set_all_plugin_sources({})

      assert.is_nil(cache.get_plugin_source("test"))
    end)
  end)

  describe("clear_all", function()
    it("should clear all in-memory caches", function()
      cache.set_lockfile_repo_paths({ "/path" })
      cache.set_lazy_plugins({ { name = "test" } })
      cache.set_git_info("/path", { branch = "main" })

      cache.clear_all()

      assert.is_nil(cache.get_lockfile_repo_paths())
      assert.is_nil(cache.get_lazy_plugins())
      assert.is_nil(cache.get_git_info("/path"))
    end)

    it("should clear persistent cache", function()
      cache.set_plugin_source("test-plugin", "/test/repo", nil)
      cache.clear_all()
      assert.is_nil(cache.get_plugin_source("test-plugin"))
    end)
  end)

  describe("clear_plugin_source", function()
    it("should remove a single plugin from cache", function()
      cache.set_plugin_source("plugin1", "/repo1", nil)
      cache.set_plugin_source("plugin2", "/repo2", nil)

      cache.clear_plugin_source("plugin1")

      assert.is_nil(cache.get_plugin_source("plugin1"))
      assert.is_not_nil(cache.get_plugin_source("plugin2"))
    end)

    it("should return the old source when clearing", function()
      cache.set_plugin_source("test-plugin", "/test/repo", "parent-plugin")

      local old_source = cache.clear_plugin_source("test-plugin")

      assert.is_not_nil(old_source)
      assert.equals("/test/repo", old_source.repo)
      assert.equals("parent-plugin", old_source.parent)
    end)

    it("should return nil when plugin was not in cache", function()
      local old_source = cache.clear_plugin_source("nonexistent-plugin")
      assert.is_nil(old_source)
    end)

    it("should persist the removal to disk", function()
      cache.set_plugin_source("persist-test", "/repo", nil)
      cache.clear_plugin_source("persist-test")

      -- Force reload from disk by clearing in-memory cache
      cache.clear_all()

      -- Plugin should still be gone after reload
      assert.is_nil(cache.get_plugin_source("persist-test"))
    end)
  end)
end)
