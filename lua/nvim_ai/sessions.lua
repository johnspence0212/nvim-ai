local M = {}

local function new_store()
  local list = {}
  local current
  local seq = 0

  local store = {}

  local function by_id(id)
    for _, s in ipairs(list) do
      if s.id == id then
        return s
      end
    end
  end

  local function make(title)
    seq = seq + 1
    return {
      id = tostring(seq),
      n = seq,
      title = title or ("Session " .. seq),
      preview = "",
      slot = "idle",
      acp_id = nil,
      inflight = false,
      pending_text = nil,
    }
  end

  function store.list()
    return list
  end

  function store.by_id(id)
    return by_id(id)
  end

  function store.current()
    store.ensure()
    return by_id(current) or list[1]
  end

  function store.ensure()
    if #list == 0 then
      local s = make()
      list[1] = s
      current = s.id
    end
    return by_id(current)
  end

  function store.create(title)
    store.ensure()
    local s = make(title)
    list[#list + 1] = s
    current = s.id
    return s
  end

  function store.select(id)
    local s = by_id(id)
    if not s then
      return nil
    end
    current = id
    return s
  end

  function store.drop(id)
    if #list <= 1 then
      return false
    end
    local idx
    for i, s in ipairs(list) do
      if s.id == id then
        idx = i
        break
      end
    end
    if not idx then
      return false
    end
    table.remove(list, idx)
    if current == id then
      local next = list[idx] or list[idx - 1] or list[1]
      current = next.id
    end
    return true
  end

  function store.set_preview(id, text)
    local s = by_id(id)
    if not s then
      return
    end
    local line = (text or ""):gsub("^%s+", ""):gsub("\n.*", "")
    s.preview = line
  end

  function store.set_slot(id, slot)
    local s = by_id(id)
    if s then
      s.slot = slot
    end
  end

  return store
end

function M.new()
  return new_store()
end

local default = new_store()

function M.list()
  return default.list()
end

function M.by_id(id)
  return default.by_id(id)
end

function M.current()
  return default.current()
end

function M.ensure()
  return default.ensure()
end

function M.create(title)
  return default.create(title)
end

function M.select(id)
  return default.select(id)
end

function M.drop(id)
  return default.drop(id)
end

function M.set_preview(id, text)
  return default.set_preview(id, text)
end

function M.set_slot(id, slot)
  return default.set_slot(id, slot)
end

return M
