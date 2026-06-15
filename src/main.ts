import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { LogicalSize, PhysicalPosition } from "@tauri-apps/api/dpi";
import Plotly from "plotly.js-dist-min";

interface Dataset {
  name: string;
  columns: string[];
  rows: number[][];
}

const openBtn = document.getElementById("open-btn") as HTMLButtonElement;
const xSelect = document.getElementById("x-select") as HTMLSelectElement;
const ySelect = document.getElementById("y-select") as HTMLSelectElement;
const statusEl = document.getElementById("status") as HTMLSpanElement;
const plotEl = document.getElementById("plot") as HTMLDivElement;
const toolsEl = document.getElementById("tools") as HTMLDivElement;
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

let current: Dataset | null = null;
let dragmode: "zoom" | "pan" = "zoom";
let plotMode: "lines" | "markers" = "lines";

const panelEl = document.getElementById("panel") as HTMLDivElement;
const footerEl = document.querySelector(".toolbar") as HTMLElement;
let panelWidthAdjustedByUser = false;

// パネルのサイズ変化に追従して Plotly を再描画
const resizeObserver = new ResizeObserver(() => {
  if (current) Plotly.Plots.resize(plotEl);
});
resizeObserver.observe(plotEl);

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
function syncPanelWidthToFooter() {
  if (panelWidthAdjustedByUser) return;
  const footerWidth = Math.ceil(footerEl.getBoundingClientRect().width);
  if (footerWidth > 0) panelEl.style.width = `${footerWidth}px`;
}
// フッター幅が変わった時（X/Y選択の出現など）はウィンドウだけ吸着させる。
// panel 幅は起動直後だけ footer 初期幅へ合わせ、データ読み込み後の plot 幅は変えない。
new ResizeObserver(() => fitWindow()).observe(footerEl);
requestAnimationFrame(() => {
  syncPanelWidthToFooter();
  fitWindow();
});

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
    if (resizeMode === "r" || resizeMode === "c") panelWidthAdjustedByUser = true;
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

openBtn.addEventListener("click", async () => {
  const selected = await open({
    multiple: false,
    filters: [{ name: "Data", extensions: ["csv", "dat"] }],
  });
  if (typeof selected !== "string") return;

  statusEl.textContent = "";
  try {
    current = await invoke<Dataset>("read_dataset", { path: selected });
    titleEl.textContent = current.name;
    setupAxisSelectors(current);
    render();
  } catch (err) {
    statusEl.textContent = `エラー: ${err}`;
  }
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
  fill(xSelect, 0);
  fill(ySelect, ds.columns.length > 1 ? 1 : 0);
  toolsEl.hidden = false;
  requestAnimationFrame(() => fitWindow());
}

xSelect.addEventListener("change", render);
ySelect.addEventListener("change", render);

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
    Plotly.restyle(plotEl, { mode }, [0]);
    lineBtn.classList.toggle("active", plotMode === "lines");
    scatterBtn.classList.toggle("active", plotMode === "markers");
  }
}
lineBtn.addEventListener("click", () => setPlotMode("lines"));
scatterBtn.addEventListener("click", () => setPlotMode("markers"));

function themeVar(name: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

function render() {
  if (!current) return;
  const xi = Number(xSelect.value);
  const yi = Number(ySelect.value);
  const x = current.rows.map((r) => r[xi]);
  const y = current.rows.map((r) => r[yi]);

  const lineColor = themeVar("--color-plot-line");
  const frameColor = themeVar("--color-plot-frame");
  const textColor = themeVar("--color-text");
  const fontFamily = themeVar("--font-family");

  // matplotlib 風: グリッド/ゼロラインなし、プロット領域を四角い枠で囲む
  const axis = (title: string, titleStandoff = 4) => ({
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
  });

  Plotly.react(
    plotEl,
    [{
      x,
      y,
      type: "scattergl",
      mode: plotMode,
      line: { width: 1.2, color: lineColor },
      marker: { size: 4, color: lineColor },
    }],
    {
      margin: { l: 60, r: 20, t: 20, b: 50 },
      paper_bgcolor: "rgba(0,0,0,0)",
      plot_bgcolor: "rgba(0,0,0,0)",
      font: { color: textColor, family: fontFamily },
      dragmode,
      xaxis: axis(current.columns[xi], 3),
      yaxis: axis(current.columns[yi], 5),
    },
    { responsive: true, displayModeBar: false, scrollZoom: false },
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
