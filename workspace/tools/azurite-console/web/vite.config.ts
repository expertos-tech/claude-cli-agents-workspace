import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// The Go program serves the build and the API on 28091. In development the
// page runs on 25174 (PoC ports start at 20000) and /api goes to the program.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 25174,
    strictPort: true,
    host: '127.0.0.1',
    proxy: { '/api': 'http://127.0.0.1:28091' },
  },
})
