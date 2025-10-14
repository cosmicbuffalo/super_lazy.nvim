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
end)
