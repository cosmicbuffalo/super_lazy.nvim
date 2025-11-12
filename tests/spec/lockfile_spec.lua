local lockfile = require("super_lazy.lockfile")

describe("lockfile module", function()
  local test_dir = "/tmp/super_lazy_test"
  local test_lockfile = test_dir .. "/test-lock.json"

  before_each(function()
    vim.fn.mkdir(test_dir, "p")
  end)

  after_each(function()
    vim.fn.delete(test_dir, "rf")
  end)

  describe("read", function()
    it("should return empty table for non-existent file", function()
      local result = lockfile.read("/nonexistent/path.json")
      assert.same({}, result)
    end)

    it("should parse valid lockfile", function()
      local test_data = {
        ["plugin1"] = { branch = "main", commit = "abc123" },
        ["plugin2"] = { branch = "develop", commit = "def456" },
      }

      -- Write test file
      local f = io.open(test_lockfile, "w")
      f:write(vim.json.encode(test_data))
      f:close()

      local result = lockfile.read(test_lockfile)
      assert.same(test_data, result)
    end)

    it("should handle invalid JSON gracefully", function()
      local f = io.open(test_lockfile, "w")
      f:write("{ invalid json")
      f:close()

      local result = lockfile.read(test_lockfile)
      assert.same({}, result)
    end)

    it("should handle empty file", function()
      local f = io.open(test_lockfile, "w")
      f:write("")
      f:close()

      local result = lockfile.read(test_lockfile)
      assert.same({}, result)
    end)
  end)

  describe("write", function()
    it("should create directory if it doesn't exist", function()
      local nested_path = test_dir .. "/nested/deep/lock.json"
      local data = { ["test"] = { branch = "main", commit = "abc" } }

      lockfile.write(nested_path, data)

      assert.equals(1, vim.fn.filereadable(nested_path))
    end)

    it("should write formatted lockfile", function()
      local data = {
        ["plugin1"] = { branch = "main", commit = "abc123" },
        ["plugin2"] = { branch = "develop", commit = "def456" },
      }

      lockfile.write(test_lockfile, data)

      -- Read raw file to check formatting
      local f = io.open(test_lockfile, "r")
      local content = f:read("*a")
      f:close()

      -- Check basic structure
      assert.is_not_nil(content:match("^{"))
      assert.is_not_nil(content:match("}%s*$"))
      assert.is_not_nil(content:match('"plugin1"'))
      assert.is_not_nil(content:match('"plugin2"'))
      assert.is_not_nil(content:match('"main"'))
      assert.is_not_nil(content:match('"abc123"'))
    end)

    it("should sort plugin names alphabetically", function()
      local data = {
        ["zebra"] = { branch = "main", commit = "zzz" },
        ["alpha"] = { branch = "main", commit = "aaa" },
        ["middle"] = { branch = "main", commit = "mmm" },
      }

      lockfile.write(test_lockfile, data)

      local f = io.open(test_lockfile, "r")
      local content = f:read("*a")
      f:close()

      -- Alpha should come before middle, middle before zebra
      local alpha_pos = content:find('"alpha"')
      local middle_pos = content:find('"middle"')
      local zebra_pos = content:find('"zebra"')

      assert.is_true(alpha_pos < middle_pos)
      assert.is_true(middle_pos < zebra_pos)
    end)

    it("should handle empty data", function()
      lockfile.write(test_lockfile, {})

      local f = io.open(test_lockfile, "r")
      local content = f:read("*a")
      f:close()

      -- Should just be empty braces
      assert.equals("{\n}\n", content)
    end)

    it("should be readable after writing", function()
      local data = {
        ["plugin1"] = { branch = "main", commit = "abc123" },
        ["plugin2"] = { branch = "develop", commit = "def456" },
      }

      lockfile.write(test_lockfile, data)
      local result = lockfile.read(test_lockfile)

      assert.same(data, result)
    end)
  end)

  describe("get_cached", function()
    local test_cache_dir
    local original_stdpath

    before_each(function()
      test_cache_dir = vim.fn.tempname()
      vim.fn.mkdir(test_cache_dir, "p")

      original_stdpath = vim.fn.stdpath
      vim.fn.stdpath = function(what)
        if what == "data" then
          return test_cache_dir
        end
        return original_stdpath(what)
      end

      lockfile.clear_cache()
    end)

    after_each(function()
      vim.fn.stdpath = original_stdpath
      vim.fn.delete(test_cache_dir, "rf")
    end)

    it("should return nil when not in a git repo", function()
      local temp_config = vim.fn.tempname()
      vim.fn.mkdir(temp_config, "p")

      vim.fn.stdpath = function(what)
        if what == "config" then
          return temp_config
        elseif what == "data" then
          return test_cache_dir
        end
        return original_stdpath(what)
      end

      local result = lockfile.get_cached()

      vim.fn.delete(temp_config, "rf")

      assert.is_nil(result)
    end)

    it("should return nil when lockfile doesn't exist in git", function()
      local temp_config = vim.fn.tempname()
      vim.fn.mkdir(temp_config, "p")

      vim.fn.system({ "git", "-C", temp_config, "init" })
      vim.fn.system({ "git", "-C", temp_config, "config", "user.email", "test@test.com" })
      vim.fn.system({ "git", "-C", temp_config, "config", "user.name", "Test User" })

      local readme = temp_config .. "/README.md"
      vim.fn.writefile({ "# Test" }, readme)
      vim.fn.system({ "git", "-C", temp_config, "add", "README.md" })
      vim.fn.system({ "git", "-C", temp_config, "commit", "-m", "initial" })

      vim.fn.stdpath = function(what)
        if what == "config" then
          return temp_config
        elseif what == "data" then
          return test_cache_dir
        end
        return original_stdpath(what)
      end

      local result = lockfile.get_cached()

      vim.fn.delete(temp_config, "rf")

      assert.is_nil(result)
    end)

    it("should return cached data when commit matches", function()
      local temp_config = vim.fn.tempname()
      vim.fn.mkdir(temp_config, "p")

      vim.fn.system({ "git", "-C", temp_config, "init" })
      vim.fn.system({ "git", "-C", temp_config, "config", "user.email", "test@test.com" })
      vim.fn.system({ "git", "-C", temp_config, "config", "user.name", "Test User" })

      local lockfile_data = {
        ["plugin-cached"] = { branch = "main", commit = "cached123" },
      }

      local lockfile_path = temp_config .. "/lazy-lock.json"
      vim.fn.writefile({ vim.json.encode(lockfile_data) }, lockfile_path)
      vim.fn.system({ "git", "-C", temp_config, "add", "lazy-lock.json" })
      vim.fn.system({ "git", "-C", temp_config, "commit", "-m", "add lockfile" })

      vim.fn.stdpath = function(what)
        if what == "config" then
          return temp_config
        elseif what == "data" then
          return test_cache_dir
        end
        return original_stdpath(what)
      end

      local first_result = lockfile.get_cached()
      assert.is_not_nil(first_result)
      assert.same(lockfile_data, first_result)

      local second_result = lockfile.get_cached()
      assert.is_not_nil(second_result)
      assert.same(lockfile_data, second_result)

      vim.fn.delete(temp_config, "rf")
    end)

    it("should fetch from git and cache when no cache exists", function()
      local temp_config = vim.fn.tempname()
      vim.fn.mkdir(temp_config, "p")

      vim.fn.system({ "git", "-C", temp_config, "init" })
      vim.fn.system({ "git", "-C", temp_config, "config", "user.email", "test@test.com" })
      vim.fn.system({ "git", "-C", temp_config, "config", "user.name", "Test User" })

      local lockfile_data = {
        ["plugin-from-git"] = { branch = "main", commit = "git123" },
      }

      local lockfile_path = temp_config .. "/lazy-lock.json"
      vim.fn.writefile({ vim.json.encode(lockfile_data) }, lockfile_path)
      vim.fn.system({ "git", "-C", temp_config, "add", "lazy-lock.json" })
      vim.fn.system({ "git", "-C", temp_config, "commit", "-m", "add lockfile" })

      vim.fn.stdpath = function(what)
        if what == "config" then
          return temp_config
        elseif what == "data" then
          return test_cache_dir
        end
        return original_stdpath(what)
      end

      local result = lockfile.get_cached()

      assert.is_not_nil(result)
      assert.same(lockfile_data, result)

      local cache_file = test_cache_dir .. "/super_lazy/original_lockfile.json"
      assert.equals(1, vim.fn.filereadable(cache_file))

      vim.fn.stdpath = original_stdpath
      vim.fn.delete(temp_config, "rf")
    end)

    it("should invalidate cache when commit changes", function()
      local temp_config = vim.fn.tempname()
      vim.fn.mkdir(temp_config, "p")

      vim.fn.system({ "git", "-C", temp_config, "init" })
      vim.fn.system({ "git", "-C", temp_config, "config", "user.email", "test@test.com" })
      vim.fn.system({ "git", "-C", temp_config, "config", "user.name", "Test User" })

      local old_lockfile = {
        ["plugin-old"] = { branch = "main", commit = "old123" },
      }

      local lockfile_path = temp_config .. "/lazy-lock.json"
      vim.fn.writefile({ vim.json.encode(old_lockfile) }, lockfile_path)
      vim.fn.system({ "git", "-C", temp_config, "add", "lazy-lock.json" })
      vim.fn.system({ "git", "-C", temp_config, "commit", "-m", "add old lockfile" })

      vim.fn.stdpath = function(what)
        if what == "config" then
          return temp_config
        elseif what == "data" then
          return test_cache_dir
        end
        return original_stdpath(what)
      end

      local first_result = lockfile.get_cached()
      assert.same(old_lockfile, first_result)

      local new_lockfile = {
        ["plugin-new"] = { branch = "main", commit = "new456" },
      }

      vim.fn.writefile({ vim.json.encode(new_lockfile) }, lockfile_path)
      vim.fn.system({ "git", "-C", temp_config, "add", "lazy-lock.json" })
      vim.fn.system({ "git", "-C", temp_config, "commit", "-m", "update lockfile" })

      local second_result = lockfile.get_cached()
      assert.same(new_lockfile, second_result)

      vim.fn.stdpath = original_stdpath
      vim.fn.delete(temp_config, "rf")
    end)
  end)

  describe("clear_cache", function()
    local test_cache_dir
    local original_stdpath

    before_each(function()
      test_cache_dir = vim.fn.tempname()
      vim.fn.mkdir(test_cache_dir, "p")

      original_stdpath = vim.fn.stdpath
      vim.fn.stdpath = function(what)
        if what == "data" then
          return test_cache_dir
        end
        return original_stdpath(what)
      end
    end)

    after_each(function()
      vim.fn.stdpath = original_stdpath
      vim.fn.delete(test_cache_dir, "rf")
    end)

    it("should remove cache file", function()
      local cache_file = test_cache_dir .. "/super_lazy/original_lockfile.json"
      vim.fn.mkdir(vim.fn.fnamemodify(cache_file, ":h"), "p")

      local test_data = {
        timestamp = os.time(),
        commit = "abc123def",
        lockfile = { ["plugin"] = { branch = "main", commit = "abc" } },
      }

      vim.fn.writefile({ vim.json.encode(test_data) }, cache_file)
      assert.equals(1, vim.fn.filereadable(cache_file))

      lockfile.clear_cache()
      assert.equals(0, vim.fn.filereadable(cache_file))
    end)
  end)
end)
