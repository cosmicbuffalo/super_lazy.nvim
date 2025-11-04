local M = {}

local function get_cache_dir()
  return vim.fn.stdpath("data") .. "/super_lazy"
end

local function get_cache_file()
  return get_cache_dir() .. "/original_lockfile.json"
end

function M.read(path)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  local content = vim.fn.readfile(path)
  local json_str = table.concat(content, "\n")

  local ok, decoded = pcall(vim.json.decode, json_str)
  if not ok then
    return {}
  end

  return decoded
end

function M.write(path, data)
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")

  -- Format lockfile exactly like lazy.nvim does (with pretty indentation)
  local f = assert(io.open(path, "wb"))

  local names = vim.tbl_keys(data)
  table.sort(names)

  if #names == 0 then
    -- Empty lockfile
    f:write("{\n}\n")
  else
    f:write("{\n")
    for n, name in ipairs(names) do
      local info = data[name]
      if info.source then
        f:write(
          ([[  %q: { "branch": %q, "commit": %q, "source": %q }]]):format(name, info.branch, info.commit, info.source)
        )
      else
        f:write(([[  %q: { "branch": %q, "commit": %q }]]):format(name, info.branch, info.commit))
      end
      if n ~= #names then
        f:write(",\n")
      end
    end
    f:write("\n}\n")
  end

  f:close()
end

local function get_current_commit()
  local config_dir = vim.fn.stdpath("config")

  local result = vim.fn.system({
    "git",
    "-C",
    config_dir,
    "rev-parse",
    "HEAD",
  })

  if vim.v.shell_error ~= 0 then
    return nil
  end

  return vim.trim(result)
end

local function get_from_git()
  local config_dir = vim.fn.stdpath("config")

  local git_check = vim.fn.system({ "git", "-C", config_dir, "rev-parse", "--git-dir" })
  if vim.v.shell_error ~= 0 then
    return nil
  end

  local result = vim.fn.system({
    "git",
    "-C",
    config_dir,
    "show",
    "HEAD:lazy-lock.json",
  })

  if vim.v.shell_error ~= 0 then
    return nil
  end

  local ok, lockfile_data = pcall(vim.json.decode, result)
  if ok and lockfile_data then
    return lockfile_data
  end

  return nil
end

local function cache_lockfile(commit, lockfile)
  local cache_dir = get_cache_dir()
  local cache_file = get_cache_file()
  vim.fn.mkdir(cache_dir, "p")

  local cache_data = {
    timestamp = os.time(),
    commit = commit,
    lockfile = lockfile,
  }

  local encoded = vim.json.encode(cache_data)
  vim.fn.writefile(vim.split(encoded, "\n"), cache_file)

  return true
end

function M.get_cached()
  local current_commit = get_current_commit()
  local cache_file = get_cache_file()
  if vim.fn.filereadable(cache_file) == 1 then
    local cache_content = vim.fn.readfile(cache_file)
    local ok, cache_data = pcall(vim.json.decode, table.concat(cache_content, "\n"))

    if ok and cache_data and cache_data.commit == current_commit and cache_data.lockfile then
      return cache_data.lockfile
    end
  end

  local from_git = get_from_git()
  if from_git then
    cache_lockfile(current_commit, from_git)
    return from_git
  end

  return nil
end

function M.clear_cache()
  local cache_file = get_cache_file()
  pcall(vim.fn.delete, cache_file)
end

return M
