import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  plugins: [react()],
  server: {
    // Development is short-lived and must never compete with the managed
    // Sidecar/Broker/app-server ports (18790-18792). Let the OS choose a free
    // port; Vite still prints the exact local URL and an explicit CLI --port
    // remains available when a developer has passed the host port gate.
    port: 0,
    proxy: {
      "/api": "http://127.0.0.1:39393",
    },
  },
  build: {
    // The Android shell may run on an older system WebView. Keep the served
    // product UI parseable there instead of failing with a blank page.
    target: "es2015",
    sourcemap: true,
  },
});
