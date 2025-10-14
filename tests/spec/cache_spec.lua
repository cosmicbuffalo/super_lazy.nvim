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

  describe("plugin_exists cache", function()
    it("should return nil for non-existent key", function()
      assert.is_nil(cache.get_plugin_exists("test-key"))
    end)

    it("should store and retrieve boolean values", function()
      cache.set_plugin_exists("key1", true)
      cache.set_plugin_exists("key2", false)
      assert.is_true(cache.get_plugin_exists("key1"))
      assert.is_false(cache.get_plugin_exists("key2"))
    end)
  end)

  describe("recipe cache", function()
    it("should return nil for non-existent key", function()
      assert.is_nil(cache.get_recipe("test-key"))
    end)

    it("should store and retrieve recipe values", function()
      cache.set_recipe("plugin|repo", "parent-plugin")
      assert.equals("parent-plugin", cache.get_recipe("plugin|repo"))
    end)

    it("should handle nil values", function()
      cache.set_recipe("plugin|repo", nil)
      assert.is_nil(cache.get_recipe("plugin|repo"))
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

  describe("clear_all", function()
    it("should clear all caches", function()
      -- Set values in all caches
      cache.set_lockfile_repo_paths({ "/path" })
      cache.set_lazy_plugins({ { name = "test" } })
      cache.set_plugin_exists("key", true)
      cache.set_recipe("key", "value")
      cache.set_git_info("/path", { branch = "main" })

      -- Clear all
      cache.clear_all()

      -- Verify all are cleared
      assert.is_nil(cache.get_lockfile_repo_paths())
      assert.is_nil(cache.get_lazy_plugins())
      assert.is_nil(cache.get_plugin_exists("key"))
      assert.is_nil(cache.get_recipe("key"))
      assert.is_nil(cache.get_git_info("/path"))
    end)
  end)
end)
