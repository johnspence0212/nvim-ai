local M = {}

local bufnr

local function ensure_buf()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    return bufnr
  end
  bufnr = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, bufnr, "nai://scratch")
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  return bufnr
end

function M.open()
  local buf = ensure_buf()
  local wins = vim.fn.win_findbuf(buf)
  if #wins == 0 then
    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, buf)
  else
    vim.api.nvim_set_current_win(wins[1])
  end
end

function M.start_turn(prompt)
  local buf = ensure_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local empty = #lines == 1 and lines[1] == ""
  local block = { "You", prompt, "", "Agent", "" }
  if empty then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, block)
  else
    local appended = { "" }
    for _, line in ipairs(block) do
      appended[#appended + 1] = line
    end
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, appended)
  end
end

function M.append_agent(chunk)
  local buf = ensure_buf()
  local last = vim.api.nvim_buf_line_count(buf) - 1
  local line = vim.api.nvim_buf_get_lines(buf, last, last + 1, false)[1] or ""
  local parts = vim.split(line .. chunk, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, last, last + 1, false, parts)
end

function M.bufnr()
  return bufnr
end

return M
