import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

// Library build: Vue stays a peer dependency. `vite build --mode preview`
// bundles Vue into dist/preview.js for the comparison page.
export default defineConfig(({ mode }) => {
  const preview = mode === 'preview';
  return {
    plugins: [vue()],
    define: { 'process.env.NODE_ENV': JSON.stringify('production') },
    build: {
      emptyOutDir: false,
      minify: preview,
      lib: {
        entry: preview ? 'src/preview.ts' : 'src/index.ts',
        formats: ['es'],
        fileName: () => (preview ? 'preview.js' : 'index.js'),
      },
      rollupOptions: { external: preview ? [] : ['vue'] },
    },
  };
});
