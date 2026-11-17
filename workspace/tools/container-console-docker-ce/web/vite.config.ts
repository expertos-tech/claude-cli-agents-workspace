import { defineConfig } from 'vite'

// The service embeds this output with go:embed. The Makefile cleans the folder and keeps the
// tracked placeholder.html, so Vite must not empty it. The CSP refuses data: URLs, so no asset
// may be inlined. One bundle served from the same machine has no reason to be split, so the
// size warning only starts above what xterm and React weigh together. The CSS target starts at the
// first browsers with light-dark(), so the theme tokens ship as written, not as a compiled fallback.
export default defineConfig({
  base: '/',
  build: {
    outDir: '../internal/webui/dist',
    emptyOutDir: false,
    assetsInlineLimit: 0,
    cssTarget: ['chrome123', 'safari17.5', 'firefox120'],
    chunkSizeWarningLimit: 1000,
  },
})
