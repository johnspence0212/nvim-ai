# nvim-ai

An isolated Neovim Profile (`NVIM_APPNAME=nvim-ai`). Distinct from a default Neovim configuration. Neovim is the editor; Cursor Agent is the AI runtime, wired later via ACP.

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

From this repo:

```powershell
.\nai.ps1 .
```

```bash
./nai .
```

Or set `NVIM_APPNAME=nvim-ai` and run `nvim` yourself.

Optional user alias, after the junction or symlink exists:

```powershell
function nai { $env:NVIM_APPNAME = "nvim-ai"; nvim @args }
```

```bash
alias nai='NVIM_APPNAME=nvim-ai nvim'
```

Then `nai .`
