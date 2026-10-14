import { getCurrentWindow } from "./native";
import { bindThemeUpdates, loadThemePref, setThemePref, type ThemePref } from "./theme-util";

const win = getCurrentWindow();

// 自前タイトルバーのウィンドウ操作
document.getElementById("win-close")?.addEventListener("click", () => win.close());
document.getElementById("win-min")?.addEventListener("click", () => win.minimize());

bindThemeUpdates();

const select = document.getElementById("theme-select") as HTMLSelectElement;
select.value = loadThemePref();
select.addEventListener("change", () => {
  setThemePref(select.value as ThemePref);
});

// エディタ（⌘E で開くアプリ）
const editorSelect = document.getElementById("editor-select") as HTMLSelectElement;
editorSelect.value = localStorage.getItem("editor") ?? "";
editorSelect.addEventListener("change", () => {
  localStorage.setItem("editor", editorSelect.value);
});
