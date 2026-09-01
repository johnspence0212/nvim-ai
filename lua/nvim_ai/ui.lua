local M = {}

local STROKE = "#7aa2f7"
local CARD_BG = "#1a1b26"
local CARD_FG = "#c0caf5"
local LINE_NR = "#3b4261"
local TOPBAR_BG = "#3d59a1"
local COLUMN_FRACTION = 0.3
local COMPOSER_INNER = 6
local EDGE = 1
local GAP = 1
local BORDER = 2

local transcript_buf
local composer_buf
local backdrop_buf
local transcript_win
local composer_win
local editor_win
local code_win
local code_buf
local remembered_width
local session_slot = "idle"
local layout_lock = false
local saved_laststatus
local saved_ruler

local function style()
  vim.opt.termguicolors = true
  vim.api.nvim_set_hl(0, "NaiTopBar", { bg = TOPBAR_BG, fg = "#ffffff" })
  vim.api.nvim_set_hl(0, "TabLine", { bg = TOPBAR_BG, fg = "#ffffff" })
  vim.api.nvim_set_hl(0, "TabLineFill", { bg = TOPBAR_BG, fg = "#c0caf5" })
  vim.api.nvim_set_hl(0, "TabLineSel", { bg = TOPBAR_BG, fg = "#ffffff" })
  vim.api.nvim_set_hl(0, "NaiCard", { fg = CARD_FG, bg = CARD_BG })
  vim.api.nvim_set_hl(0, "NaiLineNr", { fg = LINE_NR, bg = CARD_BG })
  vim.api.nvim_set_hl(0, "NaiStroke", { fg = STROKE, bg = CARD_BG, bold = true })
  vim.api.nvim_set_hl(0, "FloatBorder", { fg = STROKE, bg = CARD_BG, bold = true })
  vim.api.nvim_set_hl(0, "WinBorder", { fg = STROKE, bg = CARD_BG, bold = true })
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
  if not (backdrop_buf and vim.api.nvim_buf_is_valid(backdrop_buf)) then
    backdrop_buf = vim.api.nvim_create_buf(false, true)
    configure_buf(backdrop_buf, "nai://backdrop")
  end
end

local function win_ok(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function is_chat_win(win)
  return win == transcript_win or win == composer_win
end

local function visible()
  return win_ok(transcript_win) and win_ok(composer_win) and win_ok(editor_win)
end

local function close_win(win)
  if win_ok(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

local function root_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative == "" then
      return win
    end
  end
  return vim.api.nvim_get_current_win()
end

local function apply_backdrop(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].statusline = " "
  vim.wo[win].fillchars = "eob: "
end

local function apply_card(win, opts)
  vim.wo[win].winhighlight =
    "Normal:NaiCard,EndOfBuffer:NaiCard,FloatBorder:NaiStroke,WinBorder:NaiStroke,LineNr:NaiLineNr,CursorLineNr:NaiLineNr,SignColumn:NaiCard,FoldColumn:NaiCard"
  vim.wo[win].wrap = true
  if opts.minimal then
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].foldcolumn = "0"
    vim.wo[win].statusline = " "
  end
end

local function column_outer()
  if remembered_width then
    return remembered_width
  end
  return math.max(24, math.floor(vim.o.columns * COLUMN_FRACTION))
end

local function clamp_outer(width)
  local max = math.max(24, vim.o.columns - 28)
  return math.max(18, math.min(max, width))
end

-- Border is drawn outside (row, col). Convert an outer box (including
-- border) on the screen grid into nvim_open_win's inner content rect.
local function outer_to_nvim(box)
  return {
    row = box.r + 1,
    col = box.c + 1,
    width = math.max(1, box.w - 2),
    height = math.max(1, box.h - 2),
  }
end

local function layout_rects()
  local tab = vim.o.showtabline == 0 and 0 or 1
  local cmd = vim.o.cmdheight
  -- Top border sits on the row under the tabline (no extra header pad).
  -- EDGE is the margin to the frame; GAP is the gutter between cards.
  local grid_top = tab
  local grid_left = EDGE
  local grid_bottom = vim.o.lines - 1 - cmd - EDGE
  local grid_right = vim.o.columns - 1 - EDGE
  local grid_h = math.max(4, grid_bottom - grid_top + 1)
  local grid_w = math.max(8, grid_right - grid_left + 1)

  local chat_w = clamp_outer(column_outer())
  if chat_w > grid_w - 16 then
    chat_w = math.max(18, grid_w - 16)
  end
  local editor_w = grid_w - GAP - chat_w
  local composer_h = COMPOSER_INNER + BORDER
  if composer_h + GAP + BORDER + 1 > grid_h then
    composer_h = math.max(BORDER + 1, math.floor(grid_h / 3))
  end
  local transcript_h = grid_h - GAP - composer_h
  local chat_c = grid_left + editor_w + GAP

  return {
    editor = outer_to_nvim({ r = grid_top, c = grid_left, w = editor_w, h = grid_h }),
    transcript = outer_to_nvim({ r = grid_top, c = chat_c, w = chat_w, h = transcript_h }),
    composer = outer_to_nvim({
      r = grid_top + transcript_h + GAP,
      c = chat_c,
      w = chat_w,
      h = composer_h,
    }),
    chat_outer = chat_w,
  }
end

local function float_opts(rect, extra)
  local opts = {
    relative = "editor",
    row = rect.row,
    col = rect.col,
    width = rect.width,
    height = rect.height,
    border = "rounded",
    zindex = 50,
    focusable = true,
  }
  if extra then
    for k, v in pairs(extra) do
      opts[k] = v
    end
  end
  return opts
end

local function place(win, buf, rect, extra, enter)
  local opts = float_opts(rect, extra)
  if win_ok(win) then
    vim.api.nvim_win_set_config(win, {
      relative = opts.relative,
      row = opts.row,
      col = opts.col,
      width = opts.width,
      height = opts.height,
      border = opts.border,
      zindex = opts.zindex,
    })
    return win
  end
  return vim.api.nvim_open_win(buf, enter, opts)
end

local function relayout()
  if not visible() then
    return
  end
  local rects = layout_rects()
  remembered_width = rects.chat_outer
  place(editor_win, code_buf, rects.editor, nil, false)
  place(transcript_win, transcript_buf, rects.transcript, { style = "minimal" }, false)
  place(composer_win, composer_buf, rects.composer, { style = "minimal" }, false)
end

local function remember_code_win()
  if layout_lock then
    return
  end
  local cur = vim.api.nvim_get_current_win()
  if not win_ok(cur) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(cur)
  if buf == backdrop_buf or buf == transcript_buf or buf == composer_buf then
    if buf == backdrop_buf and win_ok(editor_win) then
      vim.api.nvim_set_current_win(editor_win)
    end
    return
  end
  if not is_chat_win(cur) then
    code_win = cur
  end
end

local function capture_code()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if buf ~= transcript_buf and buf ~= composer_buf and buf ~= backdrop_buf then
    code_buf = buf
    if vim.api.nvim_win_get_config(win).relative == "" then
      code_win = win
    end
    return
  end
  local root = root_win()
  local root_buf = vim.api.nvim_win_get_buf(root)
  if root_buf ~= backdrop_buf and root_buf ~= transcript_buf and root_buf ~= composer_buf then
    code_buf = root_buf
    code_win = root
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
    relayout()
    return
  end
  capture_code()
  layout_lock = true
  local ok, err = pcall(function()
    if saved_laststatus == nil then
      saved_laststatus = vim.o.laststatus
    end
    if saved_ruler == nil then
      saved_ruler = vim.o.ruler
    end
    vim.o.laststatus = 0
    vim.o.ruler = false

    local root = root_win()
    if not code_buf or not vim.api.nvim_buf_is_valid(code_buf) then
      code_buf = vim.api.nvim_win_get_buf(root)
    end
    vim.api.nvim_win_set_buf(root, backdrop_buf)
    apply_backdrop(root)

    local rects = layout_rects()
    remembered_width = rects.chat_outer
    editor_win = place(editor_win, code_buf, rects.editor, nil, false)
    apply_card(editor_win, { minimal = false })
    transcript_win = place(transcript_win, transcript_buf, rects.transcript, { style = "minimal" }, false)
    apply_card(transcript_win, { minimal = true })
    composer_win = place(composer_win, composer_buf, rects.composer, { style = "minimal" }, false)
    apply_card(composer_win, { minimal = true })

    vim.api.nvim_set_current_win(editor_win)
    code_win = editor_win
  end)
  layout_lock = false
  if not ok then
    error(err)
  end
end

function M.hide()
  if not (win_ok(transcript_win) or win_ok(composer_win) or win_ok(editor_win)) then
    return
  end
  if visible() then
    local cfg = vim.api.nvim_win_get_config(transcript_win)
    remembered_width = (cfg.width or 0) + BORDER
  end
  layout_lock = true
  local ok, err = pcall(function()
    local root = root_win()
    close_win(composer_win)
    close_win(transcript_win)
    close_win(editor_win)
    composer_win = nil
    transcript_win = nil
    editor_win = nil
    if code_buf and vim.api.nvim_buf_is_valid(code_buf) then
      vim.api.nvim_win_set_buf(root, code_buf)
    end
    vim.wo[root].statusline = nil
    vim.wo[root].fillchars = nil
    if saved_laststatus ~= nil then
      vim.o.laststatus = saved_laststatus
      saved_laststatus = nil
    end
    if saved_ruler ~= nil then
      vim.o.ruler = saved_ruler
      saved_ruler = nil
    end
    vim.api.nvim_set_current_win(root)
    code_win = root
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

function M.grow_current(delta)
  if not visible() then
    return false
  end
  local cur = vim.api.nvim_get_current_win()
  if is_chat_win(cur) then
    remembered_width = clamp_outer(column_outer() + delta)
  else
    remembered_width = clamp_outer(column_outer() - delta)
  end
  relayout()
  return true
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
  local group = vim.api.nvim_create_augroup("NaiChatLayout", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      remember_code_win()
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if visible() then
        relayout()
      end
    end,
  })
  vim.keymap.set("n", "<C-w>>", function()
    if not M.grow_current(vim.v.count1) then
      vim.cmd(vim.v.count1 .. "wincmd >")
    end
  end, { desc = "Grow window / Chat column" })
  vim.keymap.set("n", "<C-w><", function()
    if not M.grow_current(-vim.v.count1) then
      vim.cmd(vim.v.count1 .. "wincmd <")
    end
  end, { desc = "Shrink window / Chat column" })
end

return M
