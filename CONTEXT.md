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
_Avoid_: conversation, thread, Chat

**Chat**:
The Profile's UI for one Session: a composer you type in, and a transcript of turns above it. Distinct from Session.
_Avoid_: Session, scratch buffer, conversation, thread

**Composer**:
The input at the bottom of Chat where you type the next turn.
_Avoid_: input box, prompt, cmdline

**Agent Workspace**:
One Linear issue's isolated Git working directory, dedicated branch, Session, and lifecycle metadata. Distinct from the Profile. A Git worktree is one possible implementation, not the product.
_Avoid_: worktree, Profile
