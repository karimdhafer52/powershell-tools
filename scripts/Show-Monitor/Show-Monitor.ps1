<#
.SYNOPSIS
    Real-time system resource monitor for AI/automation workloads.

.DESCRIPTION
    Show-Monitor is a terminal-native Task Manager replacement designed for
    developers running heavy local workloads: Docker containers, local LLMs,
    vector databases, and autonomous AI agents.

    Displays live progress bars and top-5 process consumers for:
      - CPU  (overall load + per-process)
      - RAM  (used/total + top consumers, Docker names resolved)
      - GPU  (VRAM + core utilisation via nvidia-smi or WMI fallback)
      - Disk (I/O throughput + capacity + top I/O processes)

.PARAMETER Watch
    Continuously refresh metrics every <n> seconds (default 3).
    Press Q or Ctrl-C to exit.

.PARAMETER Interval
    Refresh interval in seconds when -Watch is active. Default: 3.

.PARAMETER Top
    Number of top consumers to show per section. Default: 5.

.PARAMETER NoBanner
    Suppress the ASCII title banner.

.PARAMETER NoGpu
    Skip GPU detection entirely (faster startup on CPU-only machines).

.PARAMETER NoDocker
    Skip Docker PID-to-name resolution.

.PARAMETER Export
    Path to write a plain-text snapshot (one-shot only, no Watch).

.EXAMPLE
    smon
    One-shot snapshot of all hardware metrics.

.EXAMPLE
    smon -Watch
    Live-updating dashboard, refreshes every 3 seconds.

.EXAMPLE
    smon -Watch -Interval 5 -Top 3
    Live dashboard, 5-second refresh, 3 consumers per section.

.EXAMPLE
    smon -Export report.txt
    Capture a plain-text snapshot to file.

.EXAMPLE
    smon -NoGpu -NoDocker
    Fastest possible snapshot, no external tool calls.

.LINK
    https://gist.github.com/karimdhafer52/GIST_ID
#>

[CmdletBinding()]
param(
    [switch]$Watch,
    [int]$Interval    = 3,
    [int]$Top         = 5,
    [switch]$NoBanner,
    [switch]$NoGpu,
    [switch]$NoDocker,
    [string]$Export
)

# ===========================================================================
#  ENCODING SAFETY  (mirrors Show-Tree.ps1 pattern)
# ===========================================================================
cmd /c chcp 65001 > $null 2>&1
[System.Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$UseUnicode = $true
try {
    $test = [System.Text.Encoding]::UTF8.GetString([byte[]](0xE2, 0x94, 0x82))
    [System.Console]::OutputEncoding.GetBytes($test) | Out-Null
} catch { $UseUnicode = $false }

# ===========================================================================
#  BOX / BAR CHARACTERS
# ===========================================================================
if ($UseUnicode) {
    $B = @{
        TL = [char]0x256D; TR = [char]0x256E          # ╭ ╮
        BL = [char]0x2570; BR = [char]0x256F          # ╰ ╯
        H  = [char]0x2500                              # ─
        V  = [char]0x2502                              # │
        LT = [char]0x251C; RT = [char]0x2524          # ├ ┤
        Filled = [char]0x2588                          # █
        Light  = [char]0x2591                          # ░
        Bullet = [char]0x25B8                          # ▸
        Warn   = [char]0x26A0                          # ⚠
        OK     = [char]0x2713                          # ✓
    }
} else {
    $B = @{
        TL = "+"; TR = "+"; BL = "+"; BR = "+"
        H  = "-"; V  = "|"; LT = "+"; RT = "+"
        Filled = "#"; Light = "."; Bullet = ">"; Warn = "!"; OK = "v"
    }
}

# ===========================================================================
#  COLOUR PALETTE
# ===========================================================================
$C = @{
    Title    = "Cyan"
    Header   = "White"
    Bar      = "Green"
    BarWarn  = "Yellow"
    BarCrit  = "Red"
    Dim      = "DarkGray"
    Accent   = "DarkCyan"
    Value    = "White"
    Label    = "DarkGray"
    Alert    = "Yellow"
    Error    = "Red"
    Ok       = "Green"
    DockerPx = "Magenta"
    GpuPx    = "Blue"
}

# ===========================================================================
#  HELPER: FORMAT BYTES
# ===========================================================================
function Format-Bytes {
    param([long]$Bytes)
    if     ($Bytes -ge 1TB) { return "{0:N1} TB" -f ($Bytes / 1TB) }
    elseif ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    else                    { return "$Bytes B" }
}

# ===========================================================================
#  HELPER: PROGRESS BAR STRING
# ===========================================================================
function Get-BarString {
    param(
        [double]$Pct,           # 0–100
        [int]$Width = 28
    )
    $filled = [int][Math]::Round($Width * ($Pct / 100.0))
    $filled = [Math]::Max(0, [Math]::Min($Width, $filled))
    $empty  = $Width - $filled
    return ($B.Filled * $filled) + ($B.Light * $empty)
}

function Get-BarColor {
    param([double]$Pct)
    if ($Pct -ge 90) { return $C.BarCrit  }
    if ($Pct -ge 70) { return $C.BarWarn  }
    return $C.Bar
}

# ===========================================================================
#  HELPER: WRITE A METRIC SECTION
#  Renders:  header line, bar + readout, top-N process table
# ===========================================================================
function Write-Section {
    param(
        [string]   $Icon,
        [string]   $Title,
        [double]   $Pct,
        [string]   $Readout,        # e.g. "14.2 GB / 32 GB (44%)"
        [object[]] $Rows,           # @{ Name; Value; Tag }  Tag: 'docker','gpu',''
        [string]   $SubLabel = "Top $Top consumers",
        [string[]] $ExtraLines = @()
    )

    $bar      = Get-BarString -Pct $Pct
    $barColor = Get-BarColor  -Pct $Pct
    $pctStr   = "{0,3:N0}%" -f $Pct
    $lineW    = 68

    # ── Section header ──────────────────────────────────────────────────────
    Write-Host ""
    $hLine = $B.H * ($lineW - 2)
    Write-Host "  $($B.TL)$hLine$($B.TR)" -ForegroundColor $C.Dim
    Write-Host "  $($B.V) " -ForegroundColor $C.Dim -NoNewline
    Write-Host "$Icon  $Title" -ForegroundColor $C.Header -NoNewline
    $pad = $lineW - 4 - $Icon.Length - $Title.Length - 2
    Write-Host (" " * [Math]::Max(0,$pad)) -NoNewline
    Write-Host " $($B.V)" -ForegroundColor $C.Dim
    Write-Host "  $($B.LT)$hLine$($B.RT)" -ForegroundColor $C.Dim

    # ── Progress bar row ────────────────────────────────────────────────────
    Write-Host "  $($B.V) " -ForegroundColor $C.Dim -NoNewline
    Write-Host $bar -ForegroundColor $barColor -NoNewline
    Write-Host "  " -NoNewline
    Write-Host $pctStr -ForegroundColor $barColor -NoNewline
    Write-Host "  " -NoNewline
    Write-Host $Readout -ForegroundColor $C.Value -NoNewline
    $readPad = $lineW - 4 - 28 - 2 - 5 - 2 - $Readout.Length
    Write-Host (" " * [Math]::Max(0,$readPad)) -NoNewline
    Write-Host " $($B.V)" -ForegroundColor $C.Dim

    # ── Extra info lines (e.g. disk R/W speeds) ─────────────────────────────
    foreach ($el in $ExtraLines) {
        Write-Host "  $($B.V)  " -ForegroundColor $C.Dim -NoNewline
        Write-Host $el -ForegroundColor $C.Accent -NoNewline
        $ePad = $lineW - 4 - $el.Length
        Write-Host (" " * [Math]::Max(0,$ePad)) -NoNewline
        Write-Host " $($B.V)" -ForegroundColor $C.Dim
    }

    # ── Divider + sub-label ─────────────────────────────────────────────────
    Write-Host "  $($B.LT)$hLine$($B.RT)" -ForegroundColor $C.Dim
    Write-Host "  $($B.V)  " -ForegroundColor $C.Dim -NoNewline
    Write-Host $SubLabel -ForegroundColor $C.Label -NoNewline
    $slPad = $lineW - 4 - $SubLabel.Length
    Write-Host (" " * [Math]::Max(0,$slPad)) -NoNewline
    Write-Host " $($B.V)" -ForegroundColor $C.Dim

    # ── Process rows ────────────────────────────────────────────────────────
    if ($Rows -and $Rows.Count -gt 0) {
        $rank = 1
        foreach ($row in $Rows | Select-Object -First $Top) {
            $tagColor = switch ($row.Tag) {
                "docker" { $C.DockerPx }
                "gpu"    { $C.GpuPx    }
                default  { $C.Accent   }
            }
            $rankStr = "  {0}." -f $rank
            $nameStr = if ($row.Name.Length -gt 38) { $row.Name.Substring(0,35) + "..." } else { $row.Name }
            $valStr  = $row.Value
            $tagStr  = if ($row.Tag) { "[$($row.Tag)]" } else { "" }

            $innerW  = $lineW - 2
            $nameLen = $nameStr.Length
            $valLen  = $valStr.Length
            $tagLen  = $tagStr.Length
            $gapLen  = $innerW - 4 - $rankStr.Length - $nameLen - $valLen - $tagLen - 2
            $gapLen  = [Math]::Max(1, $gapLen)

            Write-Host "  $($B.V)" -ForegroundColor $C.Dim -NoNewline
            Write-Host $rankStr -ForegroundColor $C.Dim -NoNewline
            Write-Host " $($B.Bullet) " -ForegroundColor $C.Dim -NoNewline
            Write-Host $nameStr -ForegroundColor $C.Header -NoNewline
            Write-Host (" " * $gapLen) -NoNewline
            Write-Host $valStr -ForegroundColor $barColor -NoNewline
            if ($tagStr) {
                Write-Host " " -NoNewline
                Write-Host $tagStr -ForegroundColor $tagColor -NoNewline
            }
            Write-Host " $($B.V)" -ForegroundColor $C.Dim
            $rank++
        }
    } else {
        Write-Host "  $($B.V)  " -ForegroundColor $C.Dim -NoNewline
        Write-Host "  (no processes found)" -ForegroundColor $C.Label -NoNewline
        $noPad = $lineW - 4 - 22
        Write-Host (" " * [Math]::Max(0,$noPad)) -NoNewline
        Write-Host " $($B.V)" -ForegroundColor $C.Dim
    }

    # ── Section footer ───────────────────────────────────────────────────────
    Write-Host "  $($B.BL)$hLine$($B.BR)" -ForegroundColor $C.Dim
}

# ===========================================================================
#  DOCKER: PID → CONTAINER NAME MAP
# ===========================================================================
function Get-DockerNameMap {
    $map = @{}
    if ($NoDocker) { return $map }
    try {
        $dockerExe = Get-Command docker -ErrorAction SilentlyContinue
        if (-not $dockerExe) { return $map }
        $lines = docker ps --no-trunc --format "{{.ID}}\t{{.Names}}" 2>$null
        foreach ($line in $lines) {
            $parts = $line -split "`t"
            if ($parts.Count -lt 2) { continue }
            $id    = $parts[0].Substring(0, [Math]::Min(12, $parts[0].Length))
            $name  = $parts[1]
            # inspect to get host PID of the container's top process
            $pid_ = docker inspect --format "{{.State.Pid}}" $id 2>$null
            if ($pid_ -match '^\d+$' -and [int]$pid_ -gt 0) {
                $map[[int]$pid_] = $name
            }
        }
    } catch {}
    return $map
}

# ===========================================================================
#  CPU METRICS
# ===========================================================================
function Get-CpuMetrics {
    param([hashtable]$DockerMap)

    # Overall CPU % — two quick samples 500 ms apart for accuracy
    $cpu1 = Get-CimInstance -ClassName Win32_Processor -Property LoadPercentage
    Start-Sleep -Milliseconds 500
    $cpu2 = Get-CimInstance -ClassName Win32_Processor -Property LoadPercentage

    $cpuPct = ($cpu2 | Measure-Object -Property LoadPercentage -Average).Average
    $coreCount = ($cpu1 | Measure-Object).Count

    # Top processes by CPU
    # Use Get-Process with CPU time delta for a real % estimate
    $procs = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CPU -gt 0 } |
        Sort-Object CPU -Descending |
        Select-Object -First ($Top * 2)

    $rows = foreach ($p in $procs | Select-Object -First $Top) {
        $name  = $p.Name
        $tag   = if ($DockerMap.ContainsKey($p.Id)) { "docker" } else { "" }
        $dname = if ($tag -eq "docker") { $DockerMap[$p.Id] } else { $name }
        [PSCustomObject]@{
            Name  = $dname
            Value = "{0,6:N1} s CPU" -f $p.CPU
            Tag   = $tag
        }
    }

    $coreStr = if ($coreCount -gt 1) { "($coreCount logical cores)" } else { "" }

    [PSCustomObject]@{
        Pct     = [Math]::Round($cpuPct, 1)
        Readout = "{0:N1}% used  $coreStr" -f $cpuPct
        Rows    = $rows
    }
}

# ===========================================================================
#  RAM METRICS
# ===========================================================================
function Get-RamMetrics {
    param([hashtable]$DockerMap)

    $os     = Get-CimInstance -ClassName Win32_OperatingSystem -Property TotalVisibleMemorySize, FreePhysicalMemory
    $totalB = $os.TotalVisibleMemorySize * 1KB
    $freeB  = $os.FreePhysicalMemory     * 1KB
    $usedB  = $totalB - $freeB
    $pct    = ($usedB / $totalB) * 100

    $procs  = Get-Process -ErrorAction SilentlyContinue |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First ($Top * 2)

    $rows = foreach ($p in $procs | Select-Object -First $Top) {
        $tag   = if ($DockerMap.ContainsKey($p.Id)) { "docker" } else { "" }
        $dname = if ($tag -eq "docker") { $DockerMap[$p.Id] } else { $p.Name }
        [PSCustomObject]@{
            Name  = $dname
            Value = Format-Bytes $p.WorkingSet64
            Tag   = $tag
        }
    }

    [PSCustomObject]@{
        Pct     = [Math]::Round($pct, 1)
        Readout = "$(Format-Bytes $usedB) / $(Format-Bytes $totalB)  ($([Math]::Round($pct,0))%)"
        Rows    = $rows
    }
}

# ===========================================================================
#  GPU METRICS  (nvidia-smi preferred; WMI fallback)
# ===========================================================================
function Get-GpuMetrics {
    param([hashtable]$DockerMap)

    if ($NoGpu) {
        return [PSCustomObject]@{ Available = $false }
    }

    # ── Try nvidia-smi ────────────────────────────────────────────────────
    $nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($nvidiaSmi) {
        try {
            # GPU utilisation + memory
            $raw = nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,name `
                              --format=csv,noheader,nounits 2>$null | Select-Object -First 1

            if ($raw) {
                $parts    = $raw -split ",\s*"
                $corePct  = [double]$parts[0].Trim()
                $vramUsed = [long]($parts[1].Trim()) * 1MB    # nvidia-smi gives MiB
                $vramTotal= [long]($parts[2].Trim()) * 1MB
                $gpuName  = $parts[3].Trim()
                $vramPct  = ($vramUsed / $vramTotal) * 100

                # Top processes via nvidia-smi pmon
                $pmonRaw  = nvidia-smi pmon -c 1 -s u 2>$null
                $gpuRows  = @()
                if ($pmonRaw) {
                    foreach ($line in $pmonRaw | Select-Object -Skip 2) {
                        if ($line -match '^\s*(\d+)\s+\S+\s+(\S+)\s+(\d+)') {
                            $gpuPid  = [int]$Matches[1]
                            $smUtil  = $Matches[3]
                            try { $pName = (Get-Process -Id $gpuPid -ErrorAction Stop).Name } catch { $pName = "PID $gpuPid" }
                            $tag    = if ($DockerMap.ContainsKey($gpuPid)) { "docker" } else { "gpu" }
                            $dname  = if ($tag -eq "docker") { $DockerMap[$gpuPid] } else { $pName }
                            $gpuRows += [PSCustomObject]@{ Name = $dname; Value = "$smUtil% SM"; Tag = $tag }
                        }
                    }
                }
                if ($gpuRows.Count -eq 0) {
                    $gpuRows = @([PSCustomObject]@{ Name = "No active GPU workloads"; Value = ""; Tag = "" })
                }

                return [PSCustomObject]@{
                    Available  = $true
                    Source     = "nvidia-smi"
                    GpuName    = $gpuName
                    CorePct    = [Math]::Round($corePct, 1)
                    VramPct    = [Math]::Round($vramPct, 1)
                    CoreReadout= "{0:N1}% core  |  VRAM: $(Format-Bytes $vramUsed) / $(Format-Bytes $vramTotal)  ($([Math]::Round($vramPct,0))%)" -f $corePct
                    Rows       = $gpuRows
                }
            }
        } catch {}
    }

    # ── WMI fallback (integrated / any GPU) ──────────────────────────────
    try {
        $gpuWmi = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
                    Select-Object -First 1
        if ($gpuWmi) {
            $adapterRam = if ($gpuWmi.AdapterRAM) { $gpuWmi.AdapterRAM } else { 0 }
            $readout    = "$(Format-Bytes $adapterRam) adapter RAM  (utilisation N/A — install nvidia-smi for full metrics)"
            return [PSCustomObject]@{
                Available   = $true
                Source      = "WMI"
                GpuName     = $gpuWmi.Name
                CorePct     = 0
                VramPct     = 0
                CoreReadout = $readout
                Rows        = @([PSCustomObject]@{ Name = "Install nvidia-smi for process-level GPU data"; Value = ""; Tag = "" })
            }
        }
    } catch {}

    return [PSCustomObject]@{ Available = $false }
}

# ===========================================================================
#  DISK METRICS  (capacity + I/O throughput)
# ===========================================================================
function Get-DiskMetrics {
    param([hashtable]$DockerMap)

    # Capacity via Win32_LogicalDisk
    $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    $totalB = ($disks | Measure-Object -Property Size      -Sum).Sum
    $freeB  = ($disks | Measure-Object -Property FreeSpace -Sum).Sum
    $usedB  = $totalB - $freeB
    $pct    = if ($totalB -gt 0) { ($usedB / $totalB) * 100 } else { 0 }

    # I/O throughput — two samples 800 ms apart
    $io1    = Get-CimInstance -ClassName Win32_PerfRawData_PerfDisk_PhysicalDisk -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq "_Total" }
    $ts1    = [datetime]::Now
    Start-Sleep -Milliseconds 800
    $io2    = Get-CimInstance -ClassName Win32_PerfRawData_PerfDisk_PhysicalDisk -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq "_Total" }
    $ts2    = [datetime]::Now

    $readBps  = 0; $writeBps = 0
    if ($io1 -and $io2) {
        $dt       = ($ts2 - $ts1).TotalSeconds
        $readBps  = if ($dt -gt 0) { ($io2.DiskReadBytesPerSec  - $io1.DiskReadBytesPerSec)  / $dt } else { 0 }
        $writeBps = if ($dt -gt 0) { ($io2.DiskWriteBytesPerSec - $io1.DiskWriteBytesPerSec) / $dt } else { 0 }
        $readBps  = [Math]::Max(0, $readBps)
        $writeBps = [Math]::Max(0, $writeBps)
    }

    # Top processes by I/O — use Get-Process I/O counters
    $procs = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ReadOperationCount -gt 0 -or $_.WriteOperationCount -gt 0 } |
        Sort-Object { $_.ReadTransferCount + $_.WriteTransferCount } -Descending |
        Select-Object -First ($Top * 2)

    $rows = foreach ($p in $procs | Select-Object -First $Top) {
        $tag   = if ($DockerMap.ContainsKey($p.Id)) { "docker" } else { "" }
        $dname = if ($tag -eq "docker") { $DockerMap[$p.Id] } else { $p.Name }
        $ioTotal = $p.ReadTransferCount + $p.WriteTransferCount
        [PSCustomObject]@{
            Name  = $dname
            Value = Format-Bytes $ioTotal
            Tag   = $tag
        }
    }

    $driveList = ($disks | ForEach-Object { $_.DeviceID }) -join "  "
    $driveInfo = if ($driveList) { "Drives: $driveList" } else { "" }

    [PSCustomObject]@{
        Pct        = [Math]::Round($pct, 1)
        Readout    = "$(Format-Bytes $usedB) / $(Format-Bytes $totalB)  ($([Math]::Round($pct,0))%)"
        ReadBps    = $readBps
        WriteBps   = $writeBps
        ExtraLines = @(
            "  Read:  $('{0,-10}' -f (Format-Bytes $readBps))/s    Write: $(Format-Bytes $writeBps)/s"
            if ($driveInfo) { "  $driveInfo" }
        ) | Where-Object { $_ }
        Rows       = $rows
    }
}

# ===========================================================================
#  BANNER
# ===========================================================================
function Write-Banner {
    if ($NoBanner) { return }
    $ts = Get-Date -Format "ddd dd-MMM-yyyy  HH:mm:ss"
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║   " -ForegroundColor Cyan -NoNewline
    Write-Host "smon" -ForegroundColor White -NoNewline
    Write-Host "  ·  AI Workload Resource Monitor" -ForegroundColor DarkCyan -NoNewline
    Write-Host "                              ║" -ForegroundColor Cyan
    Write-Host "  ║   " -ForegroundColor Cyan -NoNewline
    Write-Host $ts -ForegroundColor DarkGray -NoNewline
    $datePad = 52 - $ts.Length
    Write-Host (" " * [Math]::Max(0,$datePad)) -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

# ===========================================================================
#  FOOTER
# ===========================================================================
function Write-Footer {
    $hint = if ($Watch) { "  Press Q to quit  ·  refreshing every ${Interval}s" }
             else        { "  Run 'smon -Watch' for live updates  ·  'smon -?' for help" }
    Write-Host ""
    Write-Host $hint -ForegroundColor $C.Dim
    Write-Host ""
}

# ===========================================================================
#  CORE SNAPSHOT  — collect all metrics and render
# ===========================================================================
function Invoke-Snapshot {
    param([switch]$ClearFirst)

    if ($ClearFirst) { Clear-Host }
    Write-Banner

    # Resolve Docker PIDs once per snapshot (fast if daemon not running)
    $dockerMap = Get-DockerNameMap

    # Collect all metrics
    $cpu  = Get-CpuMetrics  -DockerMap $dockerMap
    $ram  = Get-RamMetrics  -DockerMap $dockerMap
    $gpu  = Get-GpuMetrics  -DockerMap $dockerMap
    $disk = Get-DiskMetrics -DockerMap $dockerMap

    # ── CPU ────────────────────────────────────────────────────────────────
    Write-Section `
        -Icon     "CPU" `
        -Title    "Processor" `
        -Pct      $cpu.Pct `
        -Readout  $cpu.Readout `
        -Rows     $cpu.Rows `
        -SubLabel "Top $Top CPU consumers"

    # ── RAM ────────────────────────────────────────────────────────────────
    Write-Section `
        -Icon     "RAM" `
        -Title    "Memory" `
        -Pct      $ram.Pct `
        -Readout  $ram.Readout `
        -Rows     $ram.Rows `
        -SubLabel "Top $Top memory consumers"

    # ── GPU ────────────────────────────────────────────────────────────────
    if ($gpu.Available) {
        $gpuTitle = "GPU  ·  $($gpu.GpuName)  [$($gpu.Source)]"
        Write-Section `
            -Icon     "GPU" `
            -Title    $gpuTitle `
            -Pct      $gpu.CorePct `
            -Readout  $gpu.CoreReadout `
            -Rows     $gpu.Rows `
            -SubLabel "Top $Top GPU workloads"
    } else {
        Write-Host ""
        Write-Host "  (GPU section skipped — no GPU detected or -NoGpu flag set)" -ForegroundColor $C.Dim
    }

    # ── DISK ───────────────────────────────────────────────────────────────
    Write-Section `
        -Icon       "DSK" `
        -Title      "Storage  ·  I/O + Capacity" `
        -Pct        $disk.Pct `
        -Readout    $disk.Readout `
        -Rows       $disk.Rows `
        -ExtraLines $disk.ExtraLines `
        -SubLabel   "Top $Top disk I/O consumers (lifetime)"

    Write-Footer
}

# ===========================================================================
#  EXPORT (plain text via transcript)
# ===========================================================================
function Invoke-Export {
    $tmpTranscript = [System.IO.Path]::GetTempFileName()
    Start-Transcript -Path $tmpTranscript -Force | Out-Null
    Invoke-Snapshot
    Stop-Transcript | Out-Null
    # Strip ANSI escapes from transcript
    $raw     = Get-Content $tmpTranscript -Raw
    $clean   = $raw -replace '\x1b\[[0-9;]*[mK]', ''
    $clean   | Out-File -FilePath $Export -Encoding utf8 -Force
    Remove-Item $tmpTranscript -Force -ErrorAction SilentlyContinue
    Write-Host "  Snapshot exported to: $Export" -ForegroundColor $C.Ok
}

# ===========================================================================
#  WATCH LOOP
# ===========================================================================
function Invoke-Watch {
    # Hide cursor during refresh loop
    [System.Console]::CursorVisible = $false
    try {
        $first = $true
        while ($true) {
            Invoke-Snapshot -ClearFirst:(-not $first -or $true)
            $first = $false

            # Wait Interval seconds, checking for Q keypress each 100 ms
            $elapsed = 0
            while ($elapsed -lt ($Interval * 1000)) {
                if ([System.Console]::KeyAvailable) {
                    $key = [System.Console]::ReadKey($true)
                    if ($key.Key -eq [System.ConsoleKey]::Q) {
                        Write-Host "  Exiting smon." -ForegroundColor $C.Dim
                        return
                    }
                }
                Start-Sleep -Milliseconds 100
                $elapsed += 100
            }
        }
    } finally {
        [System.Console]::CursorVisible = $true
    }
}

# ===========================================================================
#  ENTRY POINT
# ===========================================================================
if ($Export) {
    Invoke-Export
} elseif ($Watch) {
    Invoke-Watch
} else {
    Invoke-Snapshot
}