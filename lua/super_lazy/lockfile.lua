local M = {}

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
      f:write(([[  %q: { "branch": %q, "commit": %q }]]):format(name, info.branch, info.commit))
      if n ~= #names then
        f:write(",\n")
      end
    end
    f:write("\n}\n")
  end

  f:close()
end

return M
