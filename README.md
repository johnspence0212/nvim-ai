# nvim-ai

An isolated Neovim Profile (`NVIM_APPNAME=nvim-ai`) on LazyVim. Distinct from a default Neovim configuration (`nvim` still opens that one). Cursor Agent is the AI runtime, wired later via ACP. `:Nai` is this Profile's command.

Keep the git clone where it is. Neovim finds this Profile through `NVIM_APPNAME`, not by moving the repo.

## Point stdpath at this repo

**Windows** — directory junction (no admin):

```powershell
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\nvim-ai" -Target "<path-to-this-clone>"
```

Skip this if `$env:LOCALAPPDATA\nvim-ai` already points at the clone.

**Unix** — symlink:

```bash
ln -s /path/to/nvim-ai ~/.config/nvim-ai
```

## Launch

`nvim` stays your default configuration. This Profile is a separate command:

```text
nvim-ai .
```

That works once this clone's directory is on your `PATH` (on this machine, `%LOCALAPPDATA%\nvim-ai` via the junction). `nvim-ai.cmd` / `nvim-ai` set `NVIM_APPNAME=nvim-ai` and exec `nvim`.

Repo-local shortcuts still work: `.\nai.ps1 .` / `./nai .`.
