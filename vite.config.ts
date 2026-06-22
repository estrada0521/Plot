import { defineConfig } from "vite";
import { resolve } from "node:path";

// Tauri は固定ポート 1420 を期待する
export default defineConfig({
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
  },
  build: {
    target: "es2021",
    outDir: "dist",
    rollupOptions: {
      input: {
        main: resolve(__dirname, "index.html"),
        settings: resolve(__dirname, "settings.html"),
        filter: resolve(__dirname, "filter.html"),
        axes: resolve(__dirname, "axes.html"),
      },
    },
  },
});
