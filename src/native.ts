declare global {
  interface Window {
    plotLabel: string;
    webkit: { messageHandlers: { plot: { postMessage(message: unknown): Promise<unknown> } } };
    plotEvent: (event: string, payload: unknown) => void;
  }
}

type Handler = (event: { payload: any }) => void;
const handlers = new Map<string, Set<Handler>>();
window.plotEvent = (event, payload) => {
  for (const handler of handlers.get(event) ?? []) handler({ payload });
};

export async function invoke<T = void>(command: string, args: object = {}): Promise<T> {
  return await window.webkit.messageHandlers.plot.postMessage({ command, args }) as T;
}
export async function listen<T>(event: string, handler: (event: { payload: T }) => void, _options?: object) {
  const set = handlers.get(event) ?? new Set();
  set.add(handler);
  handlers.set(event, set);
  return () => set.delete(handler);
}
export function emit(event: string, payload: unknown) { return invoke("emit", { event, payload }); }
export function emitTo(target: string, event: string, payload: unknown) {
  return invoke("emit", { target, event, payload });
}
export function open(options: object) { return invoke<string[] | string | null>("open_file", options); }
export function save(options: object) { return invoke<string | null>("save_file", options); }
export class LogicalSize { constructor(public width: number, public height: number) {} }
export class PhysicalPosition { constructor(public x: number, public y: number) {} }
export function getCurrentWindow() {
  return {
    label: window.plotLabel,
    close: () => invoke("close"),
    minimize: () => invoke("minimize"),
    isAlwaysOnTop: () => invoke<boolean>("is_pinned"),
    setAlwaysOnTop: (value: boolean) => invoke("pin", { value }),
    setSize: (size: LogicalSize) => invoke("resize", size),
    setPosition: (position: PhysicalPosition) => invoke("position", position),
    outerPosition: () => invoke<{ x: number; y: number }>("outer_position"),
    outerSize: () => invoke<{ width: number; height: number }>("outer_size"),
    scaleFactor: () => invoke<number>("scale_factor"),
    onFocusChanged: (handler: Handler) => listen("focus", handler),
  };
}
