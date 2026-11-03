import { defineConfig } from "vite";

export default defineConfig({
  root: "src/ui",
  base: "./",
  build: {
    outDir: "../../dist",
    emptyOutDir: true,
  },
  server: {
    // The main process loads http://127.0.0.1:5173 in dev, so bind IPv4 rather than whatever "localhost" resolves to.
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
  },
});
