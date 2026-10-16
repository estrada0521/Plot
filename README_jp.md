<div align="center">

# Plot

[English](README.md)

</div>

<p align="center">
  <img src="images/light.png" width="49%" alt="Plot、ライトモード">
  <img src="images/dark.png" width="49%" alt="Plot、ダークモード">
</p>

---

## Setup

Metal対応のmacOS 13.3以降と、Xcode Command Line Toolsが必要です。

```sh
./bin/install-app
```

`/Applications/Plot.app` にインストールして起動します。更新時も `./bin/install-app` を実行します。

Objective-C・AppKit・Metalで構成し、外部ランタイムやライブラリは使いません。[描画と比較結果](docs/rendering.md)。

## ショートカット

<details>
<summary>一覧</summary>

- 選択中のファイルをコピー — `⌘C`
- ウィンドウを閉じる — `⌘W`
- 常に手前に表示 — `⌥⌘T`
- データの選択 — 矢印キー
- 開く — `⌘O`
- 新規ウィンドウ — `⌘N`
- ウィンドウを複製 — `⇧⌘D`
- Finder で表示 — `⌥⌘R`
- エディタで開く（設定で変更可） — `⌘E`
- 絶対パスをコピー — `⌥⌘C`
- パネル画像を保存（Downloads へ） — `⌘S`
- X 軸の列を次へ／前へ — `⌘X` ／ `⇧⌘X`
- Y 軸の列を次へ／前へ — `⌘Y` ／ `⇧⌘Y`
- フィルタ画面を開く — `⌥⌘F`
- 外れ値除外を切り替え — `⇧⌥⌘R`
- 設定 — `⌘,`
- 次／前のウィンドウ — `` ⌘` `` ／ `` ⇧⌘` ``
- ウィンドウをタイル配置 — `⌥⌘A`
- 最小化 — `⌘M`

</details>
