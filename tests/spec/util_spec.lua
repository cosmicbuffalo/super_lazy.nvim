local util = require("super_lazy.util")

describe("util module", function()
  describe("notify", function()
    it("should be a function", function()
      assert.is_function(util.notify)
    end)

    it("should call vim.notify with formatted message", function()
      local original_notify = vim.notify
      local called = false
      local captured_msg = nil
      local captured_level = nil
      local captured_opts = nil

      vim.notify = function(msg, level, opts)
        called = true
        captured_msg = msg
        captured_level = level
        captured_opts = opts
      end

      util.notify("test message", vim.log.levels.INFO)

      vim.notify = original_notify

      assert.is_true(called)
      assert.equals("super_lazy.nvim: test message", captured_msg)
      assert.equals(vim.log.levels.INFO, captured_level)
      assert.same({ title = "super_lazy.nvim" }, captured_opts)
    end)

    it("should default to INFO level when level not provided", function()
      local original_notify = vim.notify
      local captured_level = nil

      vim.notify = function(msg, level, opts)
        captured_level = level
      end

      util.notify("test")

      vim.notify = original_notify

      assert.equals(vim.log.levels.INFO, captured_level)
    end)

    it("should support different log levels", function()
      local original_notify = vim.notify
      local levels = {
        vim.log.levels.ERROR,
        vim.log.levels.WARN,
        vim.log.levels.INFO,
        vim.log.levels.DEBUG,
      }

      for _, level in ipairs(levels) do
        local captured_level = nil

        vim.notify = function(msg, lvl, opts)
          captured_level = lvl
        end

        util.notify("test", level)

        assert.equals(level, captured_level)
      end

      vim.notify = original_notify
    end)
  end)

  describe("format_path", function()
    it("should be a function", function()
      assert.is_function(util.format_path)
    end)

    it("should replace home directory with tilde", function()
      local home = vim.fn.expand("~")
      local path = home .. "/some/path/to/file"
      local result = util.format_path(path)
      assert.equals("~/some/path/to/file", result)
    end)

    it("should return path unchanged if not under home", function()
      local path = "/tmp/some/path"
      local result = util.format_path(path)
      assert.equals("/tmp/some/path", result)
    end)

    it("should resolve symlinks", function()
      -- Create a temporary symlink
      local test_dir = "/tmp/format_path_test_" .. os.time()
      local real_dir = test_dir .. "/real"
      local symlink = test_dir .. "/link"

      vim.fn.mkdir(real_dir, "p")
      vim.fn.system({ "ln", "-s", real_dir, symlink })

      local result = util.format_path(symlink)
      -- Result should be the resolved path (real_dir), possibly with ~ substitution
      local expected = real_dir
      local home = vim.fn.expand("~")
      if expected:sub(1, #home) == home then
        expected = "~" .. expected:sub(#home + 1)
      end
      assert.equals(expected, result)

      -- Cleanup
      vim.fn.delete(test_dir, "rf")
    end)

    it("should handle home directory exactly", function()
      local home = vim.fn.expand("~")
      local result = util.format_path(home)
      assert.equals("~", result)
    end)
  end)
end)
