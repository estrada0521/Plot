// テーマの適用・永続化を全ウィンドウで共有するユーティリティ（LabApp-2 と同方式）。
// CSS の data-theme と matchMedia だけで切り替える。window.setTheme は使わない
// （ネイティブ外観を固定すると system が OS に追随しなくなるため）。
import { emit, listen } from "./native";

export type ThemePref = "light" | "dark" | "system";

const KEY = "theme";
const media = window.matchMedia("(prefers-color-scheme: dark)");

export function loadThemePref(): ThemePref {
  const v = localStorage.getItem(KEY);
  return v === "light" || v === "dark" || v === "system" ? v : "system";
}

function resolved(pref: ThemePref): "light" | "dark" {
  return pref === "system" ? (media.matches ? "dark" : "light") : pref;
}

export function applyTheme(): void {
  document.documentElement.dataset.theme = resolved(loadThemePref());
}

export function setThemePref(pref: ThemePref): void {
  localStorage.setItem(KEY, pref);
  applyTheme();
  emit("theme-changed", pref).catch(() => {});
}

// 各ウィンドウで一度呼ぶ。初期適用 + OS テーマ変更 + 他ウィンドウからの変更に追随。
export function bindThemeUpdates(): void {
  applyTheme();
  media.addEventListener("change", applyTheme);
  listen<ThemePref>("theme-changed", ({ payload }) => { localStorage.setItem(KEY, payload); applyTheme(); }).catch(() => {});
}
