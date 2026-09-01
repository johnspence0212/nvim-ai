# nvim-ai

An isolated Neovim Profile for AI-assisted development. Neovim is the editor; Cursor Agent is the AI runtime, integrated later via ACP.

## Language

**Profile**:
This repository's `NVIM_APPNAME` instance: its config directory, runtime files, and plugins. Distinct from the user's default Neovim configuration.
_Avoid_: distro, config, setup, environment

**Cursor Agent**:
Cursor's agent runtime, launched via `agent acp`.
_Avoid_: Cursor, Copilot

**ACP**:
Agent Client Protocol, the stdio protocol between the Profile and Cursor Agent.
_Avoid_: LSP, MCP

**Session**:
One ACP connection between the Profile and Cursor Agent. The Profile holds at most one at a time.
_Avoid_: conversation, chat, thread
