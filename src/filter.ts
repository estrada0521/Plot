import { invoke } from "@tauri-apps/api/core";
import { emitTo } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { applyTheme, bindThemeUpdates } from "./theme-util";

interface FilterInit {
  source_label: string;
  name: string;
  columns: string[];
}
interface FilterRule {
  col: number;
  min: number | null;
  max: number | null;
}

const win = getCurrentWindow();

// 自前タイトルバーのウィンドウ操作
document.getElementById("win-close")?.addEventListener("click", () => win.close());
document.getElementById("win-min")?.addEventListener("click", () => win.minimize());

// テーマ（設定ウィンドウからのイベントに追従）
bindThemeUpdates();
win.onFocusChanged(({ payload: focused }) => {
  if (focused) applyTheme();
}).catch(() => {});

const listEl = document.getElementById("filter-list") as HTMLDivElement;
const applyBtn = document.getElementById("apply-btn") as HTMLButtonElement;
const saveBtn = document.getElementById("save-btn") as HTMLButtonElement;
const resetBtn = document.getElementById("reset-btn") as HTMLButtonElement;

let sourceLabel = "";
const minInputs: HTMLInputElement[] = [];
const maxInputs: HTMLInputElement[] = [];

function buildRow(name: string, index: number) {
  const row = document.createElement("div");
  row.className = "filter-col-row";

  const label = document.createElement("span");
  label.className = "filter-col-name";
  label.textContent = name;
  label.title = name;

  const minInput = document.createElement("input");
  minInput.type = "number";
  minInput.className = "filter-input";
  minInput.placeholder = "min";

  const maxInput = document.createElement("input");
  maxInput.type = "number";
  maxInput.className = "filter-input";
  maxInput.placeholder = "max";

  minInputs[index] = minInput;
  maxInputs[index] = maxInput;

  row.append(label, minInput, maxInput);
  listEl.appendChild(row);
}

function collectRules(): FilterRule[] {
  const rules: FilterRule[] = [];
  minInputs.forEach((minInput, i) => {
    const maxInput = maxInputs[i];
    const minVal = minInput.value.trim();
    const maxVal = maxInput.value.trim();
    const min = minVal === "" ? null : Number(minVal);
    const max = maxVal === "" ? null : Number(maxVal);
    if (min === null && max === null) return;
    if ((min !== null && Number.isNaN(min)) || (max !== null && Number.isNaN(max))) return;
    rules.push({ col: i, min, max });
  });
  return rules;
}

applyBtn.addEventListener("click", () => {
  if (!sourceLabel) return;
  emitTo(sourceLabel, "filter-apply", collectRules()).catch(() => {});
});

// 全体リセット: 全列の入力をクリアし、プロットも元データ全体に戻す。
resetBtn.addEventListener("click", () => {
  minInputs.forEach((i) => (i.value = ""));
  maxInputs.forEach((i) => (i.value = ""));
  if (sourceLabel) emitTo(sourceLabel, "filter-apply", []).catch(() => {});
});

function requestSave() {
  if (!sourceLabel) return;
  emitTo(sourceLabel, "filter-save", {}).catch(() => {});
}
saveBtn.addEventListener("click", requestSave);
window.addEventListener("keydown", (e) => {
  if (e.metaKey && !e.ctrlKey && !e.altKey && !e.shiftKey && e.key.toLowerCase() === "s") {
    e.preventDefault();
    requestSave();
  }
});

const titleEl = document.getElementById("filter-title") as HTMLSpanElement;

invoke<FilterInit | null>("take_filter_init").then((init) => {
  if (!init) return;
  sourceLabel = init.source_label;
  titleEl.textContent = `Filter — ${init.name}`;
  titleEl.title = init.name;
  init.columns.forEach((name, i) => buildRow(name, i));
});
