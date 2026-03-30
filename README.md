# vitals

Zig製の超軽量システムリソースモニタ。起動した瞬間に CPU・メモリ・ディスク・ネットワークの状況を把握できる。

## 特徴

- **高速起動**: < 10ms で最初の描画が完了
- **軽量**: ツール自身が CPU 0.1% 未満、メモリ < 5MB
- **ゼロ依存**: Linux `/proc` のみ使用、外部ライブラリなし
- **3つの表示モード**: ワンショット、ミニ、ウォッチ

## インストール

### ビルド

```bash
git clone https://github.com/AI1411/Vitals
cd Vitals
zig build -Doptimize=ReleaseSafe
```

バイナリは `zig-out/bin/vitals` に生成されます。

### PATH に追加

```bash
cp zig-out/bin/vitals ~/.local/bin/
```

## 使い方

### ワンショットモード (`--once`)

CPU・メモリ・ディスク・ネットワーク情報を一度出力して終了する。

```bash
vitals --once
```

```
  CPU  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░  42%    MEM  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░  65%
  SWP  ▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   5%    LOAD 3.42 / 2.81 / 2.15

  /      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░  72%  187.0 GB free    eth0  ↓ 12.4 MB/s  ↑ 3.2 MB/s
  /home  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░  45%  530.0 GB free
```

### ミニモード (`--mini`)

tmux ステータスバーやシェルプロンプト用の1行出力。

```bash
vitals --mini
# CPU 42% | MEM 65% | DISK 72% | NET ↓12M ↑3M | LOAD 3.42
```

**tmux.conf への組み込み例:**

```
set -g status-right '#(vitals --mini)'
```

### ウォッチモード (`--watch`)

CPU・メモリ・ネットワークの時系列グラフをリアルタイム表示する。

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

[q] 終了  [+/-] 時間範囲  [space] 一時停止  [r] リセット
```

**キーバインド:**

| キー | 動作 |
|------|------|
| `q` / `Ctrl-C` | 終了 |
| `space` | 更新を一時停止 / 再開 |
| `r` | グラフをリセット |
| `+` | 表示時間範囲を縮小 (ズームイン) |
| `-` | 表示時間範囲を拡大 (ズームアウト) |

**時間範囲:** 1分〜60分 (デフォルト: 5分、60秒単位で変更)

### JSON 出力 (`--json`)

スナップショットを JSON 形式で出力する。モニタリングシステムとの連携用。

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

### オプション一覧

```
Usage: vitals [options]

Options:
  --once         One-shot output and exit
  --mini         Single-line output for tmux/prompt
  --watch        Time-series graph mode
  --interval N   Update interval in seconds (default: 1)
  --json         Output as JSON (with --once)
```

## ヘルスカラー

バーの色は使用率に応じて自動的に変わる。

| 色 | 閾値 |
|----|------|
| 緑 | < 70% |
| 黄 | 70〜90% |
| 赤 | > 90% |

## 成功指標

| 指標 | 目標値 |
|------|--------|
| 起動時間 | < 10ms |
| CPU 使用率 | < 0.1% (1秒間隔更新時) |
| メモリ使用量 | < 5MB RSS |
| バイナリサイズ | < 800KB |
| 外部依存 | ゼロ |

## 開発環境

- **言語**: [Zig](https://ziglang.org/) 0.15.0+
- **対応 OS**: Linux (x86_64, aarch64)
- **依存**: なし (Linux `/proc` + システムコールのみ)

### テスト実行

```bash
zig build test
```

## ライセンス

MIT
