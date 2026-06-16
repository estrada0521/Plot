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

function apply(pref: ThemePref) {
  applyTheme(pref);
  // 設定ウィンドウのネイティブ枠（タイトルバー）もテーマに合わせる
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
