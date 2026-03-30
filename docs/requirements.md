# vitals — 設計ドキュメント

## コンセプト

Zig製の超軽量システムリソースモニタ。ターミナルを開いた瞬間に CPU・メモリ・ディスク・ネットワーク・プロセスの状況が一目でわかる。htop のような「全部入り」ではなく、「今マシンが健康かどうか」を3秒で判断できることに特化。

### デザイン哲学

- **Glanceable**: 見た瞬間に状況がわかるビジュアル
- **Zero-config**: 引数なしで起動すれば最適な表示
- **Minimal footprint**: ツール自体が CPU 0.1% 未満、メモリ 5MB 未満

### 既存ツールとの差別化

| ツール | 問題点 | vitals の優位性 |
|--------|--------|------------------|
| htop | 情報過多、読み解くのに時間がかかる | 一画面に要約、色でヘルス判定 |
| btop | 高機能だが重い (10-30MB) | <1MB、CPU 0.1% 未満 |
| glances | Python製で起動が遅い (1-2秒) | 起動 <10ms |
| top | 見た目が古い、カスタマイズ困難 | モダンTUI、直感的 |
| neofetch | 静的情報のみ、リアルタイム性なし | ライブ更新 |
| macchina | 静的システム情報表示 | リアルタイムリソース監視 |

---

## 表示モード

### 1. ダッシュボードモード (デフォルト: `vitals`)

```
┌─ vitals ──────────────────────────────────────────────────────────┐
│  myhost · Linux 6.8.0 · up 3d 14h · 12 cores · 32 GB             │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  CPU  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░  42%   3.2 GHz   │
│       usr 35%  sys 5%  io 2%  idle 58%                             │
│                                                                    │
│       Core 0  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░  89%                        │
│       Core 1  ▓▓▓▓▓▓▓░░░░░░░░░░░░░░  31%                        │
│       Core 2  ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░  55%                        │
│       Core 3  ▓▓▓░░░░░░░░░░░░░░░░░░  12%                         │
│       ...                                                          │
│                                                                    │
│  MEM  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░  65%              │
│       Used 20.8 GB / 32.0 GB    Buffers 4.2 GB   Free 7.0 GB     │
│                                                                    │
│  SWP  ▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   5%              │
│       Used 0.4 GB / 8.0 GB                                        │
│                                                                    │
│  DISK ┬ /         ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░  72%  187G/256G  │
│       ├ /home     ▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░  45%  430G/960G  │
│       └ /data     ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  91%  1.8T/2.0T  │
│                                                     ^^^ 赤で警告   │
│                                                                    │
│  NET  eth0  ↓ 12.4 MB/s   ↑ 3.2 MB/s                             │
│       lo    ↓ 45.1 KB/s   ↑ 45.1 KB/s                            │
│                                                                    │
│  LOAD  1m: 3.42   5m: 2.81   15m: 2.15                           │
│  PROC  Total: 312   Running: 4   Sleeping: 305   Zombie: 3 ⚠     │
│                                                                    │
├────────────────────────────────────────────────────────────────────┤
│  TOP PROCESSES (by CPU)                                            │
│  ──────────────────────────────────────────────────────────────    │
│  PID     CPU%   MEM%   MEM      PROCESS         COMMAND           │
│  12345   45.2   3.1    1.0 GB   rust-analyzer   rust-analyzer     │
│  6789    22.1   8.4    2.7 GB   node            next dev          │
│  3456    12.0   1.2    384 MB   gopls           gopls serve       │
│  9012     8.5  15.2    4.9 GB   chrome          chrome --type=... │
│  1111     4.3   0.8    256 MB   docker          dockerd           │
│                                                                    │
├────────────────────────────────────────────────────────────────────┤
│ [q] 終了  [c/m/d] ソート切替  [p] プロセス詳細  [1] コア展開     │
│ [h] ヒストリ  [k] プロセスkill  [/] 検索  [?] ヘルプ              │
└────────────────────────────────────────────────────────────────────┘
```

### 2. ワンショットモード (`vitals --once`)

```bash
$ vitals --once

  CPU  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░  42%    MEM  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░  65%
  SWP  ▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   5%    LOAD 3.42 / 2.81 / 2.15

  /      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░  72%  187G free    eth0  ↓ 12.4 MB/s  ↑ 3.2 MB/s
  /home  ▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░  45%  530G free    Procs 312 (4 run, 3 zombie ⚠)
  /data  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  91%  200G free ⚠
```

### 3. ミニモード (`vitals --mini`)

tmux ステータスバーやプロンプト埋め込み用の1行出力。

```bash
$ vitals --mini
CPU 42% │ MEM 65% │ DISK 72% │ NET ↓12M ↑3M │ LOAD 3.42

# tmux.conf に組み込み:
# set -g status-right '#(vitals --mini)'
```

### 4. ウォッチモード (`vitals --watch cpu,mem`)

指定メトリクスの時系列グラフを表示。

```
┌─ vitals watch ─────────────────────────────────────────────────┐
│                                                                  │
│  CPU Usage (5 min)                                               │
│  100%┤                                                           │
│   80%┤          ╭╮                                               │
│   60%┤    ╭─────╯╰──╮                                            │
│   40%┤────╯          ╰──────────────────────                     │
│   20%┤                                                           │
│    0%┼──────┼──────┼──────┼──────┼──────┼                        │
│      -5m   -4m   -3m   -2m   -1m   now                          │
│                                                                  │
│  Memory Usage (5 min)                                            │
│  32GB┤──────────────────────────────────                         │
│  24GB┤                                                           │
│  16GB┤────────────────────╮                                      │
│   8GB┤                     ╰────────────                         │
│   0GB┼──────┼──────┼──────┼──────┼──────┼                        │
│      -5m   -4m   -3m   -2m   -1m   now                          │
│                                                                  │
│  Network I/O (5 min)                                             │
│  50MB/s┤                                                         │
│  25MB/s┤    ╭╮  ╭───╮                                            │
│      0 ┤────╯╰──╯   ╰──────────────────    ↓ Download           │
│ -10MB/s┤─────────────────────────────────   ↑ Upload             │
│        ┼──────┼──────┼──────┼──────┼──────┼                      │
│        -5m   -4m   -3m   -2m   -1m   now                        │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│ [q] 終了  [+/-] 時間範囲  [space] 一時停止  [r] リセット        │
└──────────────────────────────────────────────────────────────────┘
```

---

## ヘルスインジケーター (色分けルール)

```
  指標        正常 (緑)      注意 (黄)        危険 (赤)
  ─────────────────────────────────────────────────────
  CPU         < 60%          60-85%           > 85%
  Memory      < 70%          70-90%           > 90%
  Swap        < 10%          10-50%           > 50%
  Disk        < 70%          70-90%           > 90%
  Load Avg    < cores×0.7    cores×0.7-1.0    > cores×1.0
  Zombie      0              1-5              > 5
```

バーの色が自動で変わるので、ターミナルを開いた瞬間に赤が見えたら何かがおかしい、と即判断できる。

---

## アーキテクチャ

```
┌──────────────────────────────────────────────────────────┐
│                      CLI Entry                           │
│  vitals [--once|--mini|--watch] [--interval N]          │
└───────────────┬──────────────────────────────────────────┘
                │
                ▼
┌──────────────────────────────────────────────────────────┐
│                  System Collector                         │
│                                                          │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐           │
│  │ CPU        │ │ Memory     │ │ Disk       │           │
│  │/proc/stat  │ │/proc/      │ │/proc/      │           │
│  │            │ │ meminfo    │ │ mounts +   │           │
│  │            │ │            │ │ statvfs()  │           │
│  └─────┬──────┘ └─────┬──────┘ └─────┬──────┘          │
│        │              │              │                   │
│  ┌─────┴──────┐ ┌─────┴──────┐ ┌────┴───────┐          │
│  │ Network    │ │ Process    │ │ Load Avg   │          │
│  │/proc/net/  │ │/proc/[pid]/│ │/proc/      │          │
│  │ dev        │ │ stat,comm  │ │ loadavg    │          │
│  └─────┬──────┘ └─────┬──────┘ └────┬───────┘          │
│        │              │              │                   │
│        └──────────────┴──────────────┘                   │
│                       │                                  │
│                       ▼                                  │
│              Snapshot (全メトリクスの1時点データ)          │
└───────────────┬──────────────────────────────────────────┘
                │
        ┌───────┴───────┐
        ▼               ▼
┌──────────────┐ ┌──────────────────┐
│ History Ring │ │ Renderer         │
│ (過去N分の   │ │                  │
│  スナップ    │ │ - Dashboard TUI  │
│  ショット)   │ │ - Once (stdout)  │
│              │ │ - Mini (1 line)  │
│              │ │ - Watch (graph)  │
└──────────────┘ └──────────────────┘
```

### データ収集設計

```
/proc ファイル          読み取り頻度    パース方式
───────────────────────────────────────────────────
/proc/stat              1秒            行スキャン (cpu行のみ)
/proc/meminfo           1秒            key:value パース
/proc/loadavg           1秒            space区切り (5フィールド)
/proc/net/dev           1秒            行スキャン (ヘッダスキップ)
/proc/mounts            5秒            マウントポイント抽出
statvfs()               5秒            各マウントのディスク容量
/proc/[pid]/stat        2秒            Top N プロセスのみ
/proc/[pid]/comm        2秒            Top N プロセスのみ
/proc/[pid]/status      2秒            VmRSS 取得
```

**ポイント**: 全PIDの走査は重いので、まず `/proc/stat` から全体CPU使用率を取り、次にTop N（CPU上位10件）のプロセスだけ詳細を読む。htopのように全プロセスを毎秒走査しないことで軽量性を維持。

---

## /proc パース詳細

### CPU (/proc/stat)

```
cpu  12345 678 9012 345678 901 234 56 0 0 0
cpu0 3000  170 2200 86000  200  60 14 0 0 0
cpu1 3100  168 2250 85900  210  58 13 0 0 0
...

フィールド: user nice system idle iowait irq softirq steal guest guest_nice
CPU% = 1 - (idle_delta / total_delta) × 100
```

### Memory (/proc/meminfo)

```
MemTotal:       32768000 kB
MemFree:         7200000 kB
MemAvailable:   12800000 kB
Buffers:         1200000 kB
Cached:          4300000 kB
SwapTotal:       8192000 kB
SwapFree:        7800000 kB

Used = Total - Available
```

### Network (/proc/net/dev)

```
Inter-|   Receive                    |  Transmit
 face |bytes    packets ...          |bytes    packets ...
  eth0: 123456789  98765 ...          987654321  87654 ...

Delta bytes / interval = throughput (bytes/sec)
```

### Load Average (/proc/loadavg)

```
3.42 2.81 2.15 4/312 12345
1m   5m   15m  running/total  last_pid
```

---

## プロジェクト構成

```
vitals/
├── build.zig
├── build.zig.zon
├── README.md
│
├── src/
│   ├── main.zig                # CLI エントリ、モード分岐
│   │
│   ├── collector/
│   │   ├── cpu.zig             # /proc/stat パーサー
│   │   ├── memory.zig          # /proc/meminfo パーサー
│   │   ├── disk.zig            # /proc/mounts + statvfs
│   │   ├── network.zig         # /proc/net/dev パーサー
│   │   ├── loadavg.zig         # /proc/loadavg パーサー
│   │   ├── process.zig         # Top N プロセス収集
│   │   ├── snapshot.zig        # 全メトリクスの1時点構造体
│   │   └── history.zig         # リングバッファで過去N分保持
│   │
│   ├── render/
│   │   ├── dashboard.zig       # メインダッシュボード TUI
│   │   ├── once.zig            # ワンショット stdout 出力
│   │   ├── mini.zig            # 1行ミニ出力
│   │   ├── watch.zig           # 時系列グラフ TUI
│   │   └── widgets/
│   │       ├── bar.zig         # プログレスバー (色分け付き)
│   │       ├── sparkline.zig   # ミニグラフ (▁▂▃▄▅▆▇█)
│   │       ├── table.zig       # プロセステーブル
│   │       ├── graph.zig       # ASCII 時系列グラフ
│   │       └── gauge.zig       # パーセンテージゲージ
│   │
│   ├── health/
│   │   ├── thresholds.zig      # 閾値定義 (正常/注意/危険)
│   │   └── color.zig           # ヘルス→ANSIカラーマッピング
│   │
│   └── utils/
│       ├── proc_reader.zig     # /proc ファイル読み取りヘルパー
│       ├── parser.zig          # 汎用行パーサー
│       ├── ring_buffer.zig     # 固定サイズリングバッファ
│       ├── size.zig            # バイト数→人間可読変換
│       ├── terminal.zig        # ターミナルサイズ取得、raw mode
│       └── ansi.zig            # ANSI エスケープヘルパー
│
└── tests/
    ├── cpu_test.zig
    ├── memory_test.zig
    └── fixtures/
        ├── proc_stat.txt
        ├── proc_meminfo.txt
        └── proc_net_dev.txt
```

---

## 実装フェーズ

### Phase 1: データ収集 + ワンショット表示 (Week 1)

```
目標: vitals --once で CPU/MEM/DISK/NET/LOAD が表示される

タスク:
  [1] /proc/stat パーサー (CPU 全体 + コア別)
  [2] /proc/meminfo パーサー (Used/Free/Buffers/Swap)
  [3] /proc/mounts + statvfs() でディスク使用量
  [4] /proc/net/dev パーサー (bytes delta → throughput)
  [5] /proc/loadavg パーサー
  [6] Snapshot 構造体に全データを集約
  [7] カラー付きバー + ワンショット stdout 出力
  [8] ミニモード (--mini) 1行出力
```

### Phase 2: ダッシュボード TUI (Week 2)

```
目標: vitals でライブダッシュボードが動く

タスク:
  [1] Raw terminal mode + 画面クリア制御
  [2] レイアウトエンジン (ターミナルサイズに応じた適応)
  [3] プログレスバー widget (ヘルス色分け)
  [4] CPU コア別展開/折りたたみ ([1] キー)
  [5] 1秒間隔の定期更新ループ
  [6] ヘルスインジケーター (閾値ベース自動色分け)
  [7] ミニ sparkline (直近60秒の推移を ▁▂▃▄▅▆▇█ で表示)
```

### Phase 3: プロセスリスト + 操作 (Week 3)

```
目標: Top プロセス表示、ソート切り替え、kill 操作

タスク:
  [1] /proc/[pid]/stat からCPU使用率計算
  [2] /proc/[pid]/status からメモリ使用量取得
  [3] Top 10 プロセスをテーブル表示
  [4] ソート切り替え (c:CPU, m:MEM, d:DISK I/O)
  [5] プロセス検索 (/ キー)
  [6] プロセスkill (k キー + 確認)
  [7] プロセス詳細表示 (p キー → fd数、スレッド数、起動時間)
```

### Phase 4: ウォッチモード + 仕上げ (Week 4)

```
目標: vitals --watch で時系列グラフ、README 完成

タスク:
  [1] History リングバッファ (過去5-60分のスナップショット保持)
  [2] ASCII 時系列グラフ widget
  [3] watch モード TUI (CPU/MEM/NET のグラフ並列表示)
  [4] 時間範囲の拡大/縮小 (+/- キー)
  [5] ターミナルリサイズ対応
  [6] JSON 出力 (--json、モニタリング連携用)
  [7] README / スクリーンショット / デモ GIF
```

---

## Zig の特性が活きるポイント

### 1. /proc パースのゼロアロケーション

```zig
// /proc/stat の1行を固定バッファでパース (ヒープ割り当てゼロ)
fn parseCpuLine(line: []const u8) CpuTick {
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    _ = it.next(); // "cpu" or "cpuN" をスキップ
    return .{
        .user    = parseU64(it.next().?),
        .nice    = parseU64(it.next().?),
        .system  = parseU64(it.next().?),
        .idle    = parseU64(it.next().?),
        .iowait  = parseU64(it.next().?),
        .irq     = parseU64(it.next().?),
        .softirq = parseU64(it.next().?),
    };
}

fn parseU64(s: []const u8) u64 {
    var result: u64 = 0;
    for (s) |c| result = result * 10 + (c - '0');
    return result;
}
// std.fmt.parseInt より高速 — エラーチェック不要（/proc は信頼できるソース）
```

### 2. comptime でバー描画文字列を事前構築

```zig
// 0-100% に対応するバー文字列をコンパイル時生成
const bar_chars = comptime blk: {
    var bars: [101][]const u8 = undefined;
    for (0..101) |pct| {
        const filled = pct * 40 / 100;
        var buf: [40]u8 = undefined;
        for (0..40) |i| {
            buf[i] = if (i < filled) '▓' else '░';
        }
        bars[pct] = &buf;
    }
    break :blk bars;
};
// 描画時は bars[pct] を参照するだけ — 計算コストゼロ
```

### 3. リングバッファでヒストリ管理

```zig
// 固定サイズ、アロケーションなし
const HistoryBuffer = struct {
    snapshots: [300]Snapshot, // 5分 × 1秒間隔
    head: usize = 0,
    len: usize = 0,

    fn push(self: *@This(), snap: Snapshot) void {
        self.snapshots[self.head] = snap;
        self.head = (self.head + 1) % self.snapshots.len;
        if (self.len < self.snapshots.len) self.len += 1;
    }

    fn latest(self: *const @This(), n: usize) []const Snapshot {
        // 直近 n 個を返す (コピーなし、スライス参照)
    }
};
```

### 4. Sparkline で直近の推移をコンパクト表示

```zig
const spark_chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };

fn sparkline(values: []const f64, max: f64) void {
    for (values) |v| {
        const idx = @min(@as(usize, @intFromFloat(v / max * 7.0)), 7);
        writer.writeAll(spark_chars[idx]);
    }
}
// CPU 42% ▁▂▃▅▇▆▅▃▄▅▆▇▅▃▂▃▄▅ のように60秒分を1行で表示
```

---

## ターミナルサイズ適応

```
幅 120+ (フル):    バー40文字 + コア展開 + sparkline
幅 80-119 (標準):  バー30文字 + コア折りたたみ
幅 60-79 (コンパクト): バー20文字 + 数値のみ
幅 <60 (ミニ):     mini モードにフォールバック
```

---

## 成功指標

1. **起動時間**: < 10ms (最初の描画まで)
2. **CPU使用率**: ツール自身が 0.1% 未満 (1秒間隔更新時)
3. **メモリ使用量**: < 5MB RSS
4. **バイナリサイズ**: < 800KB
5. **依存**: ゼロ (Linux /proc のみ、外部ライブラリなし)
6. **更新頻度**: 1秒間隔でちらつきなし (差分描画)

---

## 4ツール共通ライブラリ化の見通し

reqbench・portsnap・dkill・vitals で共通化できるモジュール:

```
libs/
├── tui/
│   ├── terminal.zig      # raw mode, サイズ取得, リサイズ検知
│   ├── ansi.zig          # カラー, カーソル移動, 画面クリア
│   ├── bar.zig           # プログレスバー
│   ├── table.zig         # カラム整列テーブル
│   ├── graph.zig         # ASCII グラフ
│   └── input.zig         # キー入力ハンドラ
│
├── io/
│   ├── proc_reader.zig   # /proc ファイル読み取り (portsnap + vitals)
│   ├── http.zig          # HTTP/1.1 パーサー (reqbench + dkill)
│   └── socket.zig        # Unix/TCP ソケット (dkill + reqbench)
│
├── data/
│   ├── ring_buffer.zig   # 固定サイズリングバッファ
│   ├── json.zig          # JSON パース/出力ヘルパー
│   └── arena.zig         # Arena Allocator ラッパー
│
└── fmt/
    ├── size.zig           # バイト→人間可読 (dkill + vitals)
    ├── time.zig           # 相対時間 "3d ago" (dkill)
    └── color.zig          # ヘルス色分けルール (vitals)
```