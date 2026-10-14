 # Plots

csv / dat / ras / SPEC txt 等の配列データをグラフ表示するだけの軽量 Launcher Service アプリです。

<p align="center">
  <img src="images/light.png" width="49%">
  <img src="images/dark.png" width="49%">
</p>

## Keyboard Shortcuts

- 開く — `⌘O`
- 新規ウィンドウ — `⌘N`
- ウィンドウを複製 — `⌘C`
- Finder で表示 — `⌘F`
- エディタで開く（設定で変更可） — `⌘E`
- パスをコピー — `⌘P`
- パネル画像を保存（Downloads へ） — `⌘S`
- X 軸の列を次へ／前へ — `⌘X` ／ `⇧⌘X`
- Y 軸の列を次へ／前へ — `⌘Y` ／ `⇧⌘Y`
- フィルタ画面を開く — `⌥⌘F`
- 軸設定ウィンドウを開く — `⇧⌥⌘G`
- 2つ目のデータを追加 — `⇧⌥⌘D`
- 外れ値除外を切り替え — `⌥⌘R`
- 設定 — `⌘,`
- 次／前のウィンドウ — `` ⌘` `` ／ `` ⇧⌘` ``
- ウィンドウをタイル配置 — `⌥⌘A`
- 最小化 — `⌘M`


## Setup

Rust、Node.js/pnpm、Xcode Command Line Toolsが必要です。
ターミナルでこのフォルダに移動し、次の2つを順に実行してください

```bash
pnpm install         # 初回のみ。必要なものを取得
pnpm app:install  # ビルドして /Applications に入れ、起動
```
2回目以降は `pnpm app:install` だけで最新版に入れ替わります。

## Stack
- AppKit + WKWebView（macOS 13.3以降）
- Rust（ファイル解析）
- TypeScript + esbuild
- [Plotly.js](https://plotly.com/javascript/)（WebGL  `scattergl`）
