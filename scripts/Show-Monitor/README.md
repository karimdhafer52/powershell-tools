# smon — AI Workload Resource Monitor

A terminal-native Task Manager replacement for developers running heavy local workloads.
Displays live progress bars and top-5 process consumers for CPU, RAM, GPU, and Disk — with Docker container names resolved automatically.

```
  ╔══════════════════════════════════════════════════════════════════╗
  ║   smon  ·  AI Workload Resource Monitor                         ║
  ║   Sun 01-Jun-2025  14:32:07                                     ║
  ╚══════════════════════════════════════════════════════════════════╝

  ╭──────────────────────────────────────────────────────────────────╮
  │ CPU  Processor                                                   │
  ├──────────────────────────────────────────────────────────────────┤
  │ ████████████████░░░░░░░░░░░░   57%  57.3% used  (16 logical cores)│
  ├──────────────────────────────────────────────────────────────────┤
  │  Top 5 CPU consumers                                            │
  │  1. ▸ ollama_llama3          1842.3 s CPU                       │
  │  2. ▸ python                  934.1 s CPU                       │
  │  3. ▸ my-agent [docker]       621.8 s CPU  [docker]             │
  │  4. ▸ node                    204.5 s CPU                       │
  │  5. ▸ Code                    118.2 s CPU                       │
  ╰──────────────────────────────────────────────────────────────────╯
```

---

## Requirements

- Windows 10/11
- PowerShell 5.1+ (built-in) or PowerShell 7+
- `nvidia-smi` on PATH for full GPU metrics (optional — falls back to WMI)
- Docker Desktop running for container name resolution (optional)

---

## Installation

1. Copy `Show-Monitor.ps1` into `scripts\Show-Monitor\` and `smon.cmd` into `bin\` under your tools folder, e.g. `C:\tools\PowerShell\`:

```
C:\tools\PowerShell\
├── bin\
│   └── smon.cmd
└── scripts\
    └── Show-Monitor\
        └── Show-Monitor.ps1
```

2. Ensure `bin\` is on your system PATH (see the [repo-level README](../../README.md) for the one-time setup command).

3. Restart your terminal. `smon` is now available everywhere.

---

## Usage

```
smon [[-Watch]] [-Interval <n>] [-Top <n>] [-NoBanner] [-NoGpu] [-NoDocker] [-Export <file>]
```

| Flag | Default | Description |
|---|---|---|
| `-Watch` | off | Continuously refresh metrics in a live loop |
| `-Interval` | `3` | Refresh interval in seconds (only with `-Watch`) |
| `-Top` | `5` | Number of top consumers shown per section |
| `-NoBanner` | off | Suppress the ASCII title header |
| `-NoGpu` | off | Skip GPU detection entirely (faster on CPU-only machines) |
| `-NoDocker` | off | Skip Docker PID-to-name resolution |
| `-Export` | — | Write a plain-text snapshot to a file (one-shot only) |

---

## Examples

```powershell
smon
smon -Watch
smon -Watch -Interval 5 -Top 3
smon -NoGpu -NoDocker
smon -Export snapshot.txt
smon -?
```

---

## Sections

### CPU
Overall processor load sampled across two measurements 500 ms apart for accuracy. Top consumers are ranked by accumulated CPU time. Processes whose PID matches a running Docker container are labelled `[docker]` with the container name.

### RAM
Used vs. total physical memory via `Win32_OperatingSystem`. Top consumers ranked by working set size. Docker containers resolved the same way as CPU.

### GPU
Full metrics (core %, VRAM used/total) via `nvidia-smi --query-gpu` when available. Falls back gracefully to `Win32_VideoController` (adapter RAM only) with an install hint. Per-process GPU stats via `nvidia-smi pmon`.

### Disk
Two-section output: live I/O throughput (read/write bytes/sec, sampled over 800 ms) and total capacity across all fixed drives. Top consumers ranked by lifetime I/O transfer bytes via `Get-Process`.

---

## Help

Every flag is documented. Run `smon -?` for quick help, or:

```powershell
Get-Help C:\tools\PowerShell\scripts\Show-Monitor\Show-Monitor.ps1 -Full
Get-Help C:\tools\PowerShell\scripts\Show-Monitor\Show-Monitor.ps1 -Examples
```

---

## Performance Notes

The only intentional delays are two metric-sampling windows (500 ms for CPU, 800 ms for Disk I/O) required to measure a *rate* rather than a point-in-time value. All other queries are single CIM calls. Total cold startup is approximately 1.5–2 seconds. Use `-NoGpu` and `-NoDocker` to eliminate all external process calls and reduce startup to under 1 second.