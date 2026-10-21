import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react(), {
    name: 'share-kit-route',
    configureServer(server) { server.middlewares.use((request, response, next) => { if (/^\/share\/?(?:\?|$)/.test(request.url)) request.url=request.url.replace(/^\/share\/?/, '/share.html'); next(); }); },
    configurePreviewServer(server) { server.middlewares.use((request, response, next) => { if (/^\/share\/?(?:\?|$)/.test(request.url)) request.url=request.url.replace(/^\/share\/?/, '/share.html'); next(); }); }
  }],
});
