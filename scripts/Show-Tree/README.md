# stree — Directory Tree for Windows

A PowerShell `tree` command that actually looks good.
Prints Unicode box-drawing characters, respects `.gitignore`, and supports directory-only mode.

```
C:\Projects\MyApp
├── src/
│   ├── components/
│   │   ├── Button.tsx
│   │   └── Modal.tsx
│   └── index.ts
├── public/
│   └── favicon.ico
└── package.json
```

---

## Requirements

- Windows 10/11
- PowerShell 5.1+ (built-in) or PowerShell 7+

---

## Installation

1. Download `Show-Tree.ps1` and `stree.cmd` into the same folder, e.g. `C:\tools\PowerShell\`
2. Add that folder to your system PATH (one-time setup):

```powershell
# Run in an elevated PowerShell window
$p = "C:\tools\PowerShell"
[Environment]::SetEnvironmentVariable(
    "Path",
    [Environment]::GetEnvironmentVariable("Path","Machine") + ";$p",
    "Machine"
)
```

3. Restart your terminal. `stree` is now available everywhere.

---

## Usage

```
stree [<Path>] [-Depth <n>] [-GitIgnore] [-DirectoriesOnly] [-Ignore <names>] [-Export <file>]
```

| Flag | Default | Description |
|---|---|---|
| `Path` | `.` | Root directory to display |
| `-Depth` | `3` | How many levels deep to recurse |
| `-GitIgnore` | off | Respect the `.gitignore` file in the root |
| `-DirectoriesOnly` | off | Hide files, show folder skeleton only |
| `-Ignore` | `.git` | Extra names to always exclude |
| `-Export` | — | Save output to a file instead of printing |

---

## Examples

```powershell
stree
stree C:\Projects\MyApp -Depth 5
stree -GitIgnore
stree -DirectoriesOnly -Depth 2
stree -Ignore ".git","node_modules","dist"
stree -Export tree.txt
stree -?
```

---

## Help

Every flag is documented. Run `stree -?` for quick help, or:

```powershell
Get-Help C:\tools\PowerShell\Show-Tree.ps1 -Full
Get-Help C:\tools\PowerShell\Show-Tree.ps1 -Examples
```

---

## Also Available

This script is also published as a standalone GitHub Gist:
[gist.github.com/karimdhafer52/20e6df87b4bd11c249556e87b4ae1689](https://gist.github.com/karimdhafer52/20e6df87b4bd11c249556e87b4ae1689)