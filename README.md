# Plots

A lightweight launcher-style macOS app that simply graphs array data such as csv / dat / ras / SPEC txt.

[日本語版 README](README_jp.md)

<p align="center">
  <img src="images/light.png" width="49%">
  <img src="images/dark.png" width="49%">
</p>

## Keyboard Shortcuts

- Open — `⌘O`
- New window — `⌘N`
- Duplicate window — `⌘C`
- Reveal in Finder — `⌘F`
- Open in editor (configurable) — `⌘E`
- Copy path — `⌘P`
- Save panel image (to Downloads) — `⌘S`
- Next / previous X-axis column — `⌘X` / `⇧⌘X`
- Next / previous Y-axis column — `⌘Y` / `⇧⌘Y`
- Open the filter window — `⌥⌘F`
- Open the axes window — `⇧⌥⌘G`
- Add twin data — `⇧⌥⌘D`
- Exclude outliers — `⌥⌘R`
- Settings — `⌘,`
- Next / previous window — `` ⌘` `` / `` ⇧⌘` ``
- Tile windows — `⌥⌘A`
- Minimize — `⌘M`

## Setup

In a terminal, move into this folder and run the following two commands in order:

```bash
npm install          # first time only — fetches dependencies
npm run app:install  # builds, installs into /Applications, and launches
```

After that, just run `npm run app:install` to update to the latest build.

## Stack

- [Tauri v2](https://tauri.app/) (Rust backend)
- Vite + TypeScript
- [Plotly.js](https://plotly.com/javascript/) (WebGL `scattergl`)
