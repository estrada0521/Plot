import { defineConfig } from "vite";

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
  },
});
