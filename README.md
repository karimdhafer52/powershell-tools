# 🛠 c-tools · Windows CLI Suite

A collection of professional PowerShell utilities for Windows developers.
Inspired by Linux ergonomics — clean aliases, UTF-8 output, comment-based help.

---

## Installation

**One-time setup — add `C:\tools\PowerShell\bin` to your PATH:**

```powershell
# Run once in an elevated PowerShell session
$toolsPath = "C:\tools\PowerShell\bin"
$current = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($current -notlike "*$toolsPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$current;$toolsPath", "Machine")
    Write-Host "Added $toolsPath to system PATH. Restart your terminal."
}
```

After restarting your terminal, all aliases below are available globally.

---

## Tools

| Alias | Wrapper | Script | Description |
|-------|---------|--------|-------------|
| `stree` | [stree.cmd](bin/stree.cmd) | [Show-Tree.ps1](scripts/Show-Tree/README.md) | Print a directory tree (like Linux `tree`) |
| `gsum` | [gsum.cmd](bin/gsum.cmd) | [Get-GitSummary.ps1](scripts/Get-GitSummary/README.md) | Git repository summary — branch, sync, commits, tree |
| `smon` | [smon.cmd](bin/smon.cmd) | [Show-Monitor.ps1](scripts/Show-Monitor/README.md) | Real-time resource monitor for CPU, RAM, GPU, and Disk |

---

## Usage

### `stree` — Directory Tree

```
stree [<Path>] [-Depth <n>] [-GitIgnore] [-DirectoriesOnly] [-Ignore <names>] [-Export <file>]
```

```
stree                          # current directory, depth 3
stree C:\Projects\MyApp -Depth 5
stree -GitIgnore -DirectoriesOnly
stree -Export tree.txt
stree -?                       # full help
```

### `gsum` — Git Repository Summary
```
gsum [<Path>] [-Commits <n>] [-Stashes] [-Open] [-NoColor]
```
```
gsum                           # summary for the repo in the current directory
gsum C:\Projects\myapp         # summary for a specific repo
gsum -Commits 10               # show last 10 commits instead of 5
gsum -Stashes                  # expand stash list with full messages
gsum -Open                     # open the remote URL in the browser
gsum -NoColor                  # plain text output — useful for piping or logging
gsum -?                        # full help
```

### `smon` — Resource Monitor
```
smon [[-Watch]] [-Interval <n>] [-Top <n>] [-NoBanner] [-NoGpu] [-NoDocker] [-Export <file>]
```
```
smon                           # one-shot snapshot of all hardware metrics
smon -Watch                    # live dashboard, refreshes every 3 seconds (Q to quit)
smon -Watch -Interval 5 -Top 3 # live dashboard, 5-second refresh, 3 consumers per section
smon -NoGpu -NoDocker          # fastest snapshot — no external tool calls
smon -Export snapshot.txt      # save plain-text snapshot to file
smon -?                        # full help
```

---

## Getting Help

Every script has full comment-based help. Run `-?` or `Get-Help` on any script:

```powershell
stree -?
Get-Help C:\tools\PowerShell\scripts\Show-Tree\Show-Tree.ps1 -examples
Get-Help C:\tools\PowerShell\scripts\Show-Tree\Show-Tree.ps1 -detailed
Get-Help C:\tools\PowerShell\scripts\Show-Tree\Show-Tree.ps1 -full
Get-Help C:\tools\PowerShell\scripts\Show-Tree\Show-Tree.ps1 -online
```

---

## How It Works — CMD Wrappers

Each alias (e.g. `gsum`, `stree`, `smon`) is a thin `.cmd` file in `bin/` that calls the actual PowerShell script.
This is necessary because PowerShell `.ps1` files cannot be invoked directly from `cmd.exe`, the Windows Run dialog, or some terminals without explicit policy configuration.

The wrapper handles this transparently:

```cmd
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\Get-GitSummary\Get-GitSummary.ps1" %*
```

- `-NoProfile` — skips loading your PowerShell profile for faster startup  
- `-ExecutionPolicy Bypass` — runs the script regardless of system execution policy  
- `%*` — forwards all arguments you pass to the alias straight to the script

---

## Requirements

- Windows 10/11
- PowerShell 5.1+ (built-in) or PowerShell 7+ (recommended)
- Git installed and available in PATH (required for `gsum`)
- `nvidia-smi` on PATH for full GPU metrics in `smon` (optional — falls back to WMI)
- Docker Desktop running for container name resolution in `smon` (optional)
- No external module dependencies

---

## Repository Structure

```
C:\tools\PowerShell\
├── bin\                   ← CMD wrappers — this folder goes on your PATH
│   ├── gsum.cmd
│   ├── smon.cmd
│   └── stree.cmd
├── scripts\
│   ├── Get-GitSummary\
│   │   ├── Get-GitSummary.ps1
│   │   └── README.md
│   ├── Show-Monitor\
│   │   ├── Show-Monitor.ps1
│   │   └── README.md
│   └── Show-Tree\
│       ├── Show-Tree.ps1
│       └── README.md
└── README.md
```

---

## Contributing

Scripts follow these conventions:

- `[CmdletBinding()]` on every script
- Comment-based help with `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.LINK`
- UTF-8 safe output where text is printed
- `SupportsShouldProcess` on any script that modifies files or kills processes
- Alias name: short (≤7 chars), lowercase, no hyphens

---

## License

MIT — use freely, attribution appreciated.