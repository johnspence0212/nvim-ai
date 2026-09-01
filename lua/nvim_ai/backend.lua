local acp = require("nvim_ai.acp")

local M = {}

function M.is_inflight()
  return acp.is_inflight()
end

function M.prompt(text, callbacks)
  return acp.prompt(text, callbacks)
end

function M.cancel()
  acp.cancel()
end

return M
