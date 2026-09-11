local sessions = require("nvim_ai.sessions")
local commands = require("nvim_ai.commands")

local function eq(a, b, msg)
  if type(a) == "table" or type(b) == "table" then
    if not vim.deep_equal(a, b) then
      error((msg or "eq") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b), 2)
    end
    return
  end
  if a ~= b then
    error((msg or "eq") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b), 2)
  end
end

-- Launch starts with one Session; /nn adds another and hops to it.
local store = sessions.new()
local first = store.ensure()
eq(first.title, "Session 1")
eq(store.current().id, first.id)
eq(#store.list(), 1)

local second = store.create()
eq(second.title, "Session 2")
eq(store.current().id, second.id)
eq(#store.list(), 2)

store.select(first.id)
eq(store.current().id, first.id)

store.set_preview(first.id, "How should first launch look?")
eq(store.by_id(first.id).preview, "How should first launch look?")

-- Named /nn uses the rest of the line as the title.
local named = store.create("fix the footer")
eq(named.title, "fix the footer")
eq(store.current().id, named.id)

-- Drop hops to a remaining Session; the last one stays.
eq(store.drop(first.id), true)
eq(#store.list(), 2)
eq(store.current().id, named.id)
eq(store.drop(second.id), true)
eq(#store.list(), 1)
eq(store.drop(named.id), false)

eq(commands.parse("/nn"), { name = "nn" })
eq(commands.parse("/nn fix the footer"), { name = "nn", title = "fix the footer" })
eq(commands.parse("/ns"), { name = "ns" })
eq(commands.parse("hello"), nil)
eq(commands.parse("/nnish"), nil)

print("sessions_spec ok")
