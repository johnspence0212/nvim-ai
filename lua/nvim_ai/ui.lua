local M = {}

local STROKE = "#7aa2f7"
local TOPBAR_BG = "#3d59a1"
local COLUMN_FRACTION = 0.3
local COMPOSER_HEIGHT = 8

local transcript_buf
local composer_buf
local transcript_win
local composer_win
local code_win
local remembered_width
local session_slot = "idle"
local layout_lock = false

local function style()
  vim.api.nvim_set_hl(0, "NaiTopBar", { bg = TOPBAR_BG, fg = "#ffffff" })
  vim.api.nvim_set_hl(0, "TabLine", { bg = TOPBAR_BG, fg = "#ffffff" })
  vim.api.nvim_set_hl(0, "TabLineFill", { bg = TOPBAR_BG, fg = "#c0caf5" })
  vim.api.nvim_set_hl(0, "TabLineSel", { bg = TOPBAR_BG, fg = "#ffffff" })
  vim.api.nvim_set_hl(0, "WinSeparator", { fg = STROKE })
  vim.api.nvim_set_hl(0, "WinBorder", { fg = STROKE })
  vim.api.nvim_set_hl(0, "FloatBorder", { fg = STROKE })
end

local function configure_buf(buf, name)
  pcall(vim.api.nvim_buf_set_name, buf, name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
end

local function ensure_bufs()
  if not (transcript_buf and vim.api.nvim_buf_is_valid(transcript_buf)) then
    transcript_buf = vim.api.nvim_create_buf(false, true)
    configure_buf(transcript_buf, "nai://transcript")
    vim.bo[transcript_buf].modifiable = false
  end
  if not (composer_buf and vim.api.nvim_buf_is_valid(composer_buf)) then
    composer_buf = vim.api.nvim_create_buf(false, true)
    configure_buf(composer_buf, "nai://composer")
  end
end

local function is_chat_buf(buf)
  return buf == transcript_buf or buf == composer_buf
end

local function is_chat_win(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end
  return is_chat_buf(vim.api.nvim_win_get_buf(win))
end

local function win_ok(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function visible()
  return win_ok(transcript_win) and win_ok(composer_win)
end

local function close_win(win)
  if win_ok(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function remember_code_win()
  if layout_lock then
    return
  end
  local cur = vim.api.nvim_get_current_win()
  if not is_chat_win(cur) then
    code_win = cur
  end
end

local function focus_code()
  if win_ok(code_win) and not is_chat_win(code_win) then
    vim.api.nvim_set_current_win(code_win)
    return
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not is_chat_win(win) then
      code_win = win
      vim.api.nvim_set_current_win(win)
      return
    end
  end
end

local function apply_chat_win(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].wrap = true
  vim.wo[win].winfixwidth = true
end

local function column_width()
  if remembered_width then
    return remembered_width
  end
  return math.max(20, math.floor(vim.o.columns * COLUMN_FRACTION))
end

local function snapshot_width()
  if win_ok(transcript_win) then
    remembered_width = vim.api.nvim_win_get_width(transcript_win)
  elseif win_ok(composer_win) then
    remembered_width = vim.api.nvim_win_get_width(composer_win)
  end
end

function M.tabline()
  local left =
    " <leader>nn hide/show  <leader>nc cancel  <leader>nk cheatsheet  <C-w>> grow  <C-w>< shrink "
  return "%#NaiTopBar#" .. left .. "%=%#TabLineFill# Session · " .. session_slot .. " "
end

function M.show()
  style()
  ensure_bufs()
  if visible() then
    return
  end
  remember_code_win()
  layout_lock = true
  local ok, err = pcall(function()
    close_win(transcript_win)
    close_win(composer_win)

    vim.cmd("botright vsplit")
    transcript_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(transcript_win, transcript_buf)
    vim.api.nvim_win_set_width(transcript_win, column_width())
    apply_chat_win(transcript_win)

    vim.cmd("belowright split")
    composer_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(composer_win, composer_buf)
    vim.api.nvim_win_set_height(composer_win, COMPOSER_HEIGHT)
    apply_chat_win(composer_win)

    if win_ok(code_win) and not is_chat_win(code_win) then
      vim.api.nvim_set_current_win(code_win)
    end
  end)
  layout_lock = false
  if not ok then
    error(err)
  end
end

function M.hide()
  if not (win_ok(transcript_win) or win_ok(composer_win)) then
    return
  end
  snapshot_width()
  layout_lock = true
  local ok, err = pcall(function()
    focus_code()
    close_win(composer_win)
    close_win(transcript_win)
    transcript_win = nil
    composer_win = nil
  end)
  layout_lock = false
  if not ok then
    error(err)
  end
end

function M.toggle()
  if visible() then
    M.hide()
  else
    M.show()
    if win_ok(composer_win) then
      vim.api.nvim_set_current_win(composer_win)
    end
  end
end

function M.open()
  M.show()
  if win_ok(transcript_win) then
    vim.api.nvim_set_current_win(transcript_win)
  end
end

function M.start_turn(prompt)
  ensure_bufs()
  vim.bo[transcript_buf].modifiable = true
  local lines = vim.api.nvim_buf_get_lines(transcript_buf, 0, -1, false)
  local empty = #lines == 1 and lines[1] == ""
  local block = { "You", prompt, "", "Agent", "" }
  if empty then
    vim.api.nvim_buf_set_lines(transcript_buf, 0, -1, false, block)
  else
    local appended = { "" }
    for _, line in ipairs(block) do
      appended[#appended + 1] = line
    end
    vim.api.nvim_buf_set_lines(transcript_buf, -1, -1, false, appended)
  end
  vim.bo[transcript_buf].modifiable = false
end

function M.append_agent(chunk)
  ensure_bufs()
  vim.bo[transcript_buf].modifiable = true
  local last = vim.api.nvim_buf_line_count(transcript_buf) - 1
  local line = vim.api.nvim_buf_get_lines(transcript_buf, last, last + 1, false)[1] or ""
  local parts = vim.split(line .. chunk, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(transcript_buf, last, last + 1, false, parts)
  vim.bo[transcript_buf].modifiable = false
end

function M.bufnr()
  return transcript_buf
end

function M.setup()
  style()
  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.require('nvim_ai.ui').tabline()"
  vim.o.winborder = "rounded"
  vim.o.equalalways = false
  vim.o.laststatus = 3
  vim.api.nvim_create_autocmd("WinEnter", {
    group = vim.api.nvim_create_augroup("NaiChatFocus", { clear = true }),
    callback = function()
      remember_code_win()
    end,
  })
end

return M
