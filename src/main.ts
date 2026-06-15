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
const panBtn = document.getElementById("pan-btn") as HTMLButtonElement;
const zoomBtn = document.getElementById("zoom-btn") as HTMLButtonElement;
const saveBtn = document.getElementById("save-btn") as HTMLButtonElement;
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
  const w = Math.ceil(Math.max(panelEl.offsetWidth, footerEl.offsetWidth));
  const h = Math.ceil(panelEl.offsetHeight + footerEl.offsetHeight);
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
// フッター幅が変わった時（X/Y選択の出現など）や初期化時に吸着
new ResizeObserver(() => fitWindow()).observe(footerEl);

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
panBtn.addEventListener("click", () => setDragmode("pan"));
zoomBtn.addEventListener("click", () => setDragmode("zoom"));

function setPlotMode(mode: "lines" | "markers") {
  plotMode = mode;
  if (current) render();
}
lineBtn.addEventListener("click", () => setPlotMode("lines"));
scatterBtn.addEventListener("click", () => setPlotMode("markers"));

saveBtn.addEventListener("click", () => {
  if (!current) return;
  Plotly.downloadImage(plotEl, {
    format: "png",
    filename: current.name.replace(/\.[^.]+$/, ""),
    width: plotEl.clientWidth,
    height: plotEl.clientHeight,
  });
});

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
  const axis = (title: string) => ({
    title: { text: title },
    showgrid: false,
    zeroline: false,
    showline: true,
    mirror: true,
    linecolor: frameColor,
    linewidth: 1,
    ticks: "outside",
    tickcolor: frameColor,
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
      margin: { l: 60, r: 20, t: 20, b: 58 },
      paper_bgcolor: "rgba(0,0,0,0)",
      plot_bgcolor: "rgba(0,0,0,0)",
      font: { color: textColor, family: fontFamily },
      dragmode,
      xaxis: axis(current.columns[xi]),
      yaxis: axis(current.columns[yi]),
    },
    { responsive: true, displayModeBar: false },
  );

  zoomBtn.classList.toggle("active", dragmode === "zoom");
  panBtn.classList.toggle("active", dragmode === "pan");
  lineBtn.classList.toggle("active", plotMode === "lines");
  scatterBtn.classList.toggle("active", plotMode === "markers");
}
