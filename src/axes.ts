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
  x_range?: [number, number] | null;
  y_ranges?: ([number, number] | null)[];
  twin_y_name?: string | null;
  twin_y_range?: [number, number] | null;
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
const xMinInput = document.getElementById("x-min-input") as HTMLInputElement;
const xMaxInput = document.getElementById("x-max-input") as HTMLInputElement;
const yList = document.getElementById("y-axis-list") as HTMLDivElement;
const twinYRow = document.getElementById("twin-y-row") as HTMLDivElement;
const twinYName = document.getElementById("twin-y-name") as HTMLSpanElement;
const twinYMinInput = document.getElementById("twin-y-min-input") as HTMLInputElement;
const twinYMaxInput = document.getElementById("twin-y-max-input") as HTMLInputElement;
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

function setRangeInputs(minInput: HTMLInputElement, maxInput: HTMLInputElement, range?: [number, number] | null) {
  minInput.value = range ? String(range[0]) : "";
  maxInput.value = range ? String(range[1]) : "";
}

function readRange(minInput: HTMLInputElement, maxInput: HTMLInputElement): [number, number] | null {
  const minText = minInput.value.trim();
  const maxText = maxInput.value.trim();
  if (!minText && !maxText) return null;
  const min = Number(minText);
  const max = Number(maxText);
  if (!Number.isFinite(min) || !Number.isFinite(max) || min === max) return null;
  return min < max ? [min, max] : [max, min];
}

function addYRow(selectedIndex: number, range?: [number, number] | null) {
  const row = document.createElement("div");
  row.className = "axes-grid axes-row";

  const label = document.createElement("span");
  label.className = "axes-axis";

  const select = document.createElement("select");
  select.className = "axes-y-select";
  fillSelect(select, selectedIndex);

  const minInput = document.createElement("input");
  minInput.className = "axes-range-input axes-y-min";
  minInput.type = "number";

  const maxInput = document.createElement("input");
  maxInput.className = "axes-range-input axes-y-max";
  maxInput.type = "number";
  setRangeInputs(minInput, maxInput, range);

  const remove = document.createElement("button");
  remove.className = "axes-remove";
  remove.type = "button";
  remove.textContent = "-";
  remove.title = "Remove axis";
  remove.addEventListener("click", () => {
    row.remove();
    renumberRows();
  });

  row.append(label, select, minInput, maxInput, remove);
  yList.appendChild(row);
  renumberRows();
}

function collectYIndices() {
  return Array.from(yList.querySelectorAll<HTMLSelectElement>(".axes-y-select"))
    .map((select) => Number(select.value))
    .filter((value) => Number.isInteger(value) && value >= 0 && value < columns.length);
}

function collectYRanges() {
  return Array.from(yList.querySelectorAll<HTMLElement>(".axes-row")).map((row) => {
    const minInput = row.querySelector<HTMLInputElement>(".axes-y-min");
    const maxInput = row.querySelector<HTMLInputElement>(".axes-y-max");
    return minInput && maxInput ? readRange(minInput, maxInput) : null;
  });
}

function applyAxes() {
  if (!sourceLabel) return;
  const yIndices = collectYIndices();
  if (!yIndices.length) return;
  emitTo(sourceLabel, "axes-apply", {
    xIndex: Number(xSelect.value),
    yIndices,
    xRange: readRange(xMinInput, xMaxInput),
    yRanges: collectYRanges(),
    twinYRange: twinYRow.hidden ? null : readRange(twinYMinInput, twinYMaxInput),
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
  setRangeInputs(xMinInput, xMaxInput, init.x_range);
  twinYRow.hidden = !init.twin_y_name;
  if (init.twin_y_name) {
    twinYName.textContent = init.twin_y_name;
    twinYName.title = init.twin_y_name;
    setRangeInputs(twinYMinInput, twinYMaxInput, init.twin_y_range);
  }
  const ys = init.y_indices.length ? init.y_indices : [Math.min(1, columns.length - 1)];
  ys.forEach((index, i) => addYRow(index, init.y_ranges?.[i]));
});
