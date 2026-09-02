local M = {}

local markdown = require("nvim_ai.markdown")
local sessions = require("nvim_ai.sessions")

local STROKE = "#7aa2f7"
local CARD_BG = "#1a1b26"
local CARD_FG = "#c0caf5"
local LINE_NR = "#3b4261"
local YOU = "#7aa2f7"
local QUEUED = "#e0af68"
local MUTED = "#565f89"
local TOPBAR_BG = "#3d59a1"
local COMPOSER_INNER = 6
local EDGE = 1
local GAP = 1
local FRAME_PAD = 2
local BORDER = 2
local SIDE_FRACTION = 0.1
local STRIP_H = 1
local CHEATSHEET_Z = 60
local EXPLORER_Z = 60
local CHEATSHEET_LINES = {
  "Command cheatsheet",
  "",
  "<leader>nn     new Session   (also /nn)",
  "<leader>ns     Session explorer   (also /ns)",
  "<leader>nc     reserved",
  "<leader>nq     cancel (drops pending)",
  "<leader>nk     this cheatsheet",
  "Enter          send (one pending while in flight)",
  "Shift-Enter    newline in Composer",
}
local FILE_EX = {
  e = true,
  edit = true,
  ex = true,
  enew = true,
  find = true,
  args = true,
  argadd = true,
  argedit = true,
  next = true,
  previous = true,
  prev = true,
  rewind = true,
  first = true,
  last = true,
  b = true,
  buffer = true,
  bnext = true,
  bprevious = true,
  bprev = true,
  bdelete = true,
  bd = true,
  bwipeout = true,
  bunload = true,
  split = true,
  vsplit = true,
  new = true,
  vnew = true,
  tabedit = true,
  tabe = true,
  tabnew = true,
  pedit = true,
}
local QUIT_EX = {
  q = true,
  quit = true,
  close = true,
  clo = true,
  hide = true,
  only = true,
  x = true,
  xit = true,
  exit = true,
  wq = true,
  wquit = true,
}

local transcript_buf
local composer_buf
local backdrop_buf
local cheatsheet_buf
local command_buf
local transcript_win
local composer_win
local command_win
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
local turn_ns
local pending_ns
local thinking_ns
local thinking
local composer_maps_buf
local wire_composer
local paint_command_strip
local apply_command_strip
local apply_card
local win_ok
local views = {}
local explorer_buf
local explorer_win
local paint_explorer
local relayout_explorer

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
  vim.api.nvim_set_hl(0, "NaiYouRail", { fg = YOU, bg = YOU })
  vim.api.nvim_set_hl(0, "NaiYouTag", { fg = YOU, bg = CARD_BG })
  vim.api.nvim_set_hl(0, "NaiQueuedRail", { fg = QUEUED, bg = QUEUED })
  vim.api.nvim_set_hl(0, "NaiQueued", { fg = QUEUED, bg = CARD_BG })
  vim.api.nvim_set_hl(0, "NaiThinking", { fg = MUTED, bg = CARD_BG, italic = true })
  vim.api.nvim_set_hl(0, "NaiWinBar", { fg = MUTED, bg = CARD_BG })
  vim.api.nvim_set_hl(0, "FloatTitle", { fg = CARD_FG, bg = CARD_BG, bold = true })
  vim.api.nvim_set_hl(0, "FloatFooter", { fg = MUTED, bg = CARD_BG })
end

local function configure_buf(buf, name)
  pcall(vim.api.nvim_buf_set_name, buf, name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
end

local function save_into(v)
  if not v then
    return
  end
  v.pending_start = pending_start
  v.pending_len = pending_len
  v.stream_row = stream_row
  v.agent_start = agent_start
  v.agent_plain = agent_plain
  v.thinking = thinking
end

local function load_from(v)
  transcript_buf = v.transcript_buf
  composer_buf = v.composer_buf
  pending_start = v.pending_start
  pending_len = v.pending_len
  stream_row = v.stream_row
  agent_start = v.agent_start
  agent_plain = v.agent_plain
  thinking = v.thinking
end

local function ensure_view(sess)
  local v = views[sess.id]
  if v and v.transcript_buf and vim.api.nvim_buf_is_valid(v.transcript_buf) then
    if not (v.composer_buf and vim.api.nvim_buf_is_valid(v.composer_buf)) then
      v.composer_buf = vim.api.nvim_create_buf(false, true)
      configure_buf(v.composer_buf, "nai://composer/" .. sess.id)
    end
    return v
  end
  v = {
    pending_start = nil,
    pending_len = nil,
    stream_row = nil,
    agent_start = nil,
    agent_plain = nil,
    thinking = nil,
  }
  v.transcript_buf = vim.api.nvim_create_buf(false, true)
  configure_buf(v.transcript_buf, "nai://transcript/" .. sess.id)
  vim.bo[v.transcript_buf].modifiable = false
  v.composer_buf = vim.api.nvim_create_buf(false, true)
  configure_buf(v.composer_buf, "nai://composer/" .. sess.id)
  views[sess.id] = v
  return v
end

local function with_view(sid, fn)
  local sess = sid and sessions.by_id(sid) or sessions.current()
  if not sess then
    return
  end
  local current = sessions.current()
  local target = ensure_view(sess)
  local prev
  if current and current.id ~= sess.id then
    prev = views[current.id]
    save_into(prev)
  end
  load_from(target)
  fn(target, sess)
  save_into(target)
  if prev then
    load_from(prev)
  end
end

local function ensure_bufs()
  local sess = sessions.ensure()
  local v = ensure_view(sess)
  load_from(v)
  wire_composer()
  if not (backdrop_buf and vim.api.nvim_buf_is_valid(backdrop_buf)) then
    backdrop_buf = vim.api.nvim_create_buf(false, true)
    configure_buf(backdrop_buf, "nai://backdrop")
  end
  if not (command_buf and vim.api.nvim_buf_is_valid(command_buf)) then
    command_buf = vim.api.nvim_create_buf(false, true)
    configure_buf(command_buf, "nai://commands")
    vim.bo[command_buf].modifiable = false
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

win_ok = function(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function apply_session_windows()
  if win_ok(transcript_win) and transcript_buf then
    vim.api.nvim_win_set_buf(transcript_win, transcript_buf)
    apply_card(transcript_win, { minimal = true, pad = true })
    vim.wo[transcript_win].breakindent = true
  end
  if win_ok(composer_win) and composer_buf then
    vim.api.nvim_win_set_buf(composer_win, composer_buf)
    apply_card(composer_win, { minimal = true, pad = true })
    wire_composer()
  end
end

local function is_cheatsheet_win(win)
  return win == cheatsheet_win
end

local function visible()
  return win_ok(transcript_win) and win_ok(composer_win)
end

local function cmd_head(line)
  local s = line:gsub("^%s+", ""):gsub("^:+", "")
  s = s:gsub("^[-%%$.0-9,'<>]+", ""):gsub("^%s+", "")
  local name = s:match("^([%a]+)")
  return name and name:lower() or ""
end

local function is_qall(name)
  return name == "qa"
    or name == "qall"
    or name == "wqa"
    or name == "wqall"
    or name == "xa"
    or name == "xall"
    or name == "quita"
    or name == "quitall"
    or name == "cq"
    or name == "cquit"
end

local function block_ex(line)
  local name = cmd_head(line)
  if name == "" or is_qall(name) then
    return false
  end
  return FILE_EX[name] == true or QUIT_EX[name] == true
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

apply_card = function(win, opts)
  vim.wo[win].winhighlight =
    "Normal:NaiCard,EndOfBuffer:NaiCard,FloatBorder:NaiStroke,WinBorder:NaiStroke,LineNr:NaiLineNr,CursorLineNr:NaiLineNr,SignColumn:NaiCard,FoldColumn:NaiCard,StatusColumn:NaiCard,WinBar:NaiCard,WinBarNC:NaiCard,FloatTitle:NaiWinBar,FloatFooter:NaiWinBar"
  vim.wo[win].wrap = true
  if opts.minimal then
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].foldcolumn = "0"
    vim.wo[win].statusline = " "
  end
  if opts.pad then
    vim.wo[win].statuscolumn = "  "
    vim.wo[win].winbar = "%#NaiCard# "
  end
end

local TRANSCRIPT_FLOAT = {
  style = "minimal",
  title = " Chat ",
  title_pos = "left",
}

local COMPOSER_FLOAT = {
  style = "minimal",
  title = " Build ",
  title_pos = "left",
}

local COMMAND_FLOAT = {
  style = "minimal",
  border = "none",
  focusable = false,
  zindex = 55,
}

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
  local cmd = vim.o.cmdheight
  local tab = vim.o.showtabline == 0 and 0 or 1
  local status = vim.o.laststatus == 0 and 0 or 1
  -- Header, pad, Chat, Build, same pad, full-width footer.
  local grid_top = tab + FRAME_PAD
  local grid_bottom = vim.o.lines - 1 - cmd - status
  local side = math.max(0, math.floor(vim.o.columns * SIDE_FRACTION))
  local chat_w = math.max(8, vim.o.columns - side * 2)
  local grid_left = side

  local composer_h = COMPOSER_INNER + BORDER
  local strip_r = grid_bottom - STRIP_H + 1
  local composer_r = strip_r - FRAME_PAD - composer_h
  local transcript_h = composer_r - GAP - grid_top
  if transcript_h < BORDER + 1 then
    composer_h = math.max(BORDER + 1, math.floor((grid_bottom - grid_top + 1) / 3))
    composer_r = strip_r - FRAME_PAD - composer_h
    transcript_h = math.max(BORDER + 1, composer_r - GAP - grid_top)
  end

  return {
    transcript = outer_to_nvim({ r = grid_top, c = grid_left, w = chat_w, h = transcript_h }),
    composer = outer_to_nvim({
      r = composer_r,
      c = grid_left,
      w = chat_w,
      h = composer_h,
    }),
    command = { row = strip_r, col = 0, width = vim.o.columns, height = STRIP_H },
  }
end

local function float_opts(rect, extra)
  local opts = {
    relative = "editor",
    row = rect.row,
    col = rect.col,
    width = rect.width,
    height = rect.height,
    border = "single",
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
    local cfg = {
      relative = opts.relative,
      row = opts.row,
      col = opts.col,
      width = opts.width,
      height = opts.height,
      border = opts.border,
      zindex = opts.zindex,
    }
    if opts.title then
      cfg.title = opts.title
      cfg.title_pos = opts.title_pos or "left"
    end
    if opts.footer then
      cfg.footer = opts.footer
      cfg.footer_pos = opts.footer_pos or "left"
    end
    vim.api.nvim_win_set_config(win, cfg)
    return win
  end
  return vim.api.nvim_open_win(buf, enter, opts)
end

local function relayout()
  if not visible() then
    return
  end
  local rects = layout_rects()
  place(transcript_win, transcript_buf, rects.transcript, TRANSCRIPT_FLOAT, false)
  command_win = place(command_win, command_buf, rects.command, COMMAND_FLOAT, false)
  apply_command_strip(command_win)
  paint_command_strip()
  place(composer_win, composer_buf, rects.composer, COMPOSER_FLOAT, false)
end

local function focus_composer()
  if not win_ok(composer_win) then
    return
  end
  vim.api.nvim_set_current_win(composer_win)
  vim.schedule(function()
    if win_ok(composer_win) then
      vim.api.nvim_set_current_win(composer_win)
      vim.cmd("startinsert")
    end
  end)
end

local function bounce_backdrop()
  if layout_lock then
    return
  end
  local cur = vim.api.nvim_get_current_win()
  if not win_ok(cur) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(cur)
  if (buf == backdrop_buf or buf == command_buf) and win_ok(composer_win) then
    vim.api.nvim_set_current_win(composer_win)
  end
end

local function first_file_arg()
  for _, name in ipairs(vim.fn.argv()) do
    if name ~= "" then
      local path = vim.fn.fnamemodify(name, ":p")
      if vim.fn.isdirectory(path) == 0 then
        return path
      end
    end
  end
end

local function capture_waiting()
  local path = first_file_arg()
  if not path then
    code_buf = nil
    return
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" and vim.fn.fnamemodify(name, ":p") == path then
      code_buf = buf
      return
    end
  end
end

function M.tabline()
  local sess = sessions.current()
  local title = sess and sess.title or "Session"
  local slot = sess and sess.slot or session_slot
  return "%#NaiTopBar#%=" .. "%#TabLineFill# " .. title .. " · " .. slot .. " "
end

local function mode_label()
  local m = vim.fn.mode()
  if m == "i" or m == "ic" or m == "ix" then
    return "INSERT"
  end
  if m == "c" then
    return "COMMAND"
  end
  if m == "v" or m == "V" or m == "\22" then
    return "VISUAL"
  end
  return "NORMAL"
end

local function command_line()
  return " "
    .. mode_label()
    .. "   Enter send   Shift-Enter newline   <leader>nn new Session   <leader>ns explorer   <leader>nq cancel   <leader>nk cheatsheet"
end

paint_command_strip = function()
  if not command_buf or not vim.api.nvim_buf_is_valid(command_buf) then
    return
  end
  local text = command_line()
  local width = vim.o.columns
  local pad = width - vim.fn.strdisplaywidth(text)
  if pad > 0 then
    text = text .. string.rep(" ", pad)
  elseif pad < 0 then
    text = vim.fn.strcharpart(text, 0, width)
  end
  vim.bo[command_buf].modifiable = true
  vim.api.nvim_buf_set_lines(command_buf, 0, -1, false, { text })
  vim.bo[command_buf].modifiable = false
end

apply_command_strip = function(win)
  vim.wo[win].winhighlight = "Normal:NaiTopBar,EndOfBuffer:NaiTopBar"
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].cursorline = false
  vim.wo[win].wrap = false
  vim.wo[win].winblend = 0
  pcall(function()
    vim.wo[win].winborder = "none"
  end)
end

function M.show()
  style()
  ensure_bufs()
  capture_waiting()
  if visible() then
    relayout()
    focus_composer()
    return
  end
  layout_lock = true
  local ok, err = pcall(function()
    if saved_laststatus == nil then
      saved_laststatus = vim.o.laststatus
    end
    if saved_ruler == nil then
      saved_ruler = vim.o.ruler
    end
    vim.o.showtabline = 2
    vim.o.laststatus = 0
    vim.o.ruler = false
    vim.o.showmode = false
    vim.o.tabline = "%!v:lua.require('nvim_ai.ui').tabline()"

    local root = root_win()
    vim.api.nvim_win_set_buf(root, backdrop_buf)
    apply_backdrop(root)

    local rects = layout_rects()
    transcript_win = place(transcript_win, transcript_buf, rects.transcript, TRANSCRIPT_FLOAT, false)
    apply_card(transcript_win, { minimal = true, pad = true })
    vim.wo[transcript_win].breakindent = true
    command_win = place(command_win, command_buf, rects.command, COMMAND_FLOAT, false)
    apply_command_strip(command_win)
    paint_command_strip()
    composer_win = place(composer_win, composer_buf, rects.composer, COMPOSER_FLOAT, false)
    apply_card(composer_win, { minimal = true, pad = true })
    focus_composer()
  end)
  layout_lock = false
  if not ok then
    error(err)
  end
end

function M.hide() end

function M.toggle() end

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

local EXPLORER_HEAD = {
  "Session explorer",
  "n new   Enter open   d drop   Esc close",
  "",
}

local function clip(s, n)
  s = s or ""
  if vim.fn.strdisplaywidth(s) <= n then
    return s
  end
  return vim.fn.strcharpart(s, 0, math.max(1, n - 1)) .. "…"
end

local function explorer_lines()
  local lines = {}
  for _, h in ipairs(EXPLORER_HEAD) do
    lines[#lines + 1] = h
  end
  local current = sessions.current()
  for _, s in ipairs(sessions.list()) do
    local mark = (current and s.id == current.id) and ">" or " "
    local preview = s.preview
    if preview == "" then
      preview = "(empty)"
    end
    lines[#lines + 1] = string.format(
      "%s %d  %-18s  %-9s  %s",
      mark,
      s.n,
      clip(s.title, 18),
      s.slot,
      clip(preview, 40)
    )
  end
  return lines
end

local function explorer_session_at_cursor()
  if not win_ok(explorer_win) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(explorer_win)[1]
  local idx = row - #EXPLORER_HEAD
  return sessions.list()[idx]
end

paint_explorer = function()
  if not explorer_buf or not vim.api.nvim_buf_is_valid(explorer_buf) then
    return
  end
  local lines = explorer_lines()
  vim.bo[explorer_buf].modifiable = true
  vim.api.nvim_buf_set_lines(explorer_buf, 0, -1, false, lines)
  vim.bo[explorer_buf].modifiable = false
end

local function explorer_rect()
  local lines = explorer_lines()
  local inner_w = 48
  for _, line in ipairs(lines) do
    inner_w = math.max(inner_w, vim.fn.strdisplaywidth(line))
  end
  inner_w = inner_w + 2
  local inner_h = math.max(#lines, #EXPLORER_HEAD + 1)
  local outer_w = math.min(vim.o.columns - 4, inner_w + BORDER)
  local outer_h = math.min(vim.o.lines - 4, inner_h + BORDER)
  local tab = vim.o.showtabline == 0 and 0 or 1
  local cmd = vim.o.cmdheight
  local grid_top = tab
  local grid_h = math.max(outer_h, vim.o.lines - 1 - cmd - grid_top + 1)
  local r = grid_top + math.max(0, math.floor((grid_h - outer_h) / 2))
  local c = math.max(0, math.floor((vim.o.columns - outer_w) / 2))
  return outer_to_nvim({ r = r, c = c, w = outer_w, h = outer_h })
end

relayout_explorer = function()
  if not win_ok(explorer_win) then
    return
  end
  place(explorer_win, explorer_buf, explorer_rect(), { zindex = EXPLORER_Z }, false)
end

local function ensure_explorer()
  if explorer_buf and vim.api.nvim_buf_is_valid(explorer_buf) then
    paint_explorer()
    return
  end
  explorer_buf = vim.api.nvim_create_buf(false, true)
  configure_buf(explorer_buf, "nai://sessions")
  paint_explorer()
  vim.keymap.set("n", "<Esc>", function()
    M.hide_explorer()
  end, { buffer = explorer_buf, desc = "Close Session explorer" })
  vim.keymap.set("n", "<CR>", function()
    local s = explorer_session_at_cursor()
    if s then
      M.use_session(s.id)
      M.hide_explorer()
    end
  end, { buffer = explorer_buf, desc = "Open Session" })
  vim.keymap.set("n", "n", function()
    M.new_session()
    M.hide_explorer()
  end, { buffer = explorer_buf, desc = "New Session" })
  vim.keymap.set("n", "d", function()
    local s = explorer_session_at_cursor()
    if not s then
      return
    end
    M.drop_session(s.id)
  end, { buffer = explorer_buf, desc = "Drop Session" })
end

function M.hide_explorer()
  if not win_ok(explorer_win) then
    explorer_win = nil
    return
  end
  close_win(explorer_win)
  explorer_win = nil
  focus_composer()
end

function M.show_explorer()
  style()
  sessions.ensure()
  ensure_explorer()
  paint_explorer()
  explorer_win = place(explorer_win, explorer_buf, explorer_rect(), { zindex = EXPLORER_Z }, true)
  apply_card(explorer_win, { minimal = true })
  vim.wo[explorer_win].wrap = false
  vim.wo[explorer_win].cursorline = true
  vim.api.nvim_set_current_win(explorer_win)
  local current = sessions.current()
  local row = #EXPLORER_HEAD + 1
  if current then
    for i, s in ipairs(sessions.list()) do
      if s.id == current.id then
        row = #EXPLORER_HEAD + i
        break
      end
    end
  end
  pcall(vim.api.nvim_win_set_cursor, explorer_win, { row, 0 })
end

function M.toggle_explorer()
  if win_ok(explorer_win) then
    M.hide_explorer()
  else
    M.hide_cheatsheet()
    M.show_explorer()
  end
end

function M.use_session(id)
  local current = sessions.current()
  if current then
    save_into(views[current.id])
  end
  local sess = sessions.select(id)
  if not sess then
    return
  end
  ensure_bufs()
  session_slot = sess.slot
  apply_session_windows()
  pcall(vim.cmd, "redrawtabline")
  paint_explorer()
  focus_composer()
end

function M.new_session(title)
  local current = sessions.current()
  if current then
    save_into(views[current.id])
  end
  sessions.create(title)
  ensure_bufs()
  session_slot = "idle"
  if visible() then
    apply_session_windows()
  else
    M.show()
  end
  pcall(vim.cmd, "redrawtabline")
  paint_explorer()
  focus_composer()
end

function M.drop_session(id)
  local target = sessions.by_id(id)
  if target and target.inflight then
    return false
  end
  local current = sessions.current()
  if current then
    save_into(views[current.id])
  end
  if not sessions.drop(id) then
    return false
  end
  local v = views[id]
  if v then
    views[id] = nil
  end
  ensure_bufs()
  session_slot = sessions.current().slot
  if visible() then
    apply_session_windows()
  end
  pcall(vim.cmd, "redrawtabline")
  if win_ok(explorer_win) then
    paint_explorer()
    relayout_explorer()
    local row = math.min(#EXPLORER_HEAD + #sessions.list(), vim.api.nvim_buf_line_count(explorer_buf))
    pcall(vim.api.nvim_win_set_cursor, explorer_win, { math.max(#EXPLORER_HEAD + 1, row), 0 })
  end
  return true
end

function M.open()
  M.show()
  if win_ok(transcript_win) then
    vim.api.nvim_set_current_win(transcript_win)
  end
end

function M.grow_current(_)
  local cur = vim.api.nvim_get_current_win()
  return visible() or is_cheatsheet_win(cur) or cur == explorer_win
end

local function scroll_transcript()
  if not win_ok(transcript_win) or not transcript_buf then
    return
  end
  if vim.api.nvim_win_get_buf(transcript_win) ~= transcript_buf then
    return
  end
  pcall(vim.api.nvim_win_set_cursor, transcript_win, { vim.api.nvim_buf_line_count(transcript_buf), 0 })
end

local function ensure_turn_ns()
  if not turn_ns then
    turn_ns = vim.api.nvim_create_namespace("nai_turn")
  end
  if not pending_ns then
    pending_ns = vim.api.nvim_create_namespace("nai_pending")
  end
  if not thinking_ns then
    thinking_ns = vim.api.nvim_create_namespace("nai_thinking")
  end
end

local function mark_span(ns, row, line, hl)
  if line == "" then
    return
  end
  vim.api.nvim_buf_set_extmark(transcript_buf, ns, row, 0, {
    end_row = row,
    end_col = #line,
    hl_group = hl,
  })
end

local function body_wrap_width(tag)
  local win_w = 24
  if win_ok(transcript_win) then
    win_w = vim.api.nvim_win_get_width(transcript_win)
  end
  -- statuscolumn + rail + gap + tag, minus one so wrap does not re-break the line
  return math.max(8, win_w - 2 - 1 - 2 - vim.fn.strdisplaywidth(tag) - 1)
end

local function take_chars(s, n)
  return vim.fn.strcharpart(s, 0, n)
end

local function drop_chars(s, n)
  return vim.fn.strcharpart(s, n)
end

local function wrap_to_width(text, width)
  width = math.max(8, width)
  local out = {}
  local function emit_hard(word)
    local rest = word
    while vim.fn.strdisplaywidth(rest) > width do
      local n = vim.fn.strcharlen(rest)
      local take = 1
      for i = 1, n do
        if vim.fn.strdisplaywidth(take_chars(rest, i)) > width then
          break
        end
        take = i
      end
      out[#out + 1] = take_chars(rest, take)
      rest = drop_chars(rest, take)
    end
    return rest
  end
  for _, para in ipairs(vim.split(text, "\n", { plain = true })) do
    if para == "" then
      out[#out + 1] = ""
    else
      local line = ""
      for word in para:gmatch("%S+") do
        local trial = line == "" and word or (line .. " " .. word)
        if vim.fn.strdisplaywidth(trial) <= width then
          line = trial
        else
          if line ~= "" then
            out[#out + 1] = line
          end
          if vim.fn.strdisplaywidth(word) > width then
            line = emit_hard(word)
          else
            line = word
          end
        end
      end
      if line ~= "" then
        out[#out + 1] = line
      end
    end
  end
  if #out == 0 then
    out = { "" }
  end
  return out
end

-- Thick left rail + label. No 4-sided box: Neovim can't size those like CSS.
local function paint_block(ns, start, len, rail_hl, tag, tag_hl, body_hl)
  local lines = vim.api.nvim_buf_get_lines(transcript_buf, start, start + len, false)
  local pad = string.rep(" ", #tag)
  for i, line in ipairs(lines) do
    local row = start + i - 1
    local label = i == 1 and { tag, tag_hl } or { pad, "NaiCard" }
    vim.api.nvim_buf_set_extmark(transcript_buf, ns, row, 0, {
      virt_text = {
        { " ", rail_hl },
        { "  ", "NaiCard" },
        label,
      },
      virt_text_pos = "inline",
      right_gravity = false,
    })
    if body_hl then
      mark_span(ns, row, line, body_hl)
    end
  end
end

local function paint_you(start, len)
  ensure_turn_ns()
  paint_block(turn_ns, start, len, "NaiYouRail", "YOU  ", "NaiYouTag")
end

local function paint_queued(start, len)
  ensure_turn_ns()
  vim.api.nvim_buf_clear_namespace(transcript_buf, pending_ns, 0, -1)
  paint_block(pending_ns, start, len, "NaiQueuedRail", "QUEUED  ", "NaiQueued", "NaiQueued")
end

local function paint_thinking(row)
  ensure_turn_ns()
  local line = vim.api.nvim_buf_get_lines(transcript_buf, row, row + 1, false)[1] or ""
  mark_span(thinking_ns, row, line, "NaiThinking")
end

local function clear_thinking()
  thinking = false
  if thinking_ns and transcript_buf and vim.api.nvim_buf_is_valid(transcript_buf) then
    vim.api.nvim_buf_clear_namespace(transcript_buf, thinking_ns, 0, -1)
  end
end

function M.start_turn(text, sid)
  with_view(sid, function(_, sess)
    if sess.preview == "" then
      sessions.set_preview(sess.id, text)
    end
    vim.bo[transcript_buf].modifiable = true
    local lines = vim.api.nvim_buf_get_lines(transcript_buf, 0, -1, false)
    local empty = #lines == 1 and lines[1] == ""
    local you_tag = "YOU  "
    local body = wrap_to_width(text, body_wrap_width(you_tag))
    local block = {}
    for _, line in ipairs(body) do
      block[#block + 1] = line
    end
    block[#block + 1] = ""
    block[#block + 1] = "thinking..."
    local you_start
    if empty then
      vim.api.nvim_buf_set_lines(transcript_buf, 0, -1, false, block)
      you_start = 0
      stream_row = #block - 1
    else
      local count = vim.api.nvim_buf_line_count(transcript_buf)
      local appended = { "" }
      for _, line in ipairs(block) do
        appended[#appended + 1] = line
      end
      vim.api.nvim_buf_set_lines(transcript_buf, -1, -1, false, appended)
      you_start = count + 1
      stream_row = count + #appended - 1
    end
    agent_start = stream_row
    agent_plain = true
    thinking = true
    paint_you(you_start, #body)
    paint_thinking(stream_row)
    vim.bo[transcript_buf].modifiable = false
    scroll_transcript()
  end)
end

function M.append_agent(chunk, sid)
  with_view(sid, function()
    if not stream_row then
      stream_row = vim.api.nvim_buf_line_count(transcript_buf) - 1
    end
    vim.bo[transcript_buf].modifiable = true
    local parts
    if thinking then
      clear_thinking()
      parts = vim.split(chunk, "\n", { plain = true })
      if #parts == 0 then
        parts = { "" }
      end
      vim.api.nvim_buf_set_lines(transcript_buf, stream_row, stream_row + 1, false, parts)
    else
      local line = vim.api.nvim_buf_get_lines(transcript_buf, stream_row, stream_row + 1, false)[1] or ""
      parts = vim.split(line .. chunk, "\n", { plain = true })
      vim.api.nvim_buf_set_lines(transcript_buf, stream_row, stream_row + 1, false, parts)
    end
    local extra = #parts - 1
    if extra > 0 and pending_start then
      pending_start = pending_start + extra
    end
    stream_row = stream_row + extra
    vim.bo[transcript_buf].modifiable = false
    scroll_transcript()
  end)
end

function M.finish_agent(sid)
  with_view(sid, function()
    if not agent_plain or not agent_start or not stream_row then
      return
    end
    vim.bo[transcript_buf].modifiable = true
    if thinking then
      vim.api.nvim_buf_set_lines(transcript_buf, stream_row, stream_row + 1, false, { "" })
      clear_thinking()
    end
    if not md_ns then
      md_ns = vim.api.nvim_create_namespace("nai_agent_md")
    end
    local src_lines = vim.api.nvim_buf_get_lines(transcript_buf, agent_start, stream_row + 1, false)
    local src = table.concat(src_lines, "\n")
    if src == "" then
      vim.bo[transcript_buf].modifiable = false
      agent_plain = false
      return
    end
    local out, marks = markdown.render(src)
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
  end)
end

function M.set_session_slot(slot, sid)
  local sess = sid and sessions.by_id(sid) or sessions.current()
  if sess then
    sessions.set_slot(sess.id, slot)
  end
  if not sid or (sessions.current() and sess and sess.id == sessions.current().id) then
    session_slot = slot
    pcall(vim.cmd, "redrawtabline")
  end
  if paint_explorer then
    paint_explorer()
  end
end

function M.set_pending(text, sid)
  with_view(sid, function()
    local queued_tag = "QUEUED  "
    local body = wrap_to_width(text, body_wrap_width(queued_tag))
    local block = {}
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
    paint_queued(pending_start, pending_len)
    vim.bo[transcript_buf].modifiable = false
    scroll_transcript()
  end)
end

function M.drop_pending(sid)
  with_view(sid, function()
    if not pending_start or not transcript_buf or not vim.api.nvim_buf_is_valid(transcript_buf) then
      pending_start = nil
      pending_len = nil
      return
    end
    ensure_turn_ns()
    vim.api.nvim_buf_clear_namespace(transcript_buf, pending_ns, 0, -1)
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
  end)
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
  vim.o.laststatus = 0
  vim.o.showmode = false
  vim.o.tabline = "%!v:lua.require('nvim_ai.ui').tabline()"
  vim.o.winborder = "single"
  vim.o.equalalways = false
  local group = vim.api.nvim_create_augroup("NaiChatLayout", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = bounce_backdrop,
  })
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = paint_command_strip,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if visible() then
        relayout()
      end
      relayout_cheatsheet()
      relayout_explorer()
    end,
  })
  vim.keymap.set("c", "<CR>", function()
    if vim.fn.getcmdtype() == ":" and visible() and block_ex(vim.fn.getcmdline()) then
      return "<C-u><Esc>"
    end
    return "<CR>"
  end, { expr = true, desc = "Block file Ex and :q in Chat-only" })
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
