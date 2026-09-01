local backend = require("nvim_ai.backend")
local ui = require("nvim_ai.ui")

local M = {}

ui.setup()

vim.keymap.set("n", "<leader>nn", function()
  ui.toggle()
end, { desc = "Chat hide/show" })

vim.keymap.set("n", "<leader>nc", function() end, { desc = "Chat cancel" })

vim.keymap.set("n", "<leader>nk", function() end, { desc = "Chat command cheatsheet" })

vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("NaiChat", { clear = true }),
  callback = function()
    ui.show()
  end,
})

function M.nai(args)
  if backend.is_inflight() then
    vim.notify("Nai: a turn is already in flight", vim.log.levels.ERROR)
    return
  end
  local text = args
  if not text or text == "" then
    text = vim.fn.input("Nai: ")
  end
  if text == "" then
    return
  end
  ui.open()
  ui.start_turn(text)
  backend.prompt(text, {
    on_chunk = function(chunk)
      ui.append_agent(chunk)
    end,
    on_done = function() end,
    on_error = function(msg)
      vim.notify("Nai: " .. msg, vim.log.levels.ERROR)
    end,
  })
end

function M.cancel()
  backend.cancel()
end

vim.api.nvim_create_user_command("Nai", function(opts)
  M.nai(opts.args)
end, { nargs = "*" })

vim.api.nvim_create_user_command("NaiCancel", function()
  M.cancel()
end, {})

return M
