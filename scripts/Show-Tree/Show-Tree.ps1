<#
.SYNOPSIS
    Displays a directory tree structure in the terminal.

.DESCRIPTION
    Show-Tree prints a visual directory tree for a given path, mimicking the
    Linux `tree` command. Supports depth limiting, .gitignore awareness,
    directory-only mode, and UTF-8 Unicode box-drawing characters.

.PARAMETER Path
    The root directory to display. Defaults to the current directory.

.PARAMETER Depth
    Maximum depth of recursion. Defaults to 3.

.PARAMETER Ignore
    Array of names to always exclude. Defaults to @('.git').

.PARAMETER GitIgnore
    If set, reads and respects the .gitignore file found in the root Path.

.PARAMETER DirectoriesOnly
    If set, only directories are shown; files are hidden.

.PARAMETER Export
    If provided, writes the tree output to this file path instead of stdout.

.EXAMPLE
    .\Show-Tree.ps1
    Shows the tree of the current directory up to depth 3.

.EXAMPLE
    .\Show-Tree.ps1 -Path C:\Projects\MyApp -Depth 5 -GitIgnore
    Shows a depth-5 tree of MyApp, respecting .gitignore.

.EXAMPLE
    .\Show-Tree.ps1 -DirectoriesOnly -Depth 2
    Shows only the directory skeleton, no files.

.EXAMPLE
    .\Show-Tree.ps1 -Export tree.txt
    Exports the tree to tree.txt.

.LINK
    https://gist.github.com/karimdhafer52/20e6df87b4bd11c249556e87b4ae1689
#>

[CmdletBinding()]
param(
    [string]$Path = ".",
    [int]$Depth = 3,
    [string[]]$Ignore = @(".git"),
    [switch]$GitIgnore,
    [switch]$DirectoriesOnly,
    [string]$Export
)

# ----------------------------
# Encoding safety
# ----------------------------
cmd /c chcp 65001 > $null
[System.Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# ----------------------------
# Build box chars from code points (avoids source-encoding issues)
# ----------------------------
$UseUnicode = $true
try {
    $test = [System.Text.Encoding]::UTF8.GetString([byte[]](0xE2, 0x94, 0x82))
    [System.Console]::OutputEncoding.GetBytes($test) | Out-Null
} catch {
    $UseUnicode = $false
}

if ($UseUnicode) {
    $TreeChars = @{
        Vertical    = [char]0x2502                                 # │
        Branch      = [char]0x251C + [char]0x2500 + [char]0x2500  # ├──
        Corner      = [char]0x2514 + [char]0x2500 + [char]0x2500  # └──
        Indent      = [char]0x2502 + "   "                         # │   (child of non-last item)
        BlankIndent = "    "                                        #     (child of last item)
        Space       = "   "
    }
} else {
    $TreeChars = @{
        Vertical    = "|"
        Branch      = "+--"
        Corner      = "`--"
        Indent      = "|   "
        BlankIndent = "    "
        Space       = "   "
    }
}

# ----------------------------
# Load .gitignore patterns
# ----------------------------
$gitIgnorePatterns = @()
if ($GitIgnore) {
    $gitIgnoreFile = Join-Path $Path ".gitignore"
    if (Test-Path $gitIgnoreFile) {
        $gitIgnorePatterns = Get-Content $gitIgnoreFile |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith("#") }
    }
}

function Test-GitIgnoreMatch {
    param([string]$Name, [string]$FullPath)
    foreach ($pattern in $gitIgnorePatterns) {
        if ($pattern.EndsWith("/")) {
            $dirPattern = $pattern.TrimEnd("/")
            if ($Name -eq $dirPattern) { return $true }
        }
        if ($pattern -like "*`**" -or $pattern -like "*?*") {
            $regex = [WildcardPattern]::Escape($pattern)
            $regex = $regex -replace "\\\*", ".*"
            $regex = $regex -replace "\\\?", "."
            if ($Name -match "^$regex$") { return $true }
        }
        if ($Name -eq $pattern) { return $true }
    }
    return $false
}

function Show-Tree {
    param(
        [string]$Path,
        [int]$Depth,
        [int]$CurrentDepth = 0,
        [string]$Prefix = ""        # carries the exact indent string from parent levels
    )
    if ($CurrentDepth -ge $Depth) { return @() }

    $items = Get-ChildItem -LiteralPath $Path -Force |
        Where-Object {
            $name = $_.Name
            -not ($Ignore -contains $name) -and
            -not (Test-GitIgnoreMatch -Name $name -FullPath $_.FullName) -and
            (-not $DirectoriesOnly -or $_.PSIsContainer)
        } |
        Sort-Object -Property PSIsContainer, Name -Descending

    $results = @()
    for ($i = 0; $i -lt $items.Count; $i++) {
        $item   = $items[$i]
        $isLast = ($i -eq $items.Count - 1)

        # Last item gets └──, all others get ├──
        $connector   = if ($isLast) { $TreeChars.Corner  } else { $TreeChars.Branch  }
        # Indent passed to children: blank space under └──, continuing │ under ├──
        $childPrefix = if ($isLast) { $Prefix + $TreeChars.BlankIndent } else { $Prefix + $TreeChars.Indent }

        # Append "/" to directory names
        $displayName = if ($item.PSIsContainer) { "$($item.Name)/" } else { $item.Name }
        $results += "$Prefix$connector $displayName"

        if ($item.PSIsContainer) {
            $results += Show-Tree -Path $item.FullName -Depth $Depth -CurrentDepth ($CurrentDepth + 1) -Prefix $childPrefix
        }
    }
    return $results
}

$output = @(Resolve-Path $Path) + @(Show-Tree -Path $Path -Depth $Depth)

if ($Export) {
    $output | Out-File -Encoding utf8 -FilePath $Export
    Write-Host "Tree exported to $Export"
} else {
    $output
}