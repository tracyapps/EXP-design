import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// Library build keeps svelte external; `--mode preview` bundles it.
export default defineConfig(({ mode }) => {
  const preview = mode === 'preview';
  return {
    plugins: [svelte()],
    build: {
      emptyOutDir: false,
      minify: preview,
      lib: {
        entry: preview ? 'src/preview.ts' : 'src/index.ts',
        formats: ['es'],
        fileName: () => (preview ? 'preview.js' : 'index.js'),
      },
      rollupOptions: { external: preview ? [] : [/^svelte($|\/)/] },
    },
  };
});
