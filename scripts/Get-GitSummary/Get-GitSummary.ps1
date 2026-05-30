<#
.SYNOPSIS
    Displays a visual Git repository summary.

.DESCRIPTION
    Get-GitSummary (gsum) provides a comprehensive, scannable picture of a
    Git repository's current state — branch health, remote sync, recent
    commits, working tree changes, stashes, contributors, and tags — in a
    single clean output.

    Includes branch hygiene insights (merged vs unmerged), last fetch age,
    diff volume (lines added/removed), and a performance-safe commit count
    capped at 10,000 for large repositories.

.PARAMETER Path
    The repository to inspect. Defaults to the current directory.

.PARAMETER Commits
    Number of recent commits to display. Defaults to 5.

.PARAMETER Stashes
    Expands the stash list with full messages instead of just a count.

.PARAMETER Open
    Opens the remote GitHub/GitLab URL in the default browser.

.PARAMETER NoColor
    Disables all color output. Useful when piping or exporting.

.EXAMPLE
    gsum
    Shows the full summary for the repo in the current directory.

.EXAMPLE
    gsum -Path C:\Projects\myapp
    Shows the summary for a specific repo.

.EXAMPLE
    gsum -Commits 10
    Shows the last 10 commits instead of the default 5.

.EXAMPLE
    gsum -Stashes
    Expands stash entries with their full messages.

.EXAMPLE
    gsum -Open
    Opens the repo's remote URL in the default browser.

.EXAMPLE
    gsum -NoColor
    Outputs plain text with no color — useful for piping or logging.

.LINK
    https://gist.github.com/karimdhafer52/c538c9c1816a8e5d9508ac131e91ed12
#>

[CmdletBinding()]
param(
    [string]$Path = ".",
    [int]$Commits = 5,
    [switch]$Stashes,
    [switch]$Open,
    [switch]$NoColor
)

# ----------------------------
# Encoding safety
# ----------------------------
cmd /c chcp 65001 > $null
[System.Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# ----------------------------
# Build icons from code points (avoids source-encoding issues)
# ----------------------------
$UseUnicode = $true
try {
    $test = [System.Text.Encoding]::UTF8.GetString([byte[]](0xE2, 0x9C, 0x93))
    [System.Console]::OutputEncoding.GetBytes($test) | Out-Null
} catch {
    $UseUnicode = $false
}

if ($UseUnicode) {
    $Icons = @{
        Clean    = [System.Text.Encoding]::UTF8.GetString([byte[]](0xE2, 0x9C, 0x93))  # ✓
        Dirty    = [System.Text.Encoding]::UTF8.GetString([byte[]](0xE2, 0x97, 0x8F))  # ●
        Ahead    = [System.Text.Encoding]::UTF8.GetString([byte[]](0xE2, 0x86, 0x91))  # ↑
        Behind   = [System.Text.Encoding]::UTF8.GetString([byte[]](0xE2, 0x86, 0x93))  # ↓
        Diverged = [System.Text.Encoding]::UTF8.GetString([byte[]](0xE2, 0x9A, 0xA1))  # ⚡
        NoRemote = [System.Text.Encoding]::UTF8.GetString([byte[]](0xE2, 0x9C, 0x97))  # ✗
        Stash    = [System.Text.Encoding]::UTF8.GetString([byte[]](0xE2, 0x96, 0xA3))  # ▣
        Tag      = [System.Text.Encoding]::UTF8.GetString([byte[]](0xE2, 0x97, 0x86))  # ◆
        Commit   = [System.Text.Encoding]::UTF8.GetString([byte[]](0xE2, 0x97, 0x8B))  # ○
        Head     = [System.Text.Encoding]::UTF8.GetString([byte[]](0xE2, 0x97, 0x8F))  # ●
    }
} else {
    $Icons = @{
        Clean    = "OK"; Dirty    = "!!"; Ahead    = "^";  Behind = "v"
        Diverged = "<>"; NoRemote = "X";  Stash    = "S";  Tag    = "#"
        Commit   = "o";  Head     = "*"
    }
}

# ----------------------------
# Run a git command safely, return output or $null
# ----------------------------
function Invoke-Git {
    param([string]$RepoPath, [string[]]$Arguments)
    try {
        $result = & git -C $RepoPath $Arguments 2>$null
        return $result
    } catch {
        return $null
    }
}

# ----------------------------
# Detect project type from known marker files
# ----------------------------
function Get-ProjectType {
    param([string]$RepoPath)
    $markers = @(
        @{ File = "package.json";     Label = "node"   },
        @{ File = "Cargo.toml";       Label = "rust"   },
        @{ File = "go.mod";           Label = "go"     },
        @{ File = "requirements.txt"; Label = "python" },
        @{ File = "pyproject.toml";   Label = "python" },
        @{ File = "*.sln";            Label = "dotnet" },
        @{ File = "*.csproj";         Label = "dotnet" },
        @{ File = "pom.xml";          Label = "java"   },
        @{ File = "*.ps1";            Label = "ps1"    },
        @{ File = "Dockerfile";       Label = "docker" }
    )
    foreach ($m in $markers) {
        if (Get-ChildItem -Path $RepoPath -Filter $m.File -ErrorAction SilentlyContinue |
            Select-Object -First 1) {
            return $m.Label
        }
    }
    return "unknown"
}

# ----------------------------
# Color output helper — respects -NoColor
# ----------------------------
function Write-Token {
    param([string]$Text, [string]$Color = "White")
    if ($NoColor) { Write-Host $Text -NoNewline }
    else          { Write-Host $Text -ForegroundColor $Color -NoNewline }
}

function Write-Divider {
    Write-Token ("  " + ([string][char]0x2500 * 58) + "`n") "DarkGray"
}

function Write-Section {
    param([string]$Label)
    Write-Host ""
    Write-Token "  $Label`n" "DarkGray"
    Write-Divider
}

# ----------------------------
# Resolve path and validate repo
# ----------------------------
try {
    $resolvedPath = Resolve-Path $Path -ErrorAction Stop
    $repoPath     = $resolvedPath.Path
} catch {
    Write-Host "Invalid path: $Path" -ForegroundColor Red
    exit 1
}

$isRepo = Invoke-Git -RepoPath $repoPath -Arguments @("rev-parse", "--git-dir")
if (-not $isRepo) {
    Write-Host "Not a Git repository: $repoPath" -ForegroundColor Red
    exit 1
}

# ----------------------------
# Gather — branch data
# ----------------------------
$branch = Invoke-Git -RepoPath $repoPath -Arguments @("branch", "--show-current")
if (-not $branch) { $branch = "HEAD detached" }

$allBranches    = @(Invoke-Git -RepoPath $repoPath -Arguments @("branch", "--format=%(refname:short)"))
$remoteBranches = @(Invoke-Git -RepoPath $repoPath -Arguments @("branch", "-r", "--format=%(refname:short)"))

# Branch hygiene — merged branches (excluding current)
$mergedBranches = @(
    Invoke-Git -RepoPath $repoPath -Arguments @("branch", "--merged") |
    Where-Object { $_ -notmatch '^\*' } |
    ForEach-Object { $_.Trim() }
)
$unmergedCount = [Math]::Max(0, $allBranches.Count - $mergedBranches.Count - 1)

# ----------------------------
# Gather — remote
# ----------------------------
$remote = Invoke-Git -RepoPath $repoPath -Arguments @("remote", "get-url", "origin")
$remote = if ($remote) {
    $remote -replace "git@github\.com:", "github.com/" `
            -replace "git@gitlab\.com:", "gitlab.com/" `
            -replace "\.git$", ""
} else { $null }

# ----------------------------
# Gather — last fetch age
# ----------------------------
$fetchAge = $null
$gitDirRaw = Invoke-Git -RepoPath $repoPath -Arguments @("rev-parse", "--git-dir")
if ($gitDirRaw) {
    # git-dir can be relative (".git") or absolute (worktrees)
    $gitDirFull = if ([System.IO.Path]::IsPathRooted($gitDirRaw)) {
        $gitDirRaw
    } else {
        Join-Path $repoPath $gitDirRaw
    }
    $fetchHeadPath = Join-Path $gitDirFull "FETCH_HEAD"
    if (Test-Path $fetchHeadPath) {
        $span = (Get-Date) - (Get-Item $fetchHeadPath).LastWriteTime
        $fetchAge = if     ($span.TotalMinutes -lt 60) { "$([int]$span.TotalMinutes)m ago" }
                    elseif ($span.TotalHours   -lt 24) { "$([int]$span.TotalHours)h ago"   }
                    else                               { "$([int]$span.TotalDays)d ago"     }
    }
}

# ----------------------------
# Gather — ahead / behind
# ----------------------------
$ahead = 0; $behind = 0
if ($remote) {
    $ab = Invoke-Git -RepoPath $repoPath -Arguments @("rev-list", "--left-right", "--count", "@{upstream}...HEAD")
    if ($ab -match '(\d+)\s+(\d+)') {
        $behind = [int]$Matches[1]
        $ahead  = [int]$Matches[2]
    }
}

# ----------------------------
# Gather — working tree
# ----------------------------
$statusLines = @(Invoke-Git -RepoPath $repoPath -Arguments @("status", "--porcelain"))
$staged      = @($statusLines | Where-Object { $_ -match '^[MADRC]' })
$modified    = @($statusLines | Where-Object { $_ -match '^.[MD]'   })
$untracked   = @($statusLines | Where-Object { $_ -match '^\?\?'    })
$isDirty     = ($staged.Count + $modified.Count + $untracked.Count) -gt 0

# Diff volume — lines added / removed in unstaged changes
$linesAdded = 0; $linesDeleted = 0
$diffStats = Invoke-Git -RepoPath $repoPath -Arguments @("diff", "--shortstat")
if ($diffStats -match '(\d+)\s+insertion.*?(\d+)\s+deletion') {
    $linesAdded   = [int]$Matches[1]
    $linesDeleted = [int]$Matches[2]
} elseif ($diffStats -match '(\d+)\s+insertion') {
    $linesAdded   = [int]$Matches[1]
} elseif ($diffStats -match '(\d+)\s+deletion') {
    $linesDeleted = [int]$Matches[1]
}

# ----------------------------
# Gather — stashes, commits, tags, contributors
# ----------------------------
$stashList = @(Invoke-Git -RepoPath $repoPath -Arguments @("stash", "list"))
$logLines  = @(Invoke-Git -RepoPath $repoPath -Arguments @(
    "log", "-$Commits", "--format=%h|%s|%an|%cr|%D"
))

$latestTag = Invoke-Git -RepoPath $repoPath -Arguments @("describe", "--tags", "--abbrev=0")
$totalTags = @(Invoke-Git -RepoPath $repoPath -Arguments @("tag")).Count

# Cap at 10,000 for performance on large repos
$totalCommits = Invoke-Git -RepoPath $repoPath -Arguments @(
    "rev-list", "--count", "--max-count=10000", "HEAD"
)
if ([int]$totalCommits -eq 10000) { $totalCommits = "10,000+" }

$firstCommitDate = Invoke-Git -RepoPath $repoPath -Arguments @(
    "log", "--reverse", "--format=%cr", "--max-parents=0", "HEAD"
)
$contributors = @(Invoke-Git -RepoPath $repoPath -Arguments @(
    "shortlog", "-sn", "--no-merges", "HEAD"
))
$projectType = Get-ProjectType -RepoPath $repoPath

# ----------------------------
# Health indicator
# ----------------------------
$indicator = if (-not $remote)                             { $Icons.NoRemote }
             elseif ($ahead -gt 0 -and $behind -gt 0)     { $Icons.Diverged }
             elseif ($ahead  -gt 0)                        { $Icons.Ahead    }
             elseif ($behind -gt 0)                        { $Icons.Behind   }
             elseif ($isDirty)                             { $Icons.Dirty    }
             else                                          { $Icons.Clean    }

$indicatorColor = if     ($indicator -eq $Icons.Clean)    { "Green"    }
                  elseif ($indicator -eq $Icons.NoRemote) { "DarkGray" }
                  elseif ($indicator -eq $Icons.Dirty)    { "Yellow"   }
                  else                                    { "Red"      }

# ----------------------------
# -Open: launch browser and exit
# ----------------------------
if ($Open) {
    if ($remote) {
        $url = "https://$remote"
        Write-Host "Opening $url ..." -ForegroundColor Cyan
        Start-Process $url
    } else {
        Write-Host "No remote configured for this repo." -ForegroundColor Yellow
    }
    exit 0
}

# ════════════════════════════════════════════════════
#  OUTPUT
# ════════════════════════════════════════════════════

Write-Host ""

# ── Header ────────────────────────────────────────────────────────────────────
Write-Token "  $repoPath" "Cyan"
Write-Token "  $indicator`n" $indicatorColor
Write-Host ""

# ── Overview ──────────────────────────────────────────────────────────────────
Write-Token "  Branch   " "DarkGray"
Write-Token "$branch" "Yellow"
if ($allBranches.Count -gt 1) {
    Write-Token "  ($($allBranches.Count) local" "DarkGray"
    if ($unmergedCount -gt 0) {
        Write-Token ", " "DarkGray"
        Write-Token "$unmergedCount unmerged" "Red"
    }
    Write-Token ")" "DarkGray"
}
if ($remoteBranches.Count -gt 0) { Write-Token "  · $($remoteBranches.Count) remote" "DarkGray" }
Write-Host ""

Write-Token "  Type     " "DarkGray"
Write-Token "$projectType`n" "White"

Write-Token "  Remote   " "DarkGray"
Write-Token "$(if ($remote) { $remote } else { 'none' })" "DarkGray"
if ($remote -and $fetchAge) { Write-Token "  (fetched $fetchAge)" "DarkGray" }
Write-Host ""

# ── Sync ──────────────────────────────────────────────────────────────────────
Write-Token "  Sync     " "DarkGray"
$syncColor = "Green"
$syncLabel = if (-not $remote) {
                 $syncColor = "DarkGray"; "no remote configured"
             } elseif ($ahead -gt 0 -and $behind -gt 0) {
                 $syncColor = "Red";    "$ahead ahead · $behind behind (diverged)"
             } elseif ($ahead  -gt 0) {
                 $syncColor = "Yellow"; "$ahead commit(s) ahead — push needed"
             } elseif ($behind -gt 0) {
                 $syncColor = "Yellow"; "$behind commit(s) behind — pull needed"
             } else {
                 $syncColor = "Green";  "up to date"
             }
Write-Token "$syncLabel`n" $syncColor

# ── Repo stats ────────────────────────────────────────────────────────────────
Write-Token "  Commits  " "DarkGray"
Write-Token "$totalCommits total" "White"
if ($firstCommitDate) { Write-Token "  · started $firstCommitDate" "DarkGray" }
Write-Host ""

if ($latestTag) {
    Write-Token "  Tag      " "DarkGray"
    Write-Token "$($Icons.Tag) $latestTag" "Magenta"
    if ($totalTags -gt 1) { Write-Token "  ($totalTags tags total)" "DarkGray" }
    Write-Host ""
}

# ── Branches ──────────────────────────────────────────────────────────────────
Write-Section "BRANCHES"
foreach ($b in $allBranches) {
    $cleanB = $b.Trim()
    if ($cleanB -eq $branch) {
        Write-Token "    $($Icons.Head) $cleanB  (current)`n" "Yellow"
    } else {
        $isMerged = $mergedBranches -contains $cleanB
        if ($isMerged) {
            Write-Token "    $($Icons.Commit) $cleanB`n" "DarkGray"
        } else {
            Write-Token "    $($Icons.Commit) $cleanB  " "White"
            Write-Token "[unmerged]`n" "Red"
        }
    }
}

# ── Recent commits ────────────────────────────────────────────────────────────
Write-Section "LAST $Commits COMMITS"
foreach ($line in $logLines) {
    if (-not $line -or $line -notmatch '\|') { continue }
    $parts  = $line -split '\|', 5
    $hash   = $parts[0].Trim()
    $msg    = $parts[1].Trim()
    $author = $parts[2].Trim()
    $age    = $parts[3].Trim()
    $refs   = $parts[4].Trim()

    $msg = if ($msg.Length -gt 48) { $msg.Substring(0, 45) + "..." } else { $msg }

    $decoration = ""
    if ($refs -match 'HEAD')  { $decoration += " HEAD"          }
    if ($refs -match 'tag:')  { $decoration += " $($Icons.Tag)" }

    Write-Token "    $($Icons.Commit) " "DarkGray"
    Write-Token "$hash " "Yellow"
    Write-Token "$msg" "White"
    if ($decoration) { Write-Token $decoration "Magenta" }
    Write-Host ""
    Write-Token "          $author" "DarkGray"
    Write-Token "  ·  $age`n" "DarkGray"
}

# ── Working tree ──────────────────────────────────────────────────────────────
Write-Section "WORKING TREE"

if ($isDirty -and ($linesAdded -gt 0 -or $linesDeleted -gt 0)) {
    Write-Token "    Volume   " "DarkGray"
    if ($linesAdded   -gt 0) { Write-Token "+$linesAdded " "Green" }
    if ($linesDeleted -gt 0) { Write-Token "-$linesDeleted" "Red"  }
    Write-Host ""
}

$fileGroups = @(
    @{ Label = "Staged    "; Files = $staged;    Color = "Green"   },
    @{ Label = "Modified  "; Files = $modified;  Color = "Yellow"  },
    @{ Label = "Untracked "; Files = $untracked; Color = "DarkGray" }
)
$hasFiles = $false
foreach ($group in $fileGroups) {
    $count = $group.Files.Count
    if ($count -gt 0) {
        $hasFiles    = $true
        $displayFiles = $group.Files | Select-Object -First 5
        foreach ($fileLine in $displayFiles) {
            $fname = $fileLine.Substring(3).Trim()
            Write-Token "    $($group.Label)" "DarkGray"
            Write-Token "$fname`n" $group.Color
        }
        if ($count -gt 5) {
            Write-Token "    ... and $($count - 5) more $($group.Label.Trim().ToLower()) file(s)`n" "DarkGray"
        }
    }
}
if (-not $hasFiles) {
    Write-Token "    Working tree clean`n" "Green"
}

# ── Stashes ───────────────────────────────────────────────────────────────────
if ($stashList.Count -gt 0) {
    Write-Section "STASHES  ($($stashList.Count))"
    if ($Stashes) {
        foreach ($s in $stashList) {
            Write-Token "    $($Icons.Stash) $s`n" "DarkGray"
        }
    } else {
        Write-Token "    $($stashList.Count) stash(es) saved  " "DarkGray"
        Write-Token "(use -Stashes to expand)`n" "DarkGray"
    }
}

# ── Contributors ──────────────────────────────────────────────────────────────
if ($contributors.Count -gt 0) {
    $topN = [Math]::Min(3, $contributors.Count)
    Write-Section "TOP $topN CONTRIBUTORS"
    for ($i = 0; $i -lt $topN; $i++) {
        $c      = $contributors[$i].Trim() -split '\s+', 2
        $count  = $c[0]
        $author = if ($c.Count -gt 1) { $c[1] } else { "unknown" }
        Write-Token "    $($i + 1).  " "DarkGray"
        Write-Token ($author.PadRight(28)) "White"
        Write-Token "$count commits`n" "DarkGray"
    }
}

Write-Host ""