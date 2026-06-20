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
- 設定 — `⌘,`
- 次／前のウィンドウ — `` ⌘` `` ／ `` ⇧⌘` ``
- ウィンドウをタイル配置 — `⌥⌘A`
- 最小化 — `⌘M`


## Setup
ターミナルでこのフォルダに移動し、次の2つを順に実行してください

```bash
npm install          # 初回のみ。必要なものを取得
npm run app:install  # ビルドして /Applications に入れ、起動
```
2回目以降は `npm run app:install` だけで最新版に入れ替わります。

## Stack
- [Tauri v2](https://tauri.app/)（Rust Backend）
- Vite + TypeScript
- [Plotly.js](https://plotly.com/javascript/)（WebGL  `scattergl`）
