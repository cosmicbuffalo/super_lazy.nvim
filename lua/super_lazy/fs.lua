local M = {}

local uv = vim.uv or vim.loop

function M.read_file(path, callback)
  uv.fs_open(path, "r", 0, function(err, fd)
    if err then
      callback(err, nil)
      return
    end

    uv.fs_fstat(fd, function(stat_err, stat)
      if stat_err then
        uv.fs_close(fd)
        callback(stat_err, nil)
        return
      end

      uv.fs_read(fd, stat.size, 0, function(read_err, data)
        uv.fs_close(fd)
        if read_err then
          callback(read_err, nil)
          return
        end
        callback(nil, data)
      end)
    end)
  end)
end

function M.file_exists(path, callback)
  uv.fs_stat(path, function(err, stat)
    callback(not err and stat ~= nil)
  end)
end

function M.readdir(path, callback)
  uv.fs_opendir(path, function(err, dir)
    if err then
      callback(err, nil)
      return
    end

    local entries = {}
    local function read_next()
      uv.fs_readdir(dir, function(read_err, ents)
        if read_err then
          uv.fs_closedir(dir)
          callback(read_err, nil)
          return
        end

        if not ents then
          -- No more entries
          uv.fs_closedir(dir)
          callback(nil, entries)
          return
        end

        for _, entry in ipairs(ents) do
          table.insert(entries, entry)
        end
        read_next()
      end)
    end
    read_next()
  end)
end

function M.glob_async(base_path, pattern, callback)
  local results = {}
  local pending = 0
  local has_error = false

  local function glob_to_pattern(glob)
    local pat = glob
    pat = pat:gsub("%.", "%%.")
    pat = pat:gsub("%*%*", "\001")
    pat = pat:gsub("%*", "[^/]*")
    pat = pat:gsub("\001", ".*")
    return "^" .. pat .. "$"
  end

  local lua_pattern = glob_to_pattern(pattern)

  local function check_done()
    if pending == 0 and not has_error then
      callback(nil, results)
    end
  end

  local function scan_dir(dir_path, rel_path)
    pending = pending + 1
    M.readdir(dir_path, function(err, entries)
      pending = pending - 1
      if has_error then
        return
      end
      if err then
        check_done()
        return
      end

      for _, entry in ipairs(entries) do
        local full_path = dir_path .. "/" .. entry.name
        local relative = rel_path == "" and entry.name or (rel_path .. "/" .. entry.name)

        if entry.type == "directory" then
          scan_dir(full_path, relative)
        elseif entry.type == "file" then
          if relative:match(lua_pattern) then
            table.insert(results, full_path)
          end
        end
      end
      check_done()
    end)
  end

  scan_dir(base_path, "")
end

function M.search_file(path, patterns, callback)
  M.read_file(path, function(err, content)
    if err or not content then
      callback(false, nil)
      return
    end

    for line in content:gmatch("[^\r\n]+") do
      for _, pattern in ipairs(patterns) do
        if line:find(pattern) then
          callback(true, line)
          return
        end
      end
    end
    callback(false, nil)
  end)
end

function M.search_files(files, patterns, callback)
  if #files == 0 then
    callback(false, nil, nil)
    return
  end

  local index = 1
  local function search_next()
    if index > #files then
      callback(false, nil, nil)
      return
    end

    local file = files[index]
    M.search_file(file, patterns, function(found, line)
      if found then
        callback(true, file, line)
      else
        index = index + 1
        vim.schedule(search_next)
      end
    end)
  end

  search_next()
end

return M
