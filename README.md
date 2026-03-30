# vitals

Ultra-lightweight system resource monitor written in Zig. Instantly shows CPU, memory, disk, and network status.

## Features

- **Fast startup**: First render completes in < 10ms
- **Lightweight**: < 0.1% CPU and < 5MB memory usage
- **Zero dependencies**: Uses only Linux `/proc` and macOS system APIs
- **3 display modes**: One-shot, mini, and watch

## Installation

### Homebrew (macOS & Linux)

```bash
brew tap AI1411/Vitals https://github.com/AI1411/Vitals
brew install ai1411/vitals/vitals
```

> **Note**: Use `ai1411/vitals/vitals` (not `vitals`) to avoid conflicts with an existing Homebrew cask of the same name.

### Build from source

Requires Zig 0.15.0 or later.

```bash
git clone https://github.com/AI1411/Vitals
cd Vitals
zig build -Doptimize=ReleaseSafe
```

The binary is generated at `zig-out/bin/vitals`.

```bash
cp zig-out/bin/vitals ~/.local/bin/
```

## Usage

### One-shot mode (`--once`)

Print CPU, memory, disk, and network info once and exit.

```bash
vitals --once
```

```
  CPU  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░  42%    MEM  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░  65%
  SWP  ▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   5%    LOAD 3.42 / 2.81 / 2.15

  /      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░  72%  187.0 GB free    eth0  ↓ 12.4 MB/s  ↑ 3.2 MB/s
  /home  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░  45%  530.0 GB free
```

### Mini mode (`--mini`)

Single-line output for tmux status bar or shell prompt.

```bash
vitals --mini
# CPU 42% | MEM 65% | DISK 72% | NET ↓12M ↑3M | LOAD 3.42
```

**tmux.conf integration:**

```
set -g status-right '#(vitals --mini)'
```

### Watch mode (`--watch`)

Real-time time-series graphs for CPU, memory, and network.

```bash
vitals --watch
```

```
vitals watch  (5m range)

CPU Usage (5m)  now: 42.3%
100% ┤
 80% ┤          ╭╮
 60% ┤    ╭─────╯╰──╮
 40% ┤────╯          ╰────────────────────
 20% ┤
  0% ┤
     └──────────────────────────────── now

Memory Usage (5m)  now: 65.1%
...

[q] quit  [+/-] time range  [space] pause  [r] reset
```

**Key bindings:**

| Key | Action |
|-----|--------|
| `q` / `Ctrl-C` | Quit |
| `space` | Pause / resume updates |
| `r` | Reset graph |
| `+` | Zoom in (shorter time range) |
| `-` | Zoom out (longer time range) |

**Time range:** 1–60 minutes (default: 5 minutes, adjustable in 60-second steps)

### JSON output (`--json`)

Output a snapshot in JSON format. Useful for integration with monitoring systems.

```bash
vitals --once --json
```

```json
{
  "timestamp_ms": 1711234567890,
  "cpu": {"usage_pct": 42.30, "cores": [45.10, 39.20, 50.80, 34.50]},
  "memory": {"usage_pct": 65.10, "total_kb": 32768000, "used_kb": 21319680, "available_kb": 11448320},
  "swap": {"usage_pct": 5.00, "total_kb": 8192000, "used_kb": 409600},
  "load": {"load1": 3.42, "load5": 2.81, "load15": 2.15},
  "disk": [
    {"mount": "/", "usage_pct": 72.00, "total_bytes": 274877906944, "avail_bytes": 76958277632}
  ],
  "network": [
    {"interface": "eth0", "rx_bytes_per_sec": 13000000.00, "tx_bytes_per_sec": 3355443.20}
  ]
}
```

### Options

```
Usage: vitals [options]

Options:
  --once         One-shot output and exit
  --mini         Single-line output for tmux/prompt
  --watch        Time-series graph mode
  --interval N   Update interval in seconds (default: 1)
  --json         Output as JSON (with --once)
```

## Health colors

Bar colors change automatically based on usage level.

| Color | Threshold |
|-------|-----------|
| Green | < 70% |
| Yellow | 70–90% |
| Red | > 90% |

## Performance targets

| Metric | Target |
|--------|--------|
| Startup time | < 10ms |
| CPU usage | < 0.1% (at 1s interval) |
| Memory usage | < 5MB RSS |
| Binary size | < 800KB |
| External dependencies | Zero |

## Development

- **Language**: [Zig](https://ziglang.org/) 0.15.0+
- **Supported OS**: macOS (x86_64, aarch64), Linux (x86_64, aarch64)
- **Dependencies**: None (macOS system APIs + Linux `/proc` only)

### Running tests

```bash
zig build test
```

## License

MIT
