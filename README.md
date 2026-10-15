# Plot

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
- Exclude outliers — `⌥⌘R`
- Settings — `⌘,`
- Next / previous window — `` ⌘` `` / `` ⇧⌘` ``
- Tile windows — `⌥⌘A`
- Minimize — `⌘M`

## Setup

Requires Rust, Node.js/pnpm, and Xcode Command Line Tools.

In a terminal, move into this folder and run the following two commands in order:

```bash
pnpm install         # first time only — fetches dependencies
pnpm app:install  # builds, installs into /Applications, and launches
```

After that, just run `pnpm app:install` to update to the latest build.

One toolbar is shared by all plots. It appears below the focused plot, keeps the same target while you use its controls, and hides when another app is active.

Files opened together are grouped into one plot when their default X/Y column names match. Without metadata defaults, the first two columns are used. Each group keeps only columns shared by every file; all datasets stay visible in gray while the selected dataset is emphasized in black. Use the arrow keys to change the selection; the header shows its name and position in the group. The Open dialog also accepts multiple files.

The app bundle exists only at `/Applications/Plot.app`. Both `pnpm app:build` and `pnpm app:install` install there; `app:install` also launches it. Temporary packaging files are removed automatically.

## Stack

- AppKit + WKWebView (macOS 13.3+)
- Rust (file parsing)
- TypeScript + esbuild
- [Plotly.js](https://plotly.com/javascript/) (WebGL `scattergl`)
