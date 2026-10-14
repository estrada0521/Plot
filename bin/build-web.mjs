import { build } from 'esbuild';
import { mkdir, readFile, writeFile, copyFile, rm } from 'node:fs/promises';

await rm('dist', { recursive: true, force: true });
await mkdir('dist/assets', { recursive: true });
await build({
  entryPoints: ['src/main.ts', 'src/toolbar.ts', 'src/settings.ts', 'src/filter.ts', 'src/axes.ts'],
  outdir: 'dist/assets', bundle: true, format: 'iife', target: 'safari16.4', minify: true,
});
for (const name of ['theme', 'styles']) await copyFile(`src/${name}.css`, `dist/assets/${name}.css`);
for (const name of ['index', 'toolbar', 'settings', 'filter', 'axes']) {
  let html = await readFile(`${name}.html`, 'utf8');
  html = html.replaceAll('/src/theme.css', './assets/theme.css').replaceAll('/src/styles.css', './assets/styles.css');
  html = html.replace(/<script type="module" src="\/src\/(\w+)\.ts"><\/script>/g, '<script src="./assets/$1.js"></script>');
  await writeFile(`dist/${name}.html`, html);
}
