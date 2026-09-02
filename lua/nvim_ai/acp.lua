local M = {}

local job_id = nil
local next_rpc_id = 0
local pending = {}
local stdout_rest = ""
local flights = {}
local boots = {}

local function usable(name)
  if vim.fn.executable(name) ~= 1 then
    return false
  end
  return not vim.fn.exepath(name):match("%.ps1$")
end

function M.find_agent()
  for _, name in ipairs({ "agent", "cursor-agent", "cursor-agent.cmd" }) do
    if usable(name) then
      return name
    end
  end
  return nil
end

local function write(msg)
  if not job_id then
    return
  end
  vim.fn.chansend(job_id, vim.json.encode(msg) .. "\n")
end

local function request(method, params, on_result)
  next_rpc_id = next_rpc_id + 1
  local id = next_rpc_id
  pending[id] = on_result
  write({ jsonrpc = "2.0", id = id, method = method, params = params or {} })
  return id
end

local function finish_flight(flight, kind, msg)
  if not flight or flight.done then
    return
  end
  flight.done = true
  if flight.acp_id then
    flights[flight.acp_id] = nil
  end
  for i, boot in ipairs(boots) do
    if boot == flight then
      table.remove(boots, i)
      break
    end
  end
  local cbs = flight.cbs
  if not cbs then
    return
  end
  vim.schedule(function()
    if kind == "error" and cbs.on_error then
      cbs.on_error(msg)
    elseif cbs.on_done then
      cbs.on_done()
    end
  end)
end

local function flight_for(acp_id)
  if acp_id and flights[acp_id] then
    return flights[acp_id]
  end
  if #boots == 1 then
    return boots[1]
  end
  local only
  for _, f in pairs(flights) do
    if only then
      return nil
    end
    only = f
  end
  return only
end

local function handle_update(params)
  if not params or not params.update then
    return
  end
  local update = params.update
  if update.sessionUpdate ~= "agent_message_chunk" then
    return
  end
  local content = update.content
  local text = content and content.text
  if type(text) ~= "string" or text == "" then
    return
  end
  local flight = flight_for(params.sessionId)
  if not flight or not flight.cbs or not flight.cbs.on_chunk then
    return
  end
  vim.schedule(function()
    if flight.cbs and flight.cbs.on_chunk then
      flight.cbs.on_chunk(text)
    end
  end)
end

local function handle_message(msg)
  if msg.method == "session/update" then
    handle_update(msg.params)
    return
  end
  if msg.id ~= nil and (msg.result ~= nil or msg.error ~= nil) then
    local cb = pending[msg.id]
    pending[msg.id] = nil
    if not cb then
      return
    end
    if msg.error then
      cb(msg.error.message or "ACP error", nil)
    else
      cb(nil, msg.result)
    end
    return
  end
end

local function on_stdout(_, data)
  if type(data) ~= "table" then
    return
  end
  for i, piece in ipairs(data) do
    if i == 1 then
      piece = stdout_rest .. piece
    end
    if i == #data then
      stdout_rest = piece
    elseif piece ~= "" then
      local ok, msg = pcall(vim.json.decode, piece)
      if ok and type(msg) == "table" then
        handle_message(msg)
      end
    end
  end
end

local function kill_job()
  if job_id then
    pcall(vim.fn.jobstop, job_id)
  end
  job_id = nil
  pending = {}
  stdout_rest = ""
  next_rpc_id = 0
end

local function on_exit()
  local was_job = job_id
  job_id = nil
  pending = {}
  stdout_rest = ""
  if not was_job then
    return
  end
  local dying = {}
  for _, f in pairs(flights) do
    dying[#dying + 1] = f
  end
  for _, f in ipairs(boots) do
    dying[#dying + 1] = f
  end
  flights = {}
  boots = {}
  for _, f in ipairs(dying) do
    finish_flight(f, "error", "Cursor Agent exited")
  end
end

local function spawn()
  local cmd = M.find_agent()
  if not cmd then
    return "Cursor Agent is not on PATH (agent / cursor-agent)"
  end
  stdout_rest = ""
  pending = {}
  next_rpc_id = 0
  job_id = vim.fn.jobstart({ cmd, "acp" }, {
    cwd = vim.fn.getcwd(),
    stdin = "pipe",
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = on_stdout,
    on_exit = function()
      on_exit()
    end,
  })
  if not job_id or job_id <= 0 then
    job_id = nil
    return "failed to spawn Cursor Agent (" .. cmd .. " acp)"
  end
  return nil
end

local function open_session(on_ready)
  request("session/new", {
    cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":p"),
    mcpServers = {},
  }, function(session_err, session)
    if session_err or not session or not session.sessionId then
      on_ready(session_err or "session/new failed", nil)
      return
    end
    on_ready(nil, session.sessionId)
  end)
end

local function handshake(on_ready)
  request("initialize", {
    protocolVersion = 1,
    clientCapabilities = {
      fs = { readTextFile = false, writeTextFile = false },
      terminal = false,
    },
    clientInfo = { name = "nvim-ai", version = "0.1.0" },
  }, function(err, result)
    if err or not result then
      kill_job()
      on_ready(err or "initialize failed")
      return
    end
    if result.protocolVersion ~= 1 then
      kill_job()
      on_ready("unsupported ACP protocolVersion")
      return
    end
    local need_login = false
    for _, method in ipairs(result.authMethods or {}) do
      if method.id == "cursor_login" then
        need_login = true
        break
      end
    end
    if not need_login then
      on_ready(nil)
      return
    end
    request("authenticate", { methodId = "cursor_login" }, function(auth_err)
      if auth_err then
        kill_job()
        on_ready(auth_err)
        return
      end
      on_ready(nil)
    end)
  end)
end

local function ensure_connection(on_ready)
  if job_id then
    on_ready(nil)
    return
  end
  kill_job()
  local spawn_err = spawn()
  if spawn_err then
    on_ready(spawn_err)
    return
  end
  handshake(on_ready)
end

function M.is_inflight(acp_id)
  if acp_id then
    return flights[acp_id] ~= nil
  end
  if next(flights) ~= nil then
    return true
  end
  return #boots > 0
end

function M.prompt(text, callbacks, acp_id)
  if acp_id and flights[acp_id] then
    return false
  end
  local flight = { cbs = callbacks, cancelled = false, acp_id = acp_id, done = false }
  boots[#boots + 1] = flight
  ensure_connection(function(err)
    if err then
      finish_flight(flight, "error", err)
      return
    end
    local function go(id)
      flight.acp_id = id
      flights[id] = flight
      for i, boot in ipairs(boots) do
        if boot == flight then
          table.remove(boots, i)
          break
        end
      end
      if callbacks.on_acp then
        callbacks.on_acp(id)
      end
      if flight.cancelled then
        finish_flight(flight, "done")
        return
      end
      request("session/prompt", {
        sessionId = id,
        prompt = { { type = "text", text = text } },
      }, function(prompt_err)
        if prompt_err then
          finish_flight(flight, "error", prompt_err)
          return
        end
        finish_flight(flight, "done")
      end)
    end
    if acp_id then
      go(acp_id)
      return
    end
    open_session(function(session_err, id)
      if session_err then
        finish_flight(flight, "error", session_err)
        return
      end
      go(id)
    end)
  end)
  return true
end

function M.cancel(acp_id)
  local flight = flight_for(acp_id)
  if not flight then
    return
  end
  flight.cancelled = true
  if flight.acp_id then
    write({
      jsonrpc = "2.0",
      method = "session/cancel",
      params = { sessionId = flight.acp_id },
    })
  end
end

return M
