import { invoke } from "@tauri-apps/api/core";
import { emitTo } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { applyTheme, bindThemeUpdates } from "./theme-util";

interface AxesInit {
  source_label: string;
  name: string;
  columns: string[];
  x_index: number;
  y_indices: number[];
}

const win = getCurrentWindow();
document.getElementById("win-close")?.addEventListener("click", () => win.close());
document.getElementById("win-min")?.addEventListener("click", () => win.minimize());
document.getElementById("close-btn")?.addEventListener("click", () => win.close());

bindThemeUpdates();
win.onFocusChanged(({ payload: focused }) => {
  if (focused) applyTheme();
}).catch(() => {});

const titleEl = document.getElementById("axes-title") as HTMLSpanElement;
const xSelect = document.getElementById("x-axis-select") as HTMLSelectElement;
const yList = document.getElementById("y-axis-list") as HTMLDivElement;
const addYBtn = document.getElementById("add-y-btn") as HTMLButtonElement;
const applyBtn = document.getElementById("apply-btn") as HTMLButtonElement;

let sourceLabel = "";
let columns: string[] = [];

function fillSelect(select: HTMLSelectElement, selectedIndex: number) {
  select.innerHTML = "";
  columns.forEach((name, i) => {
    const opt = document.createElement("option");
    opt.value = String(i);
    opt.textContent = name;
    opt.title = name;
    if (i === selectedIndex) opt.selected = true;
    select.appendChild(opt);
  });
}

function renumberRows() {
  yList.querySelectorAll<HTMLElement>(".axes-axis").forEach((label, i) => {
    label.textContent = `Y${i + 1}`;
  });
  yList.querySelectorAll<HTMLButtonElement>(".axes-remove").forEach((button) => {
    button.disabled = yList.children.length <= 1;
  });
}

function addYRow(selectedIndex: number) {
  const row = document.createElement("div");
  row.className = "axes-grid axes-row";

  const label = document.createElement("span");
  label.className = "axes-axis";

  const select = document.createElement("select");
  select.className = "axes-y-select";
  fillSelect(select, selectedIndex);

  const remove = document.createElement("button");
  remove.className = "axes-remove";
  remove.type = "button";
  remove.textContent = "-";
  remove.title = "Remove axis";
  remove.addEventListener("click", () => {
    row.remove();
    renumberRows();
  });

  row.append(label, select, remove);
  yList.appendChild(row);
  renumberRows();
}

function collectYIndices() {
  return Array.from(yList.querySelectorAll<HTMLSelectElement>(".axes-y-select"))
    .map((select) => Number(select.value))
    .filter((value) => Number.isInteger(value) && value >= 0 && value < columns.length);
}

function applyAxes() {
  if (!sourceLabel) return;
  const yIndices = collectYIndices();
  if (!yIndices.length) return;
  emitTo(sourceLabel, "axes-apply", {
    xIndex: Number(xSelect.value),
    yIndices,
  }).catch(() => {});
}

addYBtn.addEventListener("click", () => {
  const used = new Set(collectYIndices());
  const next = columns.findIndex((_, i) => i !== Number(xSelect.value) && !used.has(i));
  addYRow(next >= 0 ? next : Math.max(0, Number(xSelect.value)));
});
applyBtn.addEventListener("click", applyAxes);
window.addEventListener("keydown", (e) => {
  if (e.metaKey && !e.ctrlKey && !e.altKey && !e.shiftKey && e.key.toLowerCase() === "enter") {
    e.preventDefault();
    applyAxes();
  }
});

invoke<AxesInit | null>("take_axes_init").then((init) => {
  if (!init) return;
  sourceLabel = init.source_label;
  columns = init.columns;
  titleEl.textContent = `Axes — ${init.name}`;
  titleEl.title = init.name;
  fillSelect(xSelect, init.x_index);
  const ys = init.y_indices.length ? init.y_indices : [Math.min(1, columns.length - 1)];
  ys.forEach((index) => addYRow(index));
});
