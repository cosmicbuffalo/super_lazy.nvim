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

end)
