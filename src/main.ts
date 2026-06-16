import { invoke } from "@tauri-apps/api/core";
import { open, save } from "@tauri-apps/plugin-dialog";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { LogicalSize, PhysicalPosition } from "@tauri-apps/api/dpi";
import { listen } from "@tauri-apps/api/event";
import { applyTheme, bindThemeUpdates } from "./theme-util";
import Plotly from "plotly.js-dist-min";

interface Dataset {
  name: string;
  columns: string[];
  rows: (number | null)[][];
  display_name?: string;
  default_x?: string;
  default_y?: string;
}

const openBtn = document.getElementById("open-btn") as HTMLButtonElement;
const xSelect = document.getElementById("x-select") as HTMLSelectElement;
const ySelect = document.getElementById("y-select") as HTMLSelectElement;
const statusEl = document.getElementById("status") as HTMLSpanElement;
const plotEl = document.getElementById("plot") as HTMLDivElement;
const homeBtn = document.getElementById("home-btn") as HTMLButtonElement;
const undoBtn = document.getElementById("undo-btn") as HTMLButtonElement;
const redoBtn = document.getElementById("redo-btn") as HTMLButtonElement;
const panBtn = document.getElementById("pan-btn") as HTMLButtonElement;
const zoomBtn = document.getElementById("zoom-btn") as HTMLButtonElement;
const lineBtn = document.getElementById("line-btn") as HTMLButtonElement;
const scatterBtn = document.getElementById("scatter-btn") as HTMLButtonElement;
const titleEl = document.getElementById("title") as HTMLSpanElement;
const pinBtn = document.getElementById("win-pin") as HTMLButtonElement;

// --- 自前タイトルバーのウィンドウ操作 ---
const appWindow = getCurrentWindow();
let isPinned = false;
function syncPinButton() {
  pinBtn.classList.toggle("active", isPinned);
  pinBtn.title = isPinned ? "常に手前に表示を解除" : "常に手前に表示";
  pinBtn.setAttribute("aria-pressed", String(isPinned));
}
appWindow.isAlwaysOnTop().then((value) => {
  isPinned = value;
  syncPinButton();
});
pinBtn.addEventListener("click", async () => {
  isPinned = !isPinned;
  syncPinButton();
  try {
    await appWindow.setAlwaysOnTop(isPinned);
  } catch (err) {
    isPinned = !isPinned;
    syncPinButton();
    statusEl.textContent = `エラー: ${err}`;
  }
});
(document.getElementById("win-close") as HTMLButtonElement).addEventListener(
  "click",
  () => appWindow.close(),
);
(document.getElementById("win-min") as HTMLButtonElement).addEventListener(
  "click",
  () => appWindow.minimize(),
);

// --- テーマ適用（設定は別ウィンドウで変更し、イベントで反映） ---
bindThemeUpdates();

// 非フォーカス時はヘッダーのタイトルを薄く表示。
// フォーカス取得時にもテーマを再適用し、万一の取りこぼしを補正する。
appWindow
  .onFocusChanged(({ payload: focused }) => {
    document.body.classList.toggle("window-blurred", !focused);
    if (focused) applyTheme();
  })
  .catch(() => {});

let current: Dataset | null = null;
let currentPath: string | null = null;
let dragmode: "zoom" | "pan" = "zoom";
let plotMode: "lines" | "markers" = "lines";

// データフィルタ（filter ウィンドウから適用）。列インデックスごとの min/max。
// 元データ（current.rows）は不変。描画/保存時にこの規則で行を絞り込むだけ。
interface FilterRule {
  col: number;
  min: number | null;
  max: number | null;
}
let activeFilter: FilterRule[] = [];

function getFilteredRows(): (number | null)[][] {
  if (!current) return [];
  const rules = activeFilter.filter((f) => f.min !== null || f.max !== null);
  if (!rules.length) return current.rows;
  return current.rows.filter((r) =>
    rules.every((f) => {
      const v = r[f.col];
      // 制約をかけた列が欠損(null/NaN)の行は除外
      if (v === null || v === undefined || Number.isNaN(v)) return false;
      if (f.min !== null && v < f.min) return false;
      if (f.max !== null && v > f.max) return false;
      return true;
    }),
  );
}

// filter ウィンドウからの適用要求。元データには触れず描画のみ更新（軸は再フィット）。
// 自ウィンドウ宛て（emitTo）のみ受信するよう target を限定する。
listen<FilterRule[]>(
  "filter-apply",
  (e) => {
    activeFilter = Array.isArray(e.payload) ? e.payload : [];
    if (current) render();
  },
  { target: appWindow.label },
).catch(() => {});

// filter ウィンドウが閉じられたら問答無用でフィルタ解除（元データ全体に戻す）。
listen("filter-reset", () => {
  activeFilter = [];
  if (current) render();
}, { target: appWindow.label }).catch(() => {});

// filter ウィンドウからの保存要求。フィルタ後データを新規 CSV として保存（元ファイルは不変）。
// 自ウィンドウ宛て（emitTo）のみ受信。
listen("filter-save", async () => {
  if (!current) return;
  const rows = getFilteredRows();
  const fmt = (v: number | null) =>
    v === null || v === undefined || Number.isNaN(v) ? "" : String(v);
  const csv =
    current.columns.join(",") +
    "\n" +
    rows.map((r) => r.map(fmt).join(",")).join("\n") +
    "\n";
  const base = (current.display_name ?? current.name).replace(/\.[^.]+$/, "");
  try {
    const path = await save({
      defaultPath: `${base}-filtered.csv`,
      filters: [{ name: "CSV", extensions: ["csv"] }],
    });
    if (typeof path === "string") {
      await invoke("write_text_file", { path, content: csv });
    }
  } catch (err) {
    statusEl.textContent = `エラー: ${err}`;
  }
}, { target: appWindow.label }).catch(() => {});

const panelEl = document.getElementById("panel") as HTMLDivElement;
const footerEl = document.querySelector(".toolbar") as HTMLElement;

// パネルのサイズ変化に追従して Plotly を再描画
const resizeObserver = new ResizeObserver(() => {
  if (current) Plotly.Plots.resize(plotEl);
});
resizeObserver.observe(plotEl);

// plot パネルの実寸を Rust に報告（タイル配置でフッターを重ねて詰めるのに使う）
new ResizeObserver(() => {
  invoke("report_panel_size", {
    width: panelEl.offsetWidth,
    height: panelEl.offsetHeight,
  }).catch(() => {});
}).observe(panelEl);

// ウィンドウを「パネル∪フッター」の外接矩形に吸着させる。
// macOS の setContentSize は左上を固定して伸縮するため、リサイズ中は下端（左下）が
// 画面上で動かないよう、サイズ変更後に上端位置を補正する（＝左下を固定）。
let anchorLeftPhys = 0;
let anchorBottomPhys = 0;
let scale = 1;
let fitRunning = false;
let fitPending = false;
async function applyFit() {
  if (fitRunning) {
    fitPending = true;
    return;
  }
  fitRunning = true;
  const footerGap = parseFloat(themeVar("--panel-footer-gap")) || 0;
  const w = Math.ceil(Math.max(panelEl.offsetWidth, footerEl.offsetWidth));
  const h = Math.ceil(panelEl.offsetHeight + footerEl.offsetHeight + footerGap);
  await appWindow.setSize(new LogicalSize(w, h));
  if (resizeMode) {
    const topPhys = Math.round(anchorBottomPhys - h * scale);
    await appWindow.setPosition(new PhysicalPosition(anchorLeftPhys, topPhys));
  }
  fitRunning = false;
  if (fitPending) {
    fitPending = false;
    applyFit();
  }
}
function fitWindow() {
  applyFit();
}
// フッター幅が変わった時（X/Y選択の出現など）はウィンドウをコンテンツに吸着させる。
new ResizeObserver(() => fitWindow()).observe(footerEl);
fitWindow();

// 左下固定の前提で、上辺=高さ / 右辺=幅 / 右上角=両方 を伸縮。
// 計算は screen 座標で行い、ウィンドウ移動による座標ブレを排除する。
let resizeMode: "t" | "r" | "c" | null = null;
let startScreenX = 0;
let startScreenY = 0;
let startW = 0;
let startH = 0;

function onResizeMove(e: PointerEvent) {
  if (!resizeMode) return;
  const minW = parseInt(themeVar("--panel-min-width"), 10) || 80;
  const minH = parseInt(themeVar("--panel-min-height"), 10) || 30;
  if (resizeMode === "r" || resizeMode === "c") {
    panelEl.style.width = `${Math.max(minW, startW + (e.screenX - startScreenX))}px`;
  }
  if (resizeMode === "t" || resizeMode === "c") {
    panelEl.style.height = `${Math.max(minH, startH + (startScreenY - e.screenY))}px`;
  }
  fitWindow();
}

function onResizeUp() {
  resizeMode = null;
  window.removeEventListener("pointermove", onResizeMove);
  window.removeEventListener("pointerup", onResizeUp);
}

document.querySelectorAll<HTMLElement>(".grip").forEach((grip) => {
  grip.addEventListener("pointerdown", (e) => {
    resizeMode = grip.dataset.resize as "t" | "r" | "c";
    startScreenX = e.screenX;
    startScreenY = e.screenY;
    const r = panelEl.getBoundingClientRect();
    startW = r.width;
    startH = r.height;
    // 左下を固定点として捕捉（物理座標）
    Promise.all([
      appWindow.outerPosition(),
      appWindow.outerSize(),
      appWindow.scaleFactor(),
    ]).then(([pos, size, sf]) => {
      anchorLeftPhys = pos.x;
      anchorBottomPhys = pos.y + size.height;
      scale = sf;
    });
    window.addEventListener("pointermove", onResizeMove);
    window.addEventListener("pointerup", onResizeUp);
    e.preventDefault();
  });
});

// File メニュー（⌘O/⌘F/⌘E/⌘⇧C）からの操作。フォーカス中ウィンドウにのみ届く。
function menuAction(action: string) {
  if (action === "open") {
    openBtn.click();
    return;
  }
  if (!currentPath || !current) return;
  const fail = (err: unknown) => {
    statusEl.textContent = `エラー: ${err}`;
  };
  if (action === "filter") {
    invoke("open_filter_window", {
      sourceLabel: appWindow.label,
      name: current.display_name ?? current.name,
      columns: current.columns,
    }).catch(fail);
  } else if (action === "reveal") {
    invoke("reveal_in_finder", { path: currentPath }).catch(fail);
  } else if (action === "editor") {
    invoke("open_with_editor", {
      path: currentPath,
      editor: localStorage.getItem("editor") ?? "",
    }).catch(fail);
  } else if (action === "copy-path") {
    invoke("copy_path", { text: currentPath }).catch(fail);
  }
}
// このウィンドウ宛て（emit_to）のメニュー操作だけを受け取る。
// グローバル listen は target=Any で全イベントを拾ってしまうため自ウィンドウに限定する。
listen<string>("menu-action", (e) => menuAction(e.payload), { target: appWindow.label }).catch(
  () => {},
);

// パネル（ヘッダー＋プロット）を Downloads に画像保存
async function savePanel() {
  if (!current) return;
  try {
    const pos = await appWindow.outerPosition();
    const sf = await appWindow.scaleFactor();
    const base = (current.display_name ?? current.name).replace(/\.[^.]+$/, "");
    await invoke("save_panel_image", {
      x: pos.x / sf,
      y: pos.y / sf,
      w: panelEl.offsetWidth,
      h: panelEl.offsetHeight,
      name: base,
    });
  } catch {
    // 保存失敗時も footer にはメッセージを出さない。
  }
}
(document.getElementById("save-btn") as HTMLButtonElement).addEventListener(
  "click",
  () => savePanel(),
);
// 片方の軸の列を変更したとき、もう片方の軸の表示範囲は維持して描画する。
function changeAxis(changed: "x" | "y") {
  if (!current) return;
  const gd = plotEl as PlotElementWithHistory;
  const keep = changed === "x" ? "y" : "x";
  const keepAxis = keep === "x" ? gd._fullLayout?.xaxis : gd._fullLayout?.yaxis;
  const range = readAxisNumericRange(keepAxis);
  render(range ? { axis: keep, range } : undefined);
}

// 軸の列を切り替える（⌘X = X軸 / ⌘Y = Y軸、Shift 併用で逆方向に1つ戻る）。
function cycleAxis(sel: HTMLSelectElement, dir: number) {
  const n = sel.options.length;
  if (!current || n === 0) return;
  sel.selectedIndex = (sel.selectedIndex + dir + n) % n;
  changeAxis(sel === xSelect ? "x" : "y");
}
window.addEventListener("keydown", (e) => {
  if (!e.metaKey || e.ctrlKey || e.altKey) return;
  const key = e.key.toLowerCase();
  if (key === "s" && !e.shiftKey) {
    e.preventDefault();
    savePanel();
  } else if (key === "x") {
    e.preventDefault();
    cycleAxis(xSelect, e.shiftKey ? -1 : 1);
  } else if (key === "y") {
    e.preventDefault();
    cycleAxis(ySelect, e.shiftKey ? -1 : 1);
  }
});

async function loadDataset(path: string) {
  statusEl.textContent = "";
  try {
    current = await invoke<Dataset>("read_dataset", { path });
    currentPath = path;
    await invoke("mark_window_loaded");
    titleEl.textContent = current.display_name ?? current.name;
    setupAxisSelectors(current);
    render();
  } catch (err) {
    statusEl.textContent = `エラー: ${err}`;
  }
}

openBtn.addEventListener("click", async () => {
  const selected = await open({
    multiple: false,
    filters: [{ name: "Data", extensions: ["csv", "dat", "txt", "ras"] }],
  });
  if (typeof selected === "string") loadDataset(selected);
});

// Finder で開かれたファイル（関連付け）がこのウィンドウに割り当てられていれば自動ロード
invoke<string | null>("take_pending_file").then((path) => {
  if (path) loadDataset(path);
});

function setupAxisSelectors(ds: Dataset) {
  const fill = (sel: HTMLSelectElement, defaultIndex: number) => {
    sel.innerHTML = "";
    ds.columns.forEach((name, i) => {
      const opt = document.createElement("option");
      opt.value = String(i);
      opt.textContent = name;
      if (i === defaultIndex) opt.selected = true;
      sel.appendChild(opt);
    });
  };
  // metadata.json の既定軸があれば優先。なければ先頭2列。
  const dx = ds.default_x ? ds.columns.indexOf(ds.default_x) : -1;
  const dy = ds.default_y ? ds.columns.indexOf(ds.default_y) : -1;
  fill(xSelect, dx >= 0 ? dx : 0);
  fill(ySelect, dy >= 0 ? dy : ds.columns.length > 1 ? 1 : 0);
  requestAnimationFrame(() => fitWindow());
}

xSelect.addEventListener("change", () => changeAxis("x"));
ySelect.addEventListener("change", () => changeAxis("y"));

// --- matplotlib 風ナビゲーションツールバー（自前 → Plotly API） ---
function setDragmode(mode: "zoom" | "pan") {
  dragmode = mode;
  zoomBtn.classList.toggle("active", mode === "zoom");
  panBtn.classList.toggle("active", mode === "pan");
  if (current) Plotly.relayout(plotEl, { dragmode: mode });
}

homeBtn.addEventListener("click", () => {
  if (current) Plotly.relayout(plotEl, { "xaxis.autorange": true, "yaxis.autorange": true });
});

interface PlotElementWithHistory extends HTMLDivElement {
  on?: (event: string, callback: (eventData?: Record<string, unknown>) => void) => void;
  _fullLayout?: {
    xaxis?: PlotAxisLayout;
    yaxis?: PlotAxisLayout;
  };
}

interface PlotAxisLayout {
  range?: [number, number];
  autorange?: boolean;
  _offset?: number;
  _length?: number;
}

interface PlotViewState {
  xRange: [number, number] | null;
  yRange: [number, number] | null;
}

let viewHistory: PlotViewState[] = [];
let viewHistoryIndex = -1;
let suppressHistory = false;
let wheelHistoryTimer: number | null = null;

function readAxisRange(axis?: PlotAxisLayout) {
  if (!axis || axis.autorange || !Array.isArray(axis.range)) return null;
  return [Number(axis.range[0]), Number(axis.range[1])] as [number, number];
}

function readAxisNumericRange(axis?: PlotAxisLayout): [number, number] | null {
  if (!axis || !Array.isArray(axis.range)) return null;
  const start = Number(axis.range[0]);
  const end = Number(axis.range[1]);
  return Number.isFinite(start) && Number.isFinite(end) ? [start, end] : null;
}

function readViewState(): PlotViewState | null {
  const gd = plotEl as PlotElementWithHistory;
  if (!gd._fullLayout) return null;
  return {
    xRange: readAxisRange(gd._fullLayout.xaxis),
    yRange: readAxisRange(gd._fullLayout.yaxis),
  };
}

function sameRange(a: [number, number] | null, b: [number, number] | null) {
  if (!a || !b) return a === b;
  return Math.abs(a[0] - b[0]) < 1e-12 && Math.abs(a[1] - b[1]) < 1e-12;
}

function sameViewState(a: PlotViewState, b: PlotViewState) {
  return sameRange(a.xRange, b.xRange) && sameRange(a.yRange, b.yRange);
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function resetViewHistory() {
  const state = readViewState();
  viewHistory = state ? [state] : [];
  viewHistoryIndex = state ? 0 : -1;
  updateHistoryButtons();
}

function pushViewHistory() {
  const state = readViewState();
  if (!state) return;
  const previous = viewHistory[viewHistoryIndex];
  if (previous && sameViewState(previous, state)) return;
  viewHistory = viewHistory.slice(0, viewHistoryIndex + 1);
  viewHistory.push(state);
  viewHistoryIndex = viewHistory.length - 1;
  updateHistoryButtons();
}

function relayoutForViewState(state: PlotViewState) {
  return {
    ...(state.xRange
      ? { "xaxis.autorange": false, "xaxis.range": state.xRange }
      : { "xaxis.autorange": true }),
    ...(state.yRange
      ? { "yaxis.autorange": false, "yaxis.range": state.yRange }
      : { "yaxis.autorange": true }),
  };
}

async function runPlotHistory(direction: "undo" | "redo") {
  if (!current) return;
  const nextIndex = direction === "undo" ? viewHistoryIndex - 1 : viewHistoryIndex + 1;
  const state = viewHistory[nextIndex];
  if (!state) return;
  viewHistoryIndex = nextIndex;
  updateHistoryButtons();
  suppressHistory = true;
  try {
    await Plotly.relayout(plotEl, relayoutForViewState(state));
  } finally {
    suppressHistory = false;
  }
}

function updateHistoryButtons() {
  undoBtn.disabled = !current || viewHistoryIndex <= 0;
  redoBtn.disabled = !current || viewHistoryIndex < 0 || viewHistoryIndex >= viewHistory.length - 1;
}

function isRangeRelayout(eventData?: Record<string, unknown>) {
  if (!eventData) return false;
  return Object.keys(eventData).some((key) =>
    /^(xaxis|yaxis)\.(range|range\[\d+\]|autorange)$/.test(key),
  );
}

let plotEventsAttached = false;
function attachPlotEvents() {
  const gd = plotEl as PlotElementWithHistory;
  if (plotEventsAttached || !gd.on) return;
  gd.on("plotly_relayout", (eventData) => {
    if (!suppressHistory && isRangeRelayout(eventData)) pushViewHistory();
    updateHistoryButtons();
  });
  plotEventsAttached = true;
}

undoBtn.addEventListener("click", () => runPlotHistory("undo"));
redoBtn.addEventListener("click", () => runPlotHistory("redo"));

function handleNavigationMouseButton(event: MouseEvent) {
  if (event.button === 3) {
    event.preventDefault();
    event.stopPropagation();
    runPlotHistory("undo");
  } else if (event.button === 4) {
    event.preventDefault();
    event.stopPropagation();
    runPlotHistory("redo");
  }
}

window.addEventListener("mousedown", handleNavigationMouseButton, { capture: true });
window.addEventListener("mouseup", handleNavigationMouseButton, { capture: true });
window.addEventListener("auxclick", handleNavigationMouseButton, { capture: true });

plotEl.addEventListener("wheel", (event) => {
  if (!current) return;
  const gd = plotEl as PlotElementWithHistory;
  const xaxis = gd._fullLayout?.xaxis;
  const yaxis = gd._fullLayout?.yaxis;
  const xRange = readAxisNumericRange(xaxis);
  const yRange = readAxisNumericRange(yaxis);
  if (!xRange || !yRange) return;

  event.preventDefault();
  event.stopPropagation();

  const rect = plotEl.getBoundingClientRect();
  const xOffset = xaxis?._offset ?? 0;
  const yOffset = yaxis?._offset ?? 0;
  const xLength = xaxis?._length ?? rect.width;
  const yLength = yaxis?._length ?? rect.height;
  const xFraction = clamp((event.clientX - rect.left - xOffset) / xLength, 0, 1);
  const yFraction = 1 - clamp((event.clientY - rect.top - yOffset) / yLength, 0, 1);
  const anchorX = xRange[0] + (xRange[1] - xRange[0]) * xFraction;
  const anchorY = yRange[0] + (yRange[1] - yRange[0]) * yFraction;
  const factor = event.deltaY < 0 ? 0.82 : 1.22;

  suppressHistory = true;
  Plotly.relayout(plotEl, {
    "xaxis.autorange": false,
    "xaxis.range": [
      anchorX - (anchorX - xRange[0]) * factor,
      anchorX + (xRange[1] - anchorX) * factor,
    ],
    "yaxis.autorange": false,
    "yaxis.range": [
      anchorY - (anchorY - yRange[0]) * factor,
      anchorY + (yRange[1] - anchorY) * factor,
    ],
  }).finally(() => {
    suppressHistory = false;
  });

  if (wheelHistoryTimer !== null) window.clearTimeout(wheelHistoryTimer);
  wheelHistoryTimer = window.setTimeout(() => {
    wheelHistoryTimer = null;
    pushViewHistory();
  }, 250);
}, { passive: false, capture: true });

panBtn.addEventListener("click", () => setDragmode("pan"));
zoomBtn.addEventListener("click", () => setDragmode("zoom"));

function setPlotMode(mode: "lines" | "markers") {
  plotMode = mode;
  if (current) {
    // 折れ線↔散布図でマーカー分の autorange 余白により範囲が変わるのを防ぐため、
    // 現在の表示範囲を保持したままモードだけ切り替える。
    const fl = (plotEl as unknown as { _fullLayout?: { xaxis?: { range?: number[] }; yaxis?: { range?: number[] } } })._fullLayout;
    const xr = fl?.xaxis?.range ? fl.xaxis.range.slice() : null;
    const yr = fl?.yaxis?.range ? fl.yaxis.range.slice() : null;
    Plotly.restyle(plotEl, { mode }, [0]);
    if (xr && yr) {
      Plotly.relayout(plotEl, { "xaxis.range": xr, "yaxis.range": yr });
    }
    lineBtn.classList.toggle("active", plotMode === "lines");
    scatterBtn.classList.toggle("active", plotMode === "markers");
  }
}
lineBtn.addEventListener("click", () => setPlotMode("lines"));
scatterBtn.addEventListener("click", () => setPlotMode("markers"));

function themeVar(name: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

// preserve を渡すと、その軸だけ現在の表示範囲を維持し、もう片方を再フィットする。
function render(preserve?: { axis: "x" | "y"; range: [number, number] }) {
  if (!current) return;
  const xi = Number(xSelect.value);
  const yi = Number(ySelect.value);
  const rows = getFilteredRows();
  const x = rows.map((r) => r[xi]);
  const y = rows.map((r) => r[yi]);

  const lineColor = themeVar("--color-plot-line");
  const frameColor = themeVar("--color-plot-frame");
  const textColor = themeVar("--color-text");
  const fontFamily = themeVar("--font-family");

  const keep = (which: "x" | "y") =>
    preserve && preserve.axis === which
      ? { autorange: false, range: preserve.range }
      : { autorange: true };

  // matplotlib 風: グリッド/ゼロラインなし、プロット領域を四角い枠で囲む
  const axis = (title: string, which: "x" | "y", titleStandoff = 4) => ({
    title: { text: title, standoff: titleStandoff },
    showgrid: false,
    zeroline: false,
    showline: true,
    mirror: "ticks",
    linecolor: frameColor,
    linewidth: 1,
    ticks: "inside",
    tickcolor: frameColor,
    ticklen: 6,
    tickwidth: 1,
    ...keep(which),
  });

  Plotly.react(
    plotEl,
    [{
      x,
      y,
      type: "scattergl",
      mode: plotMode,
      line: { width: 2.5, color: lineColor },
      marker: { size: 4, color: lineColor },
    }],
    {
      margin: { l: 60, r: 20, t: 20, b: 50 },
      paper_bgcolor: "rgba(0,0,0,0)",
      plot_bgcolor: "rgba(0,0,0,0)",
      font: { color: textColor, family: fontFamily },
      dragmode,
      xaxis: axis(current.columns[xi], "x", 3),
      yaxis: axis(current.columns[yi], "y", 5),
    },
    { responsive: true, displayModeBar: false, scrollZoom: false, showTips: false },
  ).then(() => {
    attachPlotEvents();
    resetViewHistory();
  });

  zoomBtn.classList.toggle("active", dragmode === "zoom");
  panBtn.classList.toggle("active", dragmode === "pan");
  lineBtn.classList.toggle("active", plotMode === "lines");
  scatterBtn.classList.toggle("active", plotMode === "markers");
  updateHistoryButtons();
}
updateHistoryButtons();
