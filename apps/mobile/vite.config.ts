import { defineConfig } from "vite";

export default defineConfig({
  base: "./",
  root: "src",
  build: {
    emptyOutDir: true,
    outDir: "../dist",
    sourcemap: true,
    target: "es2015",
  },
});
