local backend = require("nvim_ai.backend")
local commands = require("nvim_ai.commands")
local sessions = require("nvim_ai.sessions")
local ui = require("nvim_ai.ui")

local M = {}

ui.setup()

local send_turn

local function finish_turn(sess)
  ui.finish_agent(sess.id)
  sess.inflight = false
  local queued = sess.pending_text
  sess.pending_text = nil
  ui.drop_pending(sess.id)
  if queued and queued ~= "" and not sess.cancelled then
    send_turn(sess, queued)
  else
    ui.set_session_slot("idle", sess.id)
  end
end

send_turn = function(sess, text)
  sess.cancelled = false
  sess.inflight = true
  ui.start_turn(text, sess.id)
  ui.set_session_slot("in flight", sess.id)
  backend.prompt(text, {
    on_acp = function(id)
      sess.acp_id = id
    end,
    on_chunk = function(chunk)
      ui.append_agent(chunk, sess.id)
    end,
    on_done = function()
      finish_turn(sess)
    end,
    on_error = function(msg)
      sess.acp_id = nil
      vim.notify("Chat: " .. msg, vim.log.levels.ERROR)
      finish_turn(sess)
    end,
  }, sess.acp_id)
end

function M.new_session(title)
  ui.new_session(title)
end

function M.send()
  local text = ui.composer_text()
  if text == "" then
    return
  end
  local cmd = commands.parse(text)
  if cmd and cmd.name == "nn" then
    ui.clear_composer()
    M.new_session(cmd.title)
    return
  end
  if cmd and cmd.name == "ns" then
    ui.clear_composer()
    ui.toggle_explorer()
    return
  end
  local sess = sessions.current()
  if sess.inflight then
    sess.pending_text = text
    ui.set_pending(text, sess.id)
    ui.clear_composer()
    ui.set_session_slot("pending", sess.id)
    return
  end
  ui.clear_composer()
  send_turn(sess, text)
end

function M.cancel()
  local sess = sessions.current()
  sess.cancelled = true
  sess.pending_text = nil
  ui.drop_pending(sess.id)
  backend.cancel(sess.acp_id)
  if sess.inflight then
    ui.set_session_slot("in flight", sess.id)
  else
    ui.set_session_slot("idle", sess.id)
  end
end

ui.bind_send(M.send)

vim.keymap.set("n", "<leader>nn", function()
  M.new_session()
end, { desc = "New Session" })
vim.keymap.set("n", "<leader>ns", function()
  ui.toggle_explorer()
end, { desc = "Session explorer" })
vim.keymap.set("n", "<leader>nc", "<Nop>", { desc = "Reserved" })
vim.keymap.set("n", "<leader>nq", function()
  M.cancel()
end, { desc = "Chat cancel" })
vim.keymap.set("n", "<leader>nk", function()
  ui.toggle_cheatsheet()
end, { desc = "Chat command cheatsheet" })

vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("NaiChat", { clear = true }),
  callback = function()
    sessions.ensure()
    ui.show()
  end,
})

return M
