local M = {}

function M.parse(text)
  if type(text) ~= "string" then
    return nil
  end
  if text == "/ns" then
    return { name = "ns" }
  end
  if text == "/nn" then
    return { name = "nn" }
  end
  local title = text:match("^/nn%s+(.+)$")
  if title and title ~= "" then
    return { name = "nn", title = title }
  end
  return nil
end

return M
