// テーマの適用・永続化・解決を全ウィンドウで共有するユーティリティ。
export type ThemePref = "light" | "dark" | "system";

const mq = window.matchMedia("(prefers-color-scheme: dark)");

export function resolveTheme(pref: ThemePref): "light" | "dark" {
  return pref === "system" ? (mq.matches ? "dark" : "light") : pref;
}

export function applyTheme(pref: ThemePref): void {
  document.documentElement.setAttribute("data-theme", resolveTheme(pref));
}

export function loadThemePref(): ThemePref {
  const v = localStorage.getItem("theme");
  return v === "light" || v === "dark" || v === "system" ? v : "system";
}

export function saveThemePref(pref: ThemePref): void {
  localStorage.setItem("theme", pref);
}

export function onSystemThemeChange(cb: () => void): void {
  mq.addEventListener("change", cb);
}
