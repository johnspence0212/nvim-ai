# nvim-ai

An isolated Neovim Profile (`NVIM_APPNAME=nvim-ai`). Distinct from a default Neovim configuration (`nvim` still opens that one). Cursor Agent is the AI runtime, wired via ACP. Chat is the Profile's Session UI (`<leader>nn` hide/show).

Keep the git clone where it is. Neovim finds this Profile through `NVIM_APPNAME`, not by moving the repo.

## Point stdpath at this repo

**Windows** — directory junction (no admin):

```powershell
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\nvim-ai" -Target "<path-to-this-clone>"
```

Skip this if `$env:LOCALAPPDATA\nvim-ai` already points at the clone.

**Unix** — two symlinks (stdpath, then launcher on `PATH`):

```bash
ln -s /path/to/nvim-ai ~/.config/nvim-ai
ln -s /path/to/nvim-ai/nvim-ai ~/.local/bin/nvim-ai
```

Skip these if they already point at the clone. Do not add `~/.config` to `PATH`.

## Launch

`nvim` stays your default configuration. This Profile is a separate command:

```text
nvim-ai .
```

`nvim-ai.cmd` / `nvim-ai` set `NVIM_APPNAME=nvim-ai` and exec `nvim`.

On Windows that works once the junction directory is on `PATH` (`%LOCALAPPDATA%\nvim-ai`). On Unix, `~/.local/bin` is already on `PATH`; the launcher symlink above is enough.

Repo-local shortcuts still work: `.\nai.ps1 .` / `./nai .`.
