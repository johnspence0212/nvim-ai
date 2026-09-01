# Cursor Agent ACP today

Researched 2026-08-31 against first-party Cursor docs, the Agent Client Protocol (ACP) spec, and the ACP registry. This note is the source of facts for a later grilling ticket on the Neovim Profile's ACP core MVP.

Out of scope here: permissions, diffs, Ask/Plan/Agent modes, buffer/selection context.

## MVP-relevant facts

- **The official ACP launch command is `agent acp`.** That is what Cursor documents and what its published Node client spawns. It is a hidden subcommand of the **Cursor Agent CLI**, not of the editor's `cursor` binary. ([Cursor ACP docs](https://cursor.com/docs/cli/acp.md), [Cursor CLI parameters](https://cursor.com/docs/cli/reference/parameters.md))
- **`agent` is not on PATH on this Windows machine because the Agent CLI is not installed.** `where agent` / `where cursor-agent` fail. `%LOCALAPPDATA%\cursor-agent` and `~\.local\bin` do not exist. The editor CLI **is** on PATH (`cursor` / `cursor.cmd` under `...\Programs\cursor\resources\app\bin`) and its `--help` has no `acp` command. ACP is a separate install. ([Cursor installation](https://cursor.com/docs/cli/installation.md); checked locally 2026-08-31)
- **Install the Agent CLI, then spawn it.** Unix/WSL: `curl https://cursor.com/install -fsS | bash`, then add `~/.local/bin` to PATH; default binary path in Cursor's Neovim example is `~/.local/bin/agent`. Native Windows: `irm 'https://cursor.com/install?win32=true' | iex`, then `agent --version`. There is **no npm/npx ACP package** in Cursor's docs; `@cursor/sdk` is a different (non-ACP) programmatic API. ([Installation](https://cursor.com/docs/cli/installation.md), [ACP / avante.nvim example](https://cursor.com/docs/cli/acp.md), [TypeScript SDK](https://cursor.com/docs/sdk/typescript))
- **Inside the downloadable package the executable is named `cursor-agent`, not `agent`.** ACP registry (Cursor-authored entry) launches `./dist-package/cursor-agent acp` on Unix and `./dist-package\cursor-agent.cmd acp` on Windows, from archives at `https://downloads.cursor.com/lab/<version>/<os>/<arch>/agent-cli-package.{tar.gz,zip}`. Cursor user-facing docs still say `agent`. A Neovim client should treat `agent` and `cursor-agent` as the same CLI. ([ACP registry JSON](https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json), entry `id: "cursor"` version `2026.08.11`)
- **Process model is stdio JSON-RPC 2.0, newline-delimited (one JSON object per line), not HTTP.** Client spawns the agent as a subprocess, writes requests to stdin, reads responses/notifications from stdout, may ignore or capture stderr logs. HTTP transport is a draft in ACP, unused by Cursor ACP. ([Cursor ACP](https://cursor.com/docs/cli/acp.md), [ACP v1 transports](https://agentclientprotocol.com/protocol/v1/transports.md), [ACP architecture](https://agentclientprotocol.com/get-started/architecture.md))
- **Cursor's published ACP surface is ACP v1, not the v2 draft.** Cursor's minimal client sends `protocolVersion: 1`, `authenticate` (not v2 `auth/login`), `session/new` / `session/load`, and treats `session/prompt` as a turn that completes with `stopReason`. ACP v2 (draft, announced 2026-07-20) changes those shapes; Cursor docs have not switched. MVP should speak v1 as Cursor documents it. ([Cursor ACP](https://cursor.com/docs/cli/acp.md), [ACP v1 overview](https://agentclientprotocol.com/protocol/v1/overview.md), [ACP v2 draft announcement](https://agentclientprotocol.com/announcements/acp-v2-draft.md))
- **Minimal handshake:** `initialize` → (optional) `authenticate` with `methodId: "cursor_login"` → `session/new`. Cursor's example initialize params: `{ protocolVersion: 1, clientCapabilities: { fs: { readTextFile: false, writeTextFile: false }, terminal: false }, clientInfo: { name, version } }`. Omitted client capabilities mean unsupported. Agent replies with `protocolVersion`, `agentCapabilities`, `authMethods`. ([Cursor ACP](https://cursor.com/docs/cli/acp.md), [ACP v1 initialization](https://agentclientprotocol.com/protocol/v1/initialization.md))
- **Auth can be done before spawn.** Cursor advertises `cursor_login`. Pre-auth: `agent login`, or `--api-key` / `CURSOR_API_KEY`, or `--auth-token` / `CURSOR_AUTH_TOKEN`. Example: `agent --api-key "$CURSOR_API_KEY" acp`. Root flags go *before* `acp`. ([Cursor ACP](https://cursor.com/docs/cli/acp.md), [CLI authentication](https://cursor.com/docs/cli/reference/authentication.md))
- **Hold a Session with `session/new`.** Required params: absolute `cwd`, `mcpServers` (empty array is fine). Response: `{ sessionId }`. Use that id on every later prompt. `session/load` is optional (`loadSession` capability) and out of MVP if starting fresh. ([Cursor ACP](https://cursor.com/docs/cli/acp.md), [ACP v1 session setup](https://agentclientprotocol.com/protocol/v1/session-setup.md))
- **Send a user prompt with `session/prompt`.** Params: `{ sessionId, prompt: [{ type: "text", text: "..." }] }`. Text (and resource links) are baseline; images/audio/embedded resources need advertised `promptCapabilities`. ([Cursor ACP](https://cursor.com/docs/cli/acp.md), [ACP v1 prompt turn](https://agentclientprotocol.com/protocol/v1/prompt-turn.md), [ACP v1 content](https://agentclientprotocol.com/protocol/v1/content.md))
- **Stream the assistant response via `session/update` notifications (no `id`, do not reply).** Cursor's example reads `params.update.sessionUpdate === "agent_message_chunk"` and appends `update.content.text`. The turn ends when the agent **responds** to the original `session/prompt` with `{ stopReason }` (`end_turn`, `max_tokens`, `max_turn_requests`, `refusal`, `cancelled`). Optional `session/cancel` notification to interrupt. ([Cursor ACP](https://cursor.com/docs/cli/acp.md), [ACP v1 prompt turn](https://agentclientprotocol.com/protocol/v1/prompt-turn.md), [ACP schema / StopReason](https://agentclientprotocol.com/protocol/v1/schema.md))

## Launch: CLI command, args, env

### Official user-facing command

Cursor's ACP page:

> You can run `agent acp` and connect a custom client over `stdio` using JSON-RPC.

Start server:

```bash
agent acp
```

Spawn example (Node):

```js
const agent = spawn("agent", ["acp"], { stdio: ["pipe", "pipe", "inherit"] });
```

Source: [https://cursor.com/docs/cli/acp.md](https://cursor.com/docs/cli/acp.md)

The same command is listed in CLI parameters as a **hidden** command: `acp` — "Start ACP server mode (advanced, hidden command)". It is omitted from default `--help`. Source: [https://cursor.com/docs/cli/reference/parameters.md](https://cursor.com/docs/cli/reference/parameters.md)

Related: [https://cursor.com/docs/cli/using.md](https://cursor.com/docs/cli/using.md) ("Use `agent acp` to run Cursor CLI as an ACP server over `stdio` with JSON-RPC messaging.")

### What `agent` is (and is not)

| Binary | Role | ACP? |
| --- | --- | --- |
| `agent` / `cursor-agent` | Cursor Agent CLI (separate install from [cursor.com/install](https://cursor.com/install)) | Yes: `agent acp` |
| `cursor` / `cursor.cmd` | Cursor editor (VS Code-style) CLI | No `acp` in `--help` (checked 3.11.19 on this machine) |
| `@cursor/sdk` (`npm install @cursor/sdk`) | Programmatic Agent API (`Agent.create`, local/cloud runtimes) | Not ACP stdio. Source: [https://cursor.com/docs/sdk/typescript](https://cursor.com/docs/sdk/typescript) |

Cursor installation docs name the product "Cursor CLI" and verify with `agent --version`. Interactive use is `agent`, not `cursor`. Sources: [installation](https://cursor.com/docs/cli/installation.md), [overview](https://cursor.com/docs/cli/overview.md).

### Install paths

**Unix / WSL (documented):**

```bash
curl https://cursor.com/install -fsS | bash
# then: export PATH="$HOME/.local/bin:$PATH"
agent --version
```

Default path in Cursor's avante.nvim snippet: `$HOME/.local/bin/agent` with `args = { "acp" }`. Source: [https://cursor.com/docs/cli/acp.md](https://cursor.com/docs/cli/acp.md)

**Windows native (documented):**

```powershell
irm 'https://cursor.com/install?win32=true' | iex
agent --version
```

Cursor's installation page does **not** document a Windows filesystem path. It only documents the installer and `agent --version`. Source: [https://cursor.com/docs/cli/installation.md](https://cursor.com/docs/cli/installation.md)

**Packaged binary name (ACP registry, Cursor entry):**

The first-party ACP registry lists Cursor (`id: "cursor"`, version `2026.08.11`, website `https://cursor.com/docs/cli/acp`) with **binary** distribution only (no `npx` / `uvx`):

| Platform | Archive | `cmd` | `args` |
| --- | --- | --- | --- |
| `windows-x86_64` | `https://downloads.cursor.com/lab/2026.08.11-e8db854/windows/x64/agent-cli-package.zip` | `./dist-package\cursor-agent.cmd` | `["acp"]` |
| `windows-aarch64` | `.../windows/arm64/agent-cli-package.zip` | `./dist-package\cursor-agent.cmd` | `["acp"]` |
| `linux-x86_64` | `.../linux/x64/agent-cli-package.tar.gz` | `./dist-package/cursor-agent` | `["acp"]` |
| `darwin-aarch64` | `.../darwin/arm64/agent-cli-package.tar.gz` | `./dist-package/cursor-agent` | `["acp"]` |

Source: [https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json](https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json) (documented at [https://agentclientprotocol.com/get-started/registry.md](https://agentclientprotocol.com/get-started/registry.md))

Implication for a Neovim client: resolve `agent` on PATH if present; otherwise `cursor-agent` / `cursor-agent.cmd`; otherwise a configured absolute path. Do not call `cursor acp`. Do not expect an npm package.

### Env and flags that matter at launch

From Cursor ACP docs, flags belong on the **root** command, before `acp`:

```bash
agent --api-key "$CURSOR_API_KEY" acp
agent -e https://api2.cursor.sh acp
agent -k acp
```

Auth-related env documented alongside ACP:

- `CURSOR_API_KEY` (also `--api-key`)
- `CURSOR_AUTH_TOKEN` (also `--auth-token`)

Cursor's avante.nvim example also forwards `HOME` and `PATH` into the child. Source: [https://cursor.com/docs/cli/acp.md](https://cursor.com/docs/cli/acp.md)

General CLI auth (same CLI): `agent login` / `agent status` / `agent logout`; `NO_OPEN_BROWSER=1` for non-interactive login URL. Source: [https://cursor.com/docs/cli/reference/authentication.md](https://cursor.com/docs/cli/reference/authentication.md)

`--workspace` exists as a global CLI option (workspace directory). Source: [https://cursor.com/docs/cli/reference/parameters.md](https://cursor.com/docs/cli/reference/parameters.md). ACP `session/new` still takes its own absolute `cwd`.

### This Windows machine (2026-08-31)

- `agent` / `cursor-agent`: not on PATH.
- `%LOCALAPPDATA%\cursor-agent`: missing (typical post-install tree from community reports; **not** documented in Cursor's install page).
- `~\.local\bin`: missing.
- `cursor` editor CLI present: `C:\Users\johns\AppData\Local\Programs\cursor\resources\app\bin\cursor.cmd`. `--help` is the editor CLI (diff/goto/extensions/MCP add). Recursive search under the editor install found **no** `agent` / `cursor-agent` executable.

A Profile on this machine cannot spawn ACP until the Agent CLI is installed via the Windows installer above (or a configured path to `cursor-agent.cmd`).

## Process model

ACP architecture: the editor boots the agent **subprocess on demand**; all communication is stdin/stdout. One connection can host several concurrent sessions. JSON-RPC notifications stream UI updates; JSON-RPC requests going the other way let the agent ask the editor (e.g. permissions — out of scope). Source: [https://agentclientprotocol.com/get-started/architecture.md](https://agentclientprotocol.com/get-started/architecture.md)

### Transport (Cursor + ACP v1)

Cursor ACP page:

- Transport: `stdio`
- Envelope: JSON-RPC 2.0
- Framing: newline-delimited JSON (one message per line)
- Client → agent: stdin
- Agent → client: stdout
- Logs: stderr

ACP v1 transports (same rules):

- Client launches agent as subprocess.
- Messages MUST be UTF-8, MUST NOT contain embedded newlines.
- Agent MUST NOT write non-ACP JSON to stdout; client MUST NOT write non-ACP JSON to stdin.
- stderr MAY be UTF-8 logs; clients MAY capture, forward, or ignore.
- Streamable HTTP: "draft proposal in progress." Agents and clients SHOULD support stdio.

Sources: [https://cursor.com/docs/cli/acp.md](https://cursor.com/docs/cli/acp.md), [https://agentclientprotocol.com/protocol/v1/transports.md](https://agentclientprotocol.com/protocol/v1/transports.md)

Cursor's Node example uses `readline` on `agent.stdout` (line-at-a-time JSON.parse) and `agent.stdin.write(JSON.stringify(...) + "\n")`.

ACP is **bidirectional**: the client sends requests (`initialize`, `session/new`, `session/prompt`); the agent sends responses to those ids **and** notifications (`session/update`) **and** may send requests the client must answer (`session/request_permission` — out of MVP scope but will block tools if ignored; Cursor says so).

## Protocol surface (ACP v1, as Cursor implements)

Canonical v1 docs: [overview](https://agentclientprotocol.com/protocol/v1/overview.md), [initialization](https://agentclientprotocol.com/protocol/v1/initialization.md), [session setup](https://agentclientprotocol.com/protocol/v1/session-setup.md), [prompt turn](https://agentclientprotocol.com/protocol/v1/prompt-turn.md), [schema](https://agentclientprotocol.com/protocol/v1/schema.md). GitHub: [agentclientprotocol/agent-client-protocol](https://github.com/agentclientprotocol/agent-client-protocol). Latest v1 schema release at research time: [schema-v1.21.0](https://github.com/agentclientprotocol/agent-client-protocol/releases/tag/schema-v1.21.0) (2026-08-20).

Unversioned URLs under `https://agentclientprotocol.com/protocol/` currently serve the **v1** shapes (`protocolVersion: 1`, `authenticate`, `session/load`, prompt response with `stopReason`). v2 lives under `/protocol/v2/`.

### Typical Cursor flow

From [https://cursor.com/docs/cli/acp.md](https://cursor.com/docs/cli/acp.md):

1. `initialize`
2. `authenticate` with `methodId: "cursor_login"`
3. `session/new` (or `session/load`)
4. `session/prompt`
5. Handle `session/update` while the model streams
6. Handle `session/request_permission` (out of scope for this ticket; Cursor: if unanswered, tool execution can block)
7. Optionally `session/cancel`

Building-an-integration checklist from the same page: spawn `agent acp` → JSON-RPC over stdio → handle `session/update` for streaming → respond to permission requests → optionally implement Cursor extension methods (`cursor/ask_question`, etc.; out of scope).

### `initialize` (required)

Client → Agent request. MUST be first. Params (v1):

- `protocolVersion` (integer, required): Cursor example uses `1`.
- `clientCapabilities` (optional): omitted fields = unsupported.
- `clientInfo` (optional, SHOULD): `{ name, title?, version }`.

Cursor minimal client:

```json
{
  "jsonrpc": "2.0",
  "id": 0,
  "method": "initialize",
  "params": {
    "protocolVersion": 1,
    "clientCapabilities": {
      "fs": { "readTextFile": false, "writeTextFile": false },
      "terminal": false
    },
    "clientInfo": { "name": "acp-minimal-client", "version": "0.1.0" }
  }
}
```

ACP v1 spec example uses the same field names with richer capabilities (`fs.readTextFile` / `writeTextFile`, `terminal: true`). Schema default for client capabilities: `fs.readTextFile`/`writeTextFile` false, `terminal` false. Sources: [Cursor ACP](https://cursor.com/docs/cli/acp.md), [ACP v1 initialization](https://agentclientprotocol.com/protocol/v1/initialization.md), [ACP v1 schema](https://agentclientprotocol.com/protocol/v1/schema.md)

Agent response MUST include the chosen `protocolVersion`. If the client cannot speak that version, it SHOULD close the connection. Agent SHOULD also return `agentCapabilities`, `agentInfo`, `authMethods`.

v1 `agentCapabilities` used by Cursor's published example (and spec):

- Baseline (always, if the agent is a session agent): `session/new`, `session/prompt`, `session/cancel`, `session/update`
- `loadSession`: enables `session/load`
- `promptCapabilities`: `{ image, audio, embeddedContext }` beyond baseline text + resource_link
- `mcpCapabilities`: `{ http, sse }`

Version negotiation: client sends the latest version it supports; agent echoes it if supported, otherwise its latest. Source: [ACP v1 initialization](https://agentclientprotocol.com/protocol/v1/initialization.md)

**v2 difference (do not use unless Cursor advertises v2):** `protocolVersion: 2`, params `capabilities` + `info` instead of `clientCapabilities` + `clientInfo`, agent returns `capabilities.session` instead of `agentCapabilities`. Source: [ACP v2 initialization](https://agentclientprotocol.com/protocol/v2/initialization.md). ACP maintainers: v2 is Draft; do not ship as default; keep v1. Source: [https://agentclientprotocol.com/announcements/acp-v2-draft.md](https://agentclientprotocol.com/announcements/acp-v2-draft.md)

### `authenticate` (Cursor expects `cursor_login`)

Cursor: advertise/use `methodId: "cursor_login"`. Spec: `authenticate` params `{ methodId }` matching an `authMethods[].id` from initialize. Success result is empty `{}`. After success, `session/new` should not return `auth_required`.

If `authMethods` is empty, ACP v2 says clients MUST NOT call login methods; v1 still has `authenticate` as a baseline agent method when auth is required. Cursor's example always calls it. Pre-authenticating via `agent login` / API key is the practical path Cursor documents "in practice."

Sources: [Cursor ACP](https://cursor.com/docs/cli/acp.md), [ACP v1 authentication](https://agentclientprotocol.com/protocol/v1/authentication.md)

### `session/new` (create and hold a Session)

Request:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "session/new",
  "params": {
    "cwd": "/absolute/path/to/project",
    "mcpServers": []
  }
}
```

- `cwd` MUST be absolute; it is the session filesystem context regardless of where the subprocess was spawned. ([session setup](https://agentclientprotocol.com/protocol/v1/session-setup.md))
- `mcpServers` is required in the v1 schema (`McpServer[]`). Cursor's example sends `[]`.
- Response: `{ "sessionId": "..." }` (required). Optional `modes` / config — out of scope.

Cursor example: `const { sessionId } = await send("session/new", { cwd: process.cwd(), mcpServers: [] })`.

`session/load` (optional, `loadSession: true`) resumes and **replays** history as `session/update`s before the load response. Not required to hold a new Session.

### `session/prompt` (user message)

Request:

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "session/prompt",
  "params": {
    "sessionId": "sess_...",
    "prompt": [{ "type": "text", "text": "Say hello in one sentence." }]
  }
}
```

v1 semantics (Cursor + spec): this request **owns the turn**. The agent streams via notifications, then **resolves the same JSON-RPC id** with:

```json
{ "jsonrpc": "2.0", "id": 2, "result": { "stopReason": "end_turn" } }
```

`StopReason` union: `end_turn` | `max_tokens` | `max_turn_requests` | `refusal` | `cancelled`. Sources: [prompt turn](https://agentclientprotocol.com/protocol/v1/prompt-turn.md), [schema](https://agentclientprotocol.com/protocol/v1/schema.md), TypeScript SDK `StopReason` in [agentclientprotocol/typescript-sdk](https://github.com/agentclientprotocol/typescript-sdk/blob/main/src/schema/types.gen.ts)

**v2 difference:** `session/prompt` returns `{}` as soon as the prompt is accepted; completion is a `session/update` with `state_update` / `idle` + `stopReason`. Cursor's Node client logs `[stopReason=${result.stopReason}]` on the **prompt response**, which is v1.

### `session/update` (stream)

Notification (no `id`):

```json
{
  "jsonrpc": "2.0",
  "method": "session/update",
  "params": {
    "sessionId": "sess_...",
    "update": {
      "sessionUpdate": "agent_message_chunk",
      "content": { "type": "text", "text": "Hello..." }
    }
  }
}
```

Cursor's minimal client only handles `agent_message_chunk` + `content.text`. Spec also defines `user_message_chunk`, `agent_thought_chunk`, `tool_call`, `tool_call_update`, `plan`, plus later v1 additions (`usage_update`, etc.). MVP text streaming: append chunks until the `session/prompt` result arrives.

Optional `messageId` groups chunks into one message. Source: [prompt turn](https://agentclientprotocol.com/protocol/v1/prompt-turn.md)

### `session/cancel` (optional interrupt)

Notification: `{ "method": "session/cancel", "params": { "sessionId" } }`. Agent SHOULD abort and then respond to the in-flight `session/prompt` with `stopReason: "cancelled"` (v1). Source: [prompt turn](https://agentclientprotocol.com/protocol/v1/prompt-turn.md)

## Capabilities handshake (minimal client)

What a smallest Neovim client must send (matching Cursor's published example):

1. `initialize` with `protocolVersion: 1`.
2. `clientCapabilities` that honestly advertise **no** fs/terminal if the Profile will not implement `fs/*` or `terminal/*` (Cursor example: all false). Spec: omitted = unsupported; agent SHOULD tolerate any combination.
3. `clientInfo.name` + `version` (SHOULD in v1).
4. Read `initialize` result: honor returned `protocolVersion`; if `authMethods` includes `cursor_login`, either call `authenticate` or pre-auth the CLI so `session/new` succeeds.
5. Do not send image/audio/embedded resource prompt blocks unless `agentCapabilities.promptCapabilities` says so. Text is always allowed.

Cursor's example does **not** send `_meta` or custom capabilities.

## v1 vs v2 (trap for implementers)

| Topic | Cursor docs + ACP v1 (MVP) | ACP v2 draft |
| --- | --- | --- |
| Version | `1` | `2` |
| Init fields | `clientCapabilities`, `clientInfo` / `agentCapabilities`, `agentInfo` | `capabilities`, `info` |
| Auth method | `authenticate` | `auth/login` |
| Resume | `session/load` (replay) | `session/resume` (+ optional `replayFrom`) |
| Prompt completion | `session/prompt` result `{ stopReason }` | prompt result `{}`; idle via `state_update` |
| Stream text | `agent_message_chunk` | `agent_message` and/or `agent_message_chunk` |

Sources: [v1 overview](https://agentclientprotocol.com/protocol/v1/overview.md), [v2 overview](https://agentclientprotocol.com/protocol/v2/overview.md), [v2 migration](https://agentclientprotocol.com/protocol/v2/migration.md), [Cursor ACP](https://cursor.com/docs/cli/acp.md)

## Primary sources

- Cursor ACP: [https://cursor.com/docs/cli/acp.md](https://cursor.com/docs/cli/acp.md)
- Cursor CLI install: [https://cursor.com/docs/cli/installation.md](https://cursor.com/docs/cli/installation.md)
- Cursor CLI overview: [https://cursor.com/docs/cli/overview.md](https://cursor.com/docs/cli/overview.md)
- Cursor CLI using (ACP one-liner): [https://cursor.com/docs/cli/using.md](https://cursor.com/docs/cli/using.md)
- Cursor CLI parameters (`acp` hidden): [https://cursor.com/docs/cli/reference/parameters.md](https://cursor.com/docs/cli/reference/parameters.md)
- Cursor CLI authentication: [https://cursor.com/docs/cli/reference/authentication.md](https://cursor.com/docs/cli/reference/authentication.md)
- Cursor TypeScript SDK (not ACP): [https://cursor.com/docs/sdk/typescript](https://cursor.com/docs/sdk/typescript)
- ACP registry (Cursor binary + `cursor-agent acp`): [https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json](https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json), [registry docs](https://agentclientprotocol.com/get-started/registry.md)
- ACP architecture: [https://agentclientprotocol.com/get-started/architecture.md](https://agentclientprotocol.com/get-started/architecture.md)
- ACP v1: [overview](https://agentclientprotocol.com/protocol/v1/overview.md), [initialization](https://agentclientprotocol.com/protocol/v1/initialization.md), [authentication](https://agentclientprotocol.com/protocol/v1/authentication.md), [session setup](https://agentclientprotocol.com/protocol/v1/session-setup.md), [prompt turn](https://agentclientprotocol.com/protocol/v1/prompt-turn.md), [content](https://agentclientprotocol.com/protocol/v1/content.md), [transports](https://agentclientprotocol.com/protocol/v1/transports.md), [schema](https://agentclientprotocol.com/protocol/v1/schema.md)
- ACP GitHub: [https://github.com/agentclientprotocol/agent-client-protocol](https://github.com/agentclientprotocol/agent-client-protocol)
- ACP v1 schema release: [https://github.com/agentclientprotocol/agent-client-protocol/releases/tag/schema-v1.21.0](https://github.com/agentclientprotocol/agent-client-protocol/releases/tag/schema-v1.21.0)
- ACP v2 draft status: [https://agentclientprotocol.com/announcements/acp-v2-draft.md](https://agentclientprotocol.com/announcements/acp-v2-draft.md)
