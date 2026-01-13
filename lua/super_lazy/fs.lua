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

return M
