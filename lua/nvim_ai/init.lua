local backend = require("nvim_ai.backend")
local ui = require("nvim_ai.ui")

local M = {}

local pending_text

ui.setup()

local send_turn

local function finish_turn()
  ui.finish_agent()
  local queued = pending_text
  pending_text = nil
  ui.drop_pending()
  if queued and queued ~= "" then
    send_turn(queued)
  else
    ui.set_session_slot("idle")
  end
end

send_turn = function(text)
  ui.start_turn(text)
  ui.set_session_slot("in flight")
  backend.prompt(text, {
    on_chunk = function(chunk)
      ui.append_agent(chunk)
    end,
    on_done = finish_turn,
    on_error = function(msg)
      vim.notify("Chat: " .. msg, vim.log.levels.ERROR)
      finish_turn()
    end,
  })
end

function M.send()
  local text = ui.composer_text()
  if text == "" then
    return
  end
  if backend.is_inflight() then
    pending_text = text
    ui.set_pending(text)
    ui.clear_composer()
    ui.set_session_slot("pending")
    return
  end
  ui.clear_composer()
  send_turn(text)
end

function M.cancel()
  pending_text = nil
  ui.drop_pending()
  backend.cancel()
  if backend.is_inflight() then
    ui.set_session_slot("in flight")
  else
    ui.set_session_slot("idle")
  end
end

ui.bind_send(M.send)

vim.keymap.set("n", "<leader>nn", "<Nop>", { desc = "Reserved" })
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
    ui.show()
  end,
})

return M
