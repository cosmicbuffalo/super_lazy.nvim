local Util = require("super_lazy.util")

local M = {}

local current_operation = nil

local function get_fidget_handle()
  local ok, fidget = pcall(require, "fidget")
  if ok and fidget.progress and fidget.progress.handle then
    return fidget.progress.handle
  end
  return nil
end

local function create_progress(title, total, silent)
  if silent then
    return nil
  end

  local handle = get_fidget_handle()
  if handle then
    return {
      type = "fidget",
      handle = handle.create({
        title = title,
        message = "Starting...",
        lsp_client = { name = "super_lazy" },
        percentage = 0,
        cancellable = true,
      }),
    }
  end
  Util.notify(title .. "...")
  return {
    type = "fallback",
    title = title,
  }
end

local function update_progress(progress, current, total, item_name)
  if not progress then
    return
  end

  if progress.type == "fidget" and progress.handle then
    progress.handle:report({
      message = string.format("(%d/%d) %s", current, total, item_name or "unknown"),
      percentage = math.floor((current - 1) / total * 100),
    })
  end
end

local function finish_progress(progress, message)
  if not progress then
    return
  end

  if progress.type == "fidget" and progress.handle then
    progress.handle:finish()
  elseif progress.type == "fallback" and message then
    Util.notify(message)
  end
end

local function cancel_progress(progress)
  if not progress then
    return
  end

  if progress.type == "fidget" and progress.handle then
    pcall(function()
      progress.handle:cancel()
    end)
  end
end

function M.cancel_current()
  if current_operation then
    current_operation.cancelled = true
    cancel_progress(current_operation.progress)
    current_operation = nil
  end
end

function M.reset()
  M.cancel_current()
end

function M.is_busy()
  return current_operation ~= nil
end

-- Process items asynchronously with a synchronous process_fn
-- opts = {
--   items = { ... },                       -- List of items to process
--   process_fn = function(item) end,       -- Function to process each item (sync)
--   on_complete = function(results) end,   -- Called when all done (optional)
--   on_cancel = function() end,            -- Called if cancelled (optional)
--   title = "...",                         -- Progress title
--   completion_message = "...",            -- Message to show on completion (optional)
--   get_item_name = function(item) end,    -- Get display name for item (optional)
--   silent = bool,                         -- Suppress progress notifications (optional)
-- }
function M.process_async(opts)
  M.cancel_current()

  local items = opts.items
  local total = #items

  if total == 0 then
    if opts.on_complete then
      opts.on_complete({})
    end
    return
  end

  local index = 1
  local results = {}

  local operation = {
    cancelled = false,
    progress = create_progress(opts.title, total, opts.silent),
  }
  current_operation = operation

  local function process_next()
    if operation.cancelled then
      if opts.on_cancel then
        opts.on_cancel()
      end
      return
    end

    if index > total then
      finish_progress(operation.progress, opts.completion_message)
      current_operation = nil
      if opts.on_complete then
        opts.on_complete(results)
      end
      return
    end

    local item = items[index]
    local item_name = opts.get_item_name and opts.get_item_name(item) or tostring(index)
    update_progress(operation.progress, index, total, item_name)

    local ok, result = pcall(opts.process_fn, item)
    if ok then
      results[item_name] = result
    else
      Util.notify("Error processing " .. item_name .. ": " .. tostring(result), vim.log.levels.WARN)
    end

    index = index + 1
    vim.schedule(process_next)
  end

  vim.schedule(process_next)
end

-- Process items with an async process_fn that takes a callback
-- opts = {
--   items = { ... },                              -- List of items to process
--   process_fn = function(item, callback) end,   -- Async function, calls callback(result) when done
--   on_complete = function(results) end,         -- Called when all done (optional)
--   on_cancel = function() end,                  -- Called if cancelled (optional)
--   title = "...",                               -- Progress title
--   completion_message = "...",                  -- Message to show on completion (optional)
--   get_item_name = function(item) end,          -- Get display name for item (optional)
--   silent = bool,                               -- Suppress progress notifications (optional)
-- }
function M.process_async_with_callback(opts)
  M.cancel_current()

  local items = opts.items
  local total = #items

  if total == 0 then
    if opts.on_complete then
      opts.on_complete({})
    end
    return
  end

  local index = 1
  local results = {}

  local operation = {
    cancelled = false,
    progress = create_progress(opts.title, total, opts.silent),
  }
  current_operation = operation

  local function process_next()
    if operation.cancelled then
      if opts.on_cancel then
        opts.on_cancel()
      end
      return
    end

    if index > total then
      finish_progress(operation.progress, opts.completion_message)
      current_operation = nil
      if opts.on_complete then
        opts.on_complete(results)
      end
      return
    end

    local item = items[index]
    local item_name = opts.get_item_name and opts.get_item_name(item) or tostring(index)
    update_progress(operation.progress, index, total, item_name)

    local ok, err = pcall(opts.process_fn, item, function(result)
      if operation.cancelled then
        if opts.on_cancel then
          opts.on_cancel()
        end
        return
      end

      results[item_name] = result
      index = index + 1
      vim.schedule(process_next)
    end)

    if not ok then
      Util.notify("Error processing " .. item_name .. ": " .. tostring(err), vim.log.levels.WARN)
      index = index + 1
      vim.schedule(process_next)
    end
  end

  vim.schedule(process_next)
end

return M
