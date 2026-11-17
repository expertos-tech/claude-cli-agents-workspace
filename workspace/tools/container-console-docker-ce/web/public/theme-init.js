// Applies the theme the user chose before the first paint. It must stay a classic script in the
// head, because a module runs too late, and an external file, because the CSP refuses inline
// scripts. The key and the values are those of src/components/ThemeSelect.tsx.
try {
  const stored = localStorage.getItem("container-console-docker-ce.theme");
  if (stored === "dark" || stored === "light") {
    document.documentElement.dataset.theme = stored;
  }
} catch {
  // Without storage the page follows the operating system.
}
