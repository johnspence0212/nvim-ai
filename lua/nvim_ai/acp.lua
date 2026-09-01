local M = {}

local job_id = nil
local session_id = nil
local next_rpc_id = 0
local pending = {}
local stdout_rest = ""
local inflight = false
local cbs = nil

local cancelled = false

local function notify_error(msg)
  local current = cbs
  cbs = nil
  if current and current.on_error then
    vim.schedule(function()
      inflight = false
      current.on_error(msg)
    end)
  else
    inflight = false
  end
end

local function notify_done()
  local current = cbs
  cbs = nil
  if current and current.on_done then
    vim.schedule(function()
      inflight = false
      current.on_done()
    end)
  else
    inflight = false
  end
end

local function kill_job()
  if job_id then
    pcall(vim.fn.jobstop, job_id)
  end
  job_id = nil
  session_id = nil
  pending = {}
  stdout_rest = ""
  next_rpc_id = 0
end

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
  if type(text) ~= "string" or text == "" or not cbs or not cbs.on_chunk then
    return
  end
  vim.schedule(function()
    if cbs and cbs.on_chunk then
      cbs.on_chunk(text)
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

local function on_exit()
  local was_job = job_id
  job_id = nil
  session_id = nil
  pending = {}
  stdout_rest = ""
  if was_job and inflight then
    notify_error("Cursor Agent exited")
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
    local function open_session()
      request("session/new", {
        cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":p"),
        mcpServers = {},
      }, function(session_err, session)
        if session_err or not session or not session.sessionId then
          kill_job()
          on_ready(session_err or "session/new failed")
          return
        end
        session_id = session.sessionId
        on_ready(nil)
      end)
    end
    local need_login = false
    for _, method in ipairs(result.authMethods or {}) do
      if method.id == "cursor_login" then
        need_login = true
        break
      end
    end
    if not need_login then
      open_session()
      return
    end
    request("authenticate", { methodId = "cursor_login" }, function(auth_err)
      if auth_err then
        kill_job()
        on_ready(auth_err)
        return
      end
      open_session()
    end)
  end)
end

local function ensure_session(on_ready)
  if job_id and session_id then
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

function M.is_inflight()
  return inflight
end

function M.prompt(text, callbacks)
  if inflight then
    return false
  end
  cancelled = false
  inflight = true
  cbs = callbacks
  ensure_session(function(err)
    if err then
      notify_error(err)
      return
    end
    if cancelled then
      notify_done()
      return
    end
    request("session/prompt", {
      sessionId = session_id,
      prompt = { { type = "text", text = text } },
    }, function(prompt_err)
      if prompt_err then
        notify_error(prompt_err)
        return
      end
      notify_done()
    end)
  end)
  return true
end

function M.cancel()
  cancelled = true
  if not inflight or not session_id then
    return
  end
  write({
    jsonrpc = "2.0",
    method = "session/cancel",
    params = { sessionId = session_id },
  })
end

return M
