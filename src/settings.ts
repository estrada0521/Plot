import { emit } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import {
  applyTheme,
  loadThemePref,
  onSystemThemeChange,
  resolveTheme,
  saveThemePref,
  type ThemePref,
} from "./theme-util";

const win = getCurrentWindow();

// 自前タイトルバーのウィンドウ操作
document.getElementById("win-close")?.addEventListener("click", () => win.close());
document.getElementById("win-min")?.addEventListener("click", () => win.minimize());

function apply(pref: ThemePref) {
  applyTheme(pref);
  win.setTheme(resolveTheme(pref)).catch(() => {});
}

let pref = loadThemePref();
apply(pref);

const select = document.getElementById("theme-select") as HTMLSelectElement;
select.value = pref;
select.addEventListener("change", () => {
  pref = select.value as ThemePref;
  saveThemePref(pref);
  apply(pref);
  emit("theme-changed", pref).catch(() => {});
});

onSystemThemeChange(() => {
  if (pref === "system") apply(pref);
});

// エディタ（⌘E で開くアプリ）
const editorSelect = document.getElementById("editor-select") as HTMLSelectElement;
editorSelect.value = localStorage.getItem("editor") ?? "";
editorSelect.addEventListener("change", () => {
  localStorage.setItem("editor", editorSelect.value);
});
