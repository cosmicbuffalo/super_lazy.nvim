local Util = require("super_lazy.util")

local M = {}

-- State for tracking in-progress operations
local current_operation = nil

-- Check if fidget is available and has the progress handle API
local function get_fidget_handle()
  local ok, fidget = pcall(require, "fidget")
  if ok and fidget.progress and fidget.progress.handle then
    return fidget.progress.handle
  end
  return nil
end

-- Create a progress handle (fidget or fallback)
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
  -- Fallback: notify at start
  Util.notify(title .. "...")
  return {
    type = "fallback",
    title = title,
  }
end

-- Update progress
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
  -- Fallback: no intermediate updates
end

-- Finish progress
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

-- Cancel progress
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

-- Cancel any in-progress operation
function M.cancel_current()
  if current_operation then
    current_operation.cancelled = true
    cancel_progress(current_operation.progress)
    current_operation = nil
  end
end

-- Reset all async state (for testing)
function M.reset()
  M.cancel_current()
  M._test_scheduler = nil
end

-- Check if there's an operation in progress
function M.is_busy()
  return current_operation ~= nil
end

-- For testing: allows setting a custom scheduler function
-- When set to a function, it will be used instead of vim.schedule
M._test_scheduler = nil

local function schedule(fn)
  if M._test_scheduler then
    M._test_scheduler(fn)
  else
    vim.schedule(fn)
  end
end

-- Process items asynchronously, one per tick (SYNC process_fn version)
function M.process_async(opts)
  -- opts = {
  --   items = { ... },              -- List of items to process
  --   process_fn = function(item) ... end,  -- Function to process each item (SYNC)
  --   on_complete = function(results) ... end,  -- Called when all done
  --   on_cancel = function() ... end,  -- Called if cancelled (optional)
  --   title = "...",                -- Progress title
  --   completion_message = "...",   -- Message to show on completion (fallback only)
  --   get_item_name = function(item) ... end,  -- Get display name for item (optional)
  --   silent = false,               -- If true, suppress progress notifications (optional)
  -- }

  M.cancel_current() -- Cancel any existing operation

  local items = opts.items
  local total = #items

  if total == 0 then
    -- Nothing to process
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
      -- All done
      finish_progress(operation.progress, opts.completion_message)
      current_operation = nil
      if opts.on_complete then
        opts.on_complete(results)
      end
      return
    end

    local item = items[index]
    local item_name = opts.get_item_name and opts.get_item_name(item) or tostring(index)

    -- Update progress
    update_progress(operation.progress, index, total, item_name)

    -- Process this item
    local ok, result = pcall(opts.process_fn, item)
    if ok then
      results[item_name] = result
    else
      -- Log error but continue processing
      Util.notify("Error processing " .. item_name .. ": " .. tostring(result), vim.log.levels.WARN)
    end

    index = index + 1

    -- Schedule next iteration
    schedule(process_next)
  end

  -- Start processing
  schedule(process_next)
end

-- Process items with ASYNC process_fn (process_fn takes a callback)
-- This is truly non-blocking as each item's processing is also async
function M.process_async_with_callback(opts)
  -- opts = {
  --   items = { ... },              -- List of items to process
  --   process_fn = function(item, callback) ... end,  -- Async function, calls callback(result) when done
  --   on_complete = function(results) ... end,  -- Called when all done
  --   on_cancel = function() ... end,  -- Called if cancelled (optional)
  --   title = "...",                -- Progress title
  --   completion_message = "...",   -- Message to show on completion (fallback only)
  --   get_item_name = function(item) ... end,  -- Get display name for item (optional)
  --   silent = false,               -- If true, suppress progress notifications (optional)
  -- }

  M.cancel_current() -- Cancel any existing operation

  local items = opts.items
  local total = #items

  if total == 0 then
    -- Nothing to process
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
      -- All done
      finish_progress(operation.progress, opts.completion_message)
      current_operation = nil
      if opts.on_complete then
        opts.on_complete(results)
      end
      return
    end

    local item = items[index]
    local item_name = opts.get_item_name and opts.get_item_name(item) or tostring(index)

    -- Update progress
    update_progress(operation.progress, index, total, item_name)

    -- Process this item asynchronously
    local ok, err = pcall(opts.process_fn, item, function(result)
      if operation.cancelled then
        if opts.on_cancel then
          opts.on_cancel()
        end
        return
      end

      results[item_name] = result
      index = index + 1

      -- Schedule next iteration (use vim.schedule to ensure we're in main loop)
      schedule(process_next)
    end)

    if not ok then
      -- process_fn itself threw an error
      Util.notify("Error processing " .. item_name .. ": " .. tostring(err), vim.log.levels.WARN)
      index = index + 1
      schedule(process_next)
    end
  end

  -- Start processing
  schedule(process_next)
end

return M
