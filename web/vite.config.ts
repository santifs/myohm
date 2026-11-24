import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";
export default defineConfig({
  base: "./",
  plugins: [
    react(),
    VitePWA({
      registerType: "prompt",
      manifest: {
        name: "BioMess Lab",
        short_name: "BioMess",
        description: "Laboratorio docente de bioimpedancia",
        lang: "es",
        start_url: "./",
        scope: "./",
        display: "standalone",
        theme_color: "#008d8d",
        background_color: "#ffffff",
        icons: [
          {
            src: "icon.svg",
            sizes: "any",
            type: "image/svg+xml",
            purpose: "any",
          },
        ],
      },
      workbox: {
        globPatterns: ["**/*.{js,css,html,svg,png,woff2}"],
        cleanupOutdatedCaches: true,
      },
    }),
  ],
});
