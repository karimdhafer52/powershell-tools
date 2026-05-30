# gsum — Git Repository Summary

A PowerShell command that gives you the full picture of a Git repository in one shot.
Branch health, sync status, recent commits, working tree changes, stashes, and contributors — all in a single clean output.

```
  C:\Projects\myapp  ↑

  Branch   main  (3 local, 1 unmerged)  · 2 remote
  Type     node
  Remote   github.com/yourname/myapp  (fetched 12m ago)
  Sync     2 commit(s) ahead — push needed
  Commits  148 total  · started 8 months ago
  Tag      ◆ v1.4.0  (6 tags total)

  BRANCHES
  ──────────────────────────────────────────────────────────
    ● main  (current)
    ○ feature/auth  [unmerged]
    ○ fix/old-bug

  LAST 5 COMMITS
  ──────────────────────────────────────────────────────────
    ○ a3f92c1 fix modal close handler  HEAD
              John Smith  ·  2 hours ago
    ○ b1d34e2 add auth middleware
              John Smith  ·  1 day ago

  WORKING TREE
  ──────────────────────────────────────────────────────────
    Volume   +34 -12
    Staged     src/index.ts
    Modified   src/components/Button.tsx
    Untracked  .env.local

  TOP 3 CONTRIBUTORS
  ──────────────────────────────────────────────────────────
    1.  John Smith                  97 commits
    2.  Jane Doe                    51 commits
```

---

## Requirements

- Windows 10/11
- PowerShell 5.1+ (built-in) or PowerShell 7+
- Git installed and available in PATH

---

## Installation

1. Clone or download the files into `C:\tools\PowerShell\` following the structure below.
2. Add `C:\tools\PowerShell\bin` to your system PATH (one-time setup):

```powershell
# Run in an elevated PowerShell window
$p = "C:\tools\PowerShell\bin"
[Environment]::SetEnvironmentVariable(
    "Path",
    [Environment]::GetEnvironmentVariable("Path", "Machine") + ";$p",
    "Machine"
)
```

3. Restart your terminal. `gsum` is now available everywhere.

---

## Folder Structure

```
C:\tools\
└── PowerShell/
    ├── bin/
    │   ├── gsum.cmd
    │   └── stree.cmd
    ├── scripts/
    │   ├── Get-GitSummary/
    │   │   ├── Get-GitSummary.ps1
    │   │   └── README.md
    │   ├── Git-Commit-Message/
    │   │   ├── Git-Commit-Message.ps1
    │   │   └── README.md
    │   └── Show-Tree/
    │       ├── Show-Tree.ps1
    │       └── README.md
    └── README.md
```



`bin/` contains only the short CMD wrappers that go on your PATH.
`scripts/` contains the actual PowerShell scripts, each in its own folder.

---

## Usage

```
gsum [<Path>] [-Commits <n>] [-Stashes] [-Open] [-NoColor]
```

| Flag | Default | Description |
|---|---|---|
| `Path` | `.` | Repository to inspect |
| `-Commits` | `5` | Number of recent commits to show |
| `-Stashes` | off | Expand stash list with full messages |
| `-Open` | off | Open the remote URL in the browser |
| `-NoColor` | off | Plain text output, no color |

---

## Examples

```powershell
gsum
gsum -Path C:\Projects\myapp
gsum -Commits 10
gsum -Stashes
gsum -Open
gsum -NoColor
gsum -?
```

---

## Help

```powershell
gsum -?
Get-Help C:\tools\PowerShell\scripts\Get-GitSummary\Get-GitSummary.ps1 -Full
Get-Help C:\tools\PowerShell\scripts\Get-GitSummary\Get-GitSummary.ps1 -Examples
```

---

## Also Available

This script is also published as a standalone GitHub Gist:
[gist.github.com/karimdhafer52/c538c9c1816a8e5d9508ac131e91ed12](https://gist.github.com/karimdhafer52/c538c9c1816a8e5d9508ac131e91ed12)