local fs = require("super_lazy.fs")

describe("fs module", function()
  local test_dir

  before_each(function()
    test_dir = "/tmp/super_lazy_fs_test_" .. os.time() .. "_" .. math.random(1000, 9999)
    vim.fn.mkdir(test_dir, "p")
  end)

  after_each(function()
    vim.fn.delete(test_dir, "rf")
  end)

  describe("read_file", function()
    it("should read file contents asynchronously", function()
      local test_file = test_dir .. "/test.txt"
      vim.fn.writefile({ "hello", "world" }, test_file)

      local done = false
      local result_err, result_content

      fs.read_file(test_file, function(err, content)
        result_err = err
        result_content = content
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_nil(result_err)
      assert.is_not_nil(result_content)
      assert.is_truthy(result_content:match("hello"))
      assert.is_truthy(result_content:match("world"))
    end)

    it("should return error for non-existent file", function()
      local done = false
      local result_err, result_content

      fs.read_file(test_dir .. "/nonexistent.txt", function(err, content)
        result_err = err
        result_content = content
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_not_nil(result_err)
      assert.is_nil(result_content)
    end)
  end)

  describe("file_exists", function()
    it("should return true for existing file", function()
      local test_file = test_dir .. "/exists.txt"
      vim.fn.writefile({ "test" }, test_file)

      local done = false
      local result

      fs.file_exists(test_file, function(exists)
        result = exists
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_true(result)
    end)

    it("should return false for non-existent file", function()
      local done = false
      local result

      fs.file_exists(test_dir .. "/nonexistent.txt", function(exists)
        result = exists
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_false(result)
    end)
  end)

  describe("readdir", function()
    it("should list directory entries", function()
      vim.fn.writefile({ "test" }, test_dir .. "/file1.txt")
      vim.fn.writefile({ "test" }, test_dir .. "/file2.txt")
      vim.fn.mkdir(test_dir .. "/subdir", "p")

      local done = false
      local result_err, result_entries

      fs.readdir(test_dir, function(err, entries)
        result_err = err
        result_entries = entries
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_nil(result_err)
      assert.is_not_nil(result_entries)
      assert.equals(3, #result_entries)

      local names = {}
      for _, entry in ipairs(result_entries) do
        names[entry.name] = entry.type
      end

      assert.equals("file", names["file1.txt"])
      assert.equals("file", names["file2.txt"])
      assert.equals("directory", names["subdir"])
    end)
  end)

  describe("search_file", function()
    it("should find pattern in file", function()
      local test_file = test_dir .. "/search.lua"
      vim.fn.writefile({
        "local M = {}",
        '{ "nvim-lua/plenary.nvim" },',
        "return M",
      }, test_file)

      local done = false
      local result_found, result_line

      fs.search_file(test_file, { "plenary%.nvim" }, function(found, line)
        result_found = found
        result_line = line
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_true(result_found)
      assert.is_truthy(result_line:match("plenary"))
    end)

    it("should return false when pattern not found", function()
      local test_file = test_dir .. "/search.lua"
      vim.fn.writefile({
        "local M = {}",
        "return M",
      }, test_file)

      local done = false
      local result_found

      fs.search_file(test_file, { "nonexistent" }, function(found, line)
        result_found = found
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_false(result_found)
    end)
  end)

  describe("search_files", function()
    it("should find pattern across multiple files", function()
      vim.fn.writefile({ "local M = {}" }, test_dir .. "/file1.lua")
      vim.fn.writefile({ '{ "telescope.nvim" }' }, test_dir .. "/file2.lua")
      vim.fn.writefile({ "return M" }, test_dir .. "/file3.lua")

      local done = false
      local result_found, result_file

      fs.search_files({
        test_dir .. "/file1.lua",
        test_dir .. "/file2.lua",
        test_dir .. "/file3.lua",
      }, { "telescope%.nvim" }, function(found, file_path, line)
        result_found = found
        result_file = file_path
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_true(result_found)
      assert.equals(test_dir .. "/file2.lua", result_file)
    end)

    it("should return false when pattern not found in any file", function()
      vim.fn.writefile({ "local M = {}" }, test_dir .. "/file1.lua")
      vim.fn.writefile({ "return M" }, test_dir .. "/file2.lua")

      local done = false
      local result_found

      fs.search_files({
        test_dir .. "/file1.lua",
        test_dir .. "/file2.lua",
      }, { "nonexistent" }, function(found, file_path, line)
        result_found = found
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_false(result_found)
    end)
  end)

  describe("glob_async", function()
    it("should find files matching pattern", function()
      vim.fn.mkdir(test_dir .. "/plugins", "p")
      vim.fn.writefile({ "test" }, test_dir .. "/plugins/core.lua")
      vim.fn.writefile({ "test" }, test_dir .. "/plugins/ui.lua")
      vim.fn.writefile({ "test" }, test_dir .. "/other.txt")

      local done = false
      local result_err, result_files

      fs.glob_async(test_dir, "plugins/*.lua", function(err, files)
        result_err = err
        result_files = files
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_nil(result_err)
      assert.is_not_nil(result_files)
      assert.equals(2, #result_files)
    end)

    it("should handle nested directories with **", function()
      vim.fn.mkdir(test_dir .. "/a/b/plugins", "p")
      vim.fn.writefile({ "test" }, test_dir .. "/a/b/plugins/nested.lua")

      local done = false
      local result_err, result_files

      fs.glob_async(test_dir, "**/plugins/*.lua", function(err, files)
        result_err = err
        result_files = files
        done = true
      end)

      vim.wait(1000, function()
        return done
      end)

      assert.is_nil(result_err)
      assert.is_not_nil(result_files)
      assert.equals(1, #result_files)
      assert.is_truthy(result_files[1]:match("nested%.lua"))
    end)
  end)
end)
