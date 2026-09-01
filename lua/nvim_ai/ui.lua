local M = {}

local markdown = require("nvim_ai.markdown")

local STROKE = "#7aa2f7"
local CARD_BG = "#1a1b26"
local CARD_FG = "#c0caf5"
local LINE_NR = "#3b4261"
local TOPBAR_BG = "#3d59a1"
local COLUMN_FRACTION = 0.3
local COMPOSER_INNER = 12
local EDGE = 1
local GAP = 1
local BORDER = 2
local CHEATSHEET_Z = 60
local CHEATSHEET_LINES = {
  "Command cheatsheet",
  "",
  "<leader>nn     hide/show Chat",
  "<leader>nc     cancel (drops pending)",
  "<leader>nk     this cheatsheet",
  "Enter          send (one pending while in flight)",
  "Shift-Enter    newline in Composer",
  "<C-w>>         grow Chat column",
  "<C-w><         shrink Chat column",
}

local transcript_buf
local composer_buf
local backdrop_buf
local cheatsheet_buf
local transcript_win
local composer_win
local editor_win
local cheatsheet_win
local code_win
local code_buf
local remembered_width
local session_slot = "idle"
local layout_lock = false
local saved_laststatus
local saved_ruler
local on_send
local pending_start
local pending_len
local stream_row
local agent_start
local agent_plain
local md_ns
local composer_maps_buf
local wire_composer

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
  vim.api.nvim_set_hl(0, "NaiMdHeading", { fg = STROKE, bg = CARD_BG, bold = true })
  vim.api.nvim_set_hl(0, "NaiMdBold", { fg = CARD_FG, bg = CARD_BG, bold = true })
  vim.api.nvim_set_hl(0, "NaiMdItalic", { fg = CARD_FG, bg = CARD_BG, italic = true })
  vim.api.nvim_set_hl(0, "NaiMdCode", { fg = "#9ece6a", bg = "#292e42" })
  vim.api.nvim_set_hl(0, "NaiMdFence", { fg = "#9ece6a", bg = "#292e42" })
  vim.api.nvim_set_hl(0, "NaiMdList", { fg = STROKE, bg = CARD_BG })
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
    wire_composer()
  end
  if not (backdrop_buf and vim.api.nvim_buf_is_valid(backdrop_buf)) then
    backdrop_buf = vim.api.nvim_create_buf(false, true)
    configure_buf(backdrop_buf, "nai://backdrop")
  end
end

wire_composer = function()
  if not composer_buf or composer_maps_buf == composer_buf then
    return
  end
  composer_maps_buf = composer_buf
  local function send()
    if on_send then
      on_send()
    end
  end
  vim.keymap.set("i", "<CR>", send, { buffer = composer_buf, desc = "Send from Composer" })
  vim.keymap.set("i", "<S-CR>", "<C-j>", { buffer = composer_buf, desc = "Newline in Composer" })
  vim.keymap.set("n", "<CR>", send, { buffer = composer_buf, desc = "Send from Composer" })
end

local function win_ok(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function is_chat_win(win)
  return win == transcript_win or win == composer_win
end

local function is_cheatsheet_win(win)
  return win == cheatsheet_win
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
  if buf == backdrop_buf or buf == transcript_buf or buf == composer_buf or buf == cheatsheet_buf then
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
  if buf ~= transcript_buf and buf ~= composer_buf and buf ~= backdrop_buf and buf ~= cheatsheet_buf then
    code_buf = buf
    if vim.api.nvim_win_get_config(win).relative == "" then
      code_win = win
    end
    return
  end
  local root = root_win()
  local root_buf = vim.api.nvim_win_get_buf(root)
  if root_buf ~= backdrop_buf and root_buf ~= transcript_buf and root_buf ~= composer_buf and root_buf ~= cheatsheet_buf then
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

local function ensure_cheatsheet()
  if cheatsheet_buf and vim.api.nvim_buf_is_valid(cheatsheet_buf) then
    return
  end
  cheatsheet_buf = vim.api.nvim_create_buf(false, true)
  configure_buf(cheatsheet_buf, "nai://cheatsheet")
  vim.bo[cheatsheet_buf].modifiable = true
  vim.api.nvim_buf_set_lines(cheatsheet_buf, 0, -1, false, CHEATSHEET_LINES)
  vim.bo[cheatsheet_buf].modifiable = false
  vim.keymap.set("n", "<Esc>", function()
    M.hide_cheatsheet()
  end, { buffer = cheatsheet_buf, desc = "Close command cheatsheet" })
end

local function cheatsheet_rect()
  local inner_w = 1
  for _, line in ipairs(CHEATSHEET_LINES) do
    inner_w = math.max(inner_w, vim.fn.strdisplaywidth(line))
  end
  inner_w = inner_w + 2
  local inner_h = #CHEATSHEET_LINES
  local outer_w = inner_w + BORDER
  local outer_h = inner_h + BORDER
  local tab = vim.o.showtabline == 0 and 0 or 1
  local cmd = vim.o.cmdheight
  local grid_top = tab
  local grid_h = math.max(outer_h, vim.o.lines - 1 - cmd - grid_top + 1)
  local r = grid_top + math.max(0, math.floor((grid_h - outer_h) / 2))
  local c = math.max(0, math.floor((vim.o.columns - outer_w) / 2))
  return outer_to_nvim({ r = r, c = c, w = outer_w, h = outer_h })
end

local function relayout_cheatsheet()
  if not win_ok(cheatsheet_win) then
    return
  end
  place(cheatsheet_win, cheatsheet_buf, cheatsheet_rect(), { zindex = CHEATSHEET_Z }, false)
end

function M.hide_cheatsheet()
  if not win_ok(cheatsheet_win) then
    cheatsheet_win = nil
    return
  end
  close_win(cheatsheet_win)
  cheatsheet_win = nil
end

function M.show_cheatsheet()
  style()
  ensure_cheatsheet()
  cheatsheet_win = place(cheatsheet_win, cheatsheet_buf, cheatsheet_rect(), { zindex = CHEATSHEET_Z }, true)
  apply_card(cheatsheet_win, { minimal = true })
  vim.wo[cheatsheet_win].wrap = false
  vim.wo[cheatsheet_win].cursorline = false
  vim.api.nvim_set_current_win(cheatsheet_win)
end

function M.toggle_cheatsheet()
  if win_ok(cheatsheet_win) then
    M.hide_cheatsheet()
  else
    M.show_cheatsheet()
  end
end

function M.open()
  M.show()
  if win_ok(transcript_win) then
    vim.api.nvim_set_current_win(transcript_win)
  end
end

function M.grow_current(delta)
  local cur = vim.api.nvim_get_current_win()
  if is_cheatsheet_win(cur) then
    if not visible() then
      return true
    end
    remembered_width = clamp_outer(column_outer() + delta)
    relayout()
    relayout_cheatsheet()
    return true
  end
  if not visible() then
    return false
  end
  if is_chat_win(cur) then
    remembered_width = clamp_outer(column_outer() + delta)
  else
    remembered_width = clamp_outer(column_outer() - delta)
  end
  relayout()
  relayout_cheatsheet()
  return true
end

local function scroll_transcript()
  if win_ok(transcript_win) then
    pcall(vim.api.nvim_win_set_cursor, transcript_win, { vim.api.nvim_buf_line_count(transcript_buf), 0 })
  end
end

function M.start_turn(text)
  ensure_bufs()
  vim.bo[transcript_buf].modifiable = true
  local lines = vim.api.nvim_buf_get_lines(transcript_buf, 0, -1, false)
  local empty = #lines == 1 and lines[1] == ""
  local body = vim.split(text, "\n", { plain = true })
  if #body == 0 then
    body = { "" }
  end
  local block = { "You" }
  for _, line in ipairs(body) do
    block[#block + 1] = line
  end
  block[#block + 1] = ""
  block[#block + 1] = "Agent"
  block[#block + 1] = ""
  if empty then
    vim.api.nvim_buf_set_lines(transcript_buf, 0, -1, false, block)
    stream_row = #block - 1
  else
    local count = vim.api.nvim_buf_line_count(transcript_buf)
    local appended = { "" }
    for _, line in ipairs(block) do
      appended[#appended + 1] = line
    end
    vim.api.nvim_buf_set_lines(transcript_buf, -1, -1, false, appended)
    stream_row = count + #appended - 1
  end
  agent_start = stream_row
  agent_plain = true
  vim.bo[transcript_buf].modifiable = false
  scroll_transcript()
end

function M.append_agent(chunk)
  ensure_bufs()
  if not stream_row then
    stream_row = vim.api.nvim_buf_line_count(transcript_buf) - 1
  end
  vim.bo[transcript_buf].modifiable = true
  local line = vim.api.nvim_buf_get_lines(transcript_buf, stream_row, stream_row + 1, false)[1] or ""
  local parts = vim.split(line .. chunk, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(transcript_buf, stream_row, stream_row + 1, false, parts)
  local extra = #parts - 1
  if extra > 0 and pending_start then
    pending_start = pending_start + extra
  end
  stream_row = stream_row + extra
  vim.bo[transcript_buf].modifiable = false
  scroll_transcript()
end

function M.finish_agent()
  if not agent_plain or not agent_start or not stream_row then
    return
  end
  ensure_bufs()
  if not md_ns then
    md_ns = vim.api.nvim_create_namespace("nai_agent_md")
  end
  local src_lines = vim.api.nvim_buf_get_lines(transcript_buf, agent_start, stream_row + 1, false)
  local src = table.concat(src_lines, "\n")
  local out, marks = markdown.render(src)
  vim.bo[transcript_buf].modifiable = true
  vim.api.nvim_buf_set_lines(transcript_buf, agent_start, stream_row + 1, false, out)
  local extra = #out - #src_lines
  if extra ~= 0 and pending_start then
    pending_start = pending_start + extra
  end
  stream_row = agent_start + #out - 1
  vim.api.nvim_buf_clear_namespace(transcript_buf, md_ns, agent_start, stream_row + 1)
  for _, mark in ipairs(marks) do
    if mark.line then
      pcall(vim.api.nvim_buf_set_extmark, transcript_buf, md_ns, agent_start + mark.row, 0, {
        line_hl_group = mark.hl,
        hl_eol = true,
      })
    else
      pcall(vim.api.nvim_buf_set_extmark, transcript_buf, md_ns, agent_start + mark.row, mark.col, {
        end_row = agent_start + mark.row,
        end_col = mark.end_col,
        hl_group = mark.hl,
      })
    end
  end
  vim.bo[transcript_buf].modifiable = false
  agent_plain = false
  scroll_transcript()
end

function M.set_session_slot(slot)
  session_slot = slot
  pcall(vim.cmd, "redrawtabline")
end

function M.set_pending(text)
  ensure_bufs()
  local body = vim.split(text, "\n", { plain = true })
  if #body == 0 then
    body = { "" }
  end
  local block = { "Pending" }
  for _, line in ipairs(body) do
    block[#block + 1] = line
  end
  vim.bo[transcript_buf].modifiable = true
  if pending_start then
    vim.api.nvim_buf_set_lines(transcript_buf, pending_start, pending_start + pending_len, false, block)
  else
    local count = vim.api.nvim_buf_line_count(transcript_buf)
    local lines = vim.api.nvim_buf_get_lines(transcript_buf, 0, -1, false)
    local empty = count == 1 and lines[1] == ""
    if empty then
      vim.api.nvim_buf_set_lines(transcript_buf, 0, -1, false, block)
      pending_start = 0
    else
      local prefixed = { "" }
      for _, line in ipairs(block) do
        prefixed[#prefixed + 1] = line
      end
      vim.api.nvim_buf_set_lines(transcript_buf, -1, -1, false, prefixed)
      pending_start = count + 1
    end
  end
  pending_len = #block
  vim.bo[transcript_buf].modifiable = false
  scroll_transcript()
end

function M.drop_pending()
  if not pending_start or not transcript_buf or not vim.api.nvim_buf_is_valid(transcript_buf) then
    pending_start = nil
    pending_len = nil
    return
  end
  vim.bo[transcript_buf].modifiable = true
  local start = pending_start
  if start > 0 then
    local prev = vim.api.nvim_buf_get_lines(transcript_buf, start - 1, start, false)[1]
    if prev == "" then
      start = start - 1
    end
  end
  vim.api.nvim_buf_set_lines(transcript_buf, start, pending_start + pending_len, false, {})
  vim.bo[transcript_buf].modifiable = false
  pending_start = nil
  pending_len = nil
end

function M.composer_text()
  ensure_bufs()
  local lines = vim.api.nvim_buf_get_lines(composer_buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  return text
end

function M.clear_composer()
  ensure_bufs()
  vim.api.nvim_buf_set_lines(composer_buf, 0, -1, false, { "" })
end

function M.bind_send(fn)
  on_send = fn
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
      relayout_cheatsheet()
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
