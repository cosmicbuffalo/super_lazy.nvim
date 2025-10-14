local config = require("super_lazy.config")

describe("config module", function()
  before_each(function()
    -- Reset config for each test
    config.options = {}
  end)

  it("should have compatible lazy version defined", function()
    assert.is_not_nil(config.COMPATIBLE_LAZY_VERSION)
    assert.equals("11.17.1", config.COMPATIBLE_LAZY_VERSION)
  end)

  it("should setup with default config", function()
    local result = config.setup()
    assert.is_not_nil(result)
    assert.is_not_nil(result.lockfile_repo_dirs)
    assert.equals(1, #result.lockfile_repo_dirs)
  end)

  it("should merge user config with defaults", function()
    local user_config = {
      lockfile_repo_dirs = { "/custom/path1", "/custom/path2" },
    }
    local result = config.setup(user_config)
    assert.equals(2, #result.lockfile_repo_dirs)
    assert.equals("/custom/path1", result.lockfile_repo_dirs[1])
    assert.equals("/custom/path2", result.lockfile_repo_dirs[2])
  end)

  it("should store options after setup", function()
    config.setup({ lockfile_repo_dirs = { "/test" } })
    assert.is_not_nil(config.options)
    assert.equals("/test", config.options.lockfile_repo_dirs[1])
  end)

  it("should handle empty user config", function()
    local result = config.setup({})
    assert.is_not_nil(result)
    assert.is_not_nil(result.lockfile_repo_dirs)
  end)

  it("should handle nil user config", function()
    local result = config.setup(nil)
    assert.is_not_nil(result)
    assert.is_not_nil(result.lockfile_repo_dirs)
  end)
end)
