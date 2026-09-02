local acp = require("nvim_ai.acp")

local M = {}

function M.is_inflight(acp_id)
  return acp.is_inflight(acp_id)
end

function M.prompt(text, callbacks, acp_id)
  return acp.prompt(text, callbacks, acp_id)
end

function M.cancel(acp_id)
  acp.cancel(acp_id)
end

return M
