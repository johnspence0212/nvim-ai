-- Stub backend. ACP replaces this in a later ticket.
local M = {}

local FAKE_REPLY =
  "Chunks arrive as session/update agent_message_chunk. The Profile appends each text fragment. The turn ends when session/prompt returns stopReason end_turn."
local INTERVAL_MS = 70

local inflight = false
local timer = nil
local cbs = nil

local function chunkify(text)
  local chunks = {}
  for word in text:gmatch("%S+") do
    chunks[#chunks + 1] = word
  end
  return chunks
end

local function stop_timer()
  if timer then
    vim.fn.timer_stop(timer)
    timer = nil
  end
end

local function finish()
  stop_timer()
  local done = cbs
  inflight = false
  cbs = nil
  if done and done.on_done then
    done.on_done()
  end
end

function M.is_inflight()
  return inflight
end

function M.prompt(_text, callbacks)
  if inflight then
    return false
  end
  inflight = true
  cbs = callbacks
  local chunks = chunkify(FAKE_REPLY)
  local i = 1
  timer = vim.fn.timer_start(INTERVAL_MS, function()
    if i > #chunks then
      finish()
      return
    end
    local piece = chunks[i]
    if i > 1 then
      piece = " " .. piece
    end
    if cbs and cbs.on_chunk then
      cbs.on_chunk(piece)
    end
    i = i + 1
  end, { ["repeat"] = -1 })
  return true
end

function M.cancel()
  if not inflight then
    return
  end
  finish()
end

return M
