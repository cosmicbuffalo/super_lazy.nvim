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
end)
