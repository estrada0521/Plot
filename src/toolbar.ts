import { invoke } from "./native";

declare global { interface Window { plotToolbar: (state: { html: string; theme: string; values: Record<string, string> }) => void } }
window.plotToolbar = ({ html, theme, values }) => {
  document.documentElement.dataset.theme = theme;
  document.body.innerHTML = html;
  for (const [id, value] of Object.entries(values)) {
    (document.getElementById(id) as HTMLSelectElement).value = value;
  }
};
document.addEventListener("click", (event) => {
  const button = (event.target as HTMLElement).closest("button");
  if (button && !button.disabled) invoke("toolbar_action", { id: button.id });
});
document.addEventListener("change", (event) => {
  const select = event.target as HTMLSelectElement;
  invoke("toolbar_action", { id: select.id, value: select.value });
});
window.addEventListener("keydown", (event) => {
  const editing = event.target instanceof Element && event.target.closest("input, select, textarea, [contenteditable=true]");
  const arrow = !editing && !event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey && ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key);
  const shortcut = event.metaKey && !event.ctrlKey && !event.altKey && ["c", "x", "y", "s"].includes(event.key.toLowerCase());
  if (arrow || shortcut) {
    event.preventDefault();
    invoke("toolbar_key", { key: event.key, metaKey: event.metaKey, shiftKey: event.shiftKey, altKey: event.altKey });
  }
});
invoke("toolbar_ready");

document.addEventListener("copy", (event) => {
  event.preventDefault();
  invoke("toolbar_key", { key: "c", metaKey: true });
});
