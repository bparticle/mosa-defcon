#!/usr/bin/env node
// pnpm build:web        apps/mosa/ → dist/web/night-shift-<version>-<hash>/ (+ dist/web/latest.json)
//
// The arcade cabinet's bundle (M.O.S.A.'s Janitor Room plays Night Shift on a
// screen in the room): a static, versioned folder a page can serve as it is.
//
//   host.js     tools/web/host-browser.mjs + host-core.mjs + wasmoon, one ES module
//   glue.wasm   wasmoon's Lua 5.4
//   app.json    { version, mosa, files }: the BUILT app (apps/mosa), as the badge gets it
//   index.html  the cabinet alone, for a look in a browser (not used by the museum)
//
// Run `pnpm build` first: this packs apps/mosa as committed, and refuses a stale one.
// The museum pins a version with its own `pnpm arcade:sync` (MOSA docs/ARCADE.md).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { build } from 'esbuild';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const APP = path.join(ROOT, 'apps', 'mosa');
const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));
const lock = JSON.parse(fs.readFileSync(path.join(ROOT, 'mosa.lock.json'), 'utf8'));

execFileSync(process.execPath, [path.join(ROOT, 'tools', 'bundle.mjs'), '--check'], { stdio: 'inherit' });

const TMP = path.join(ROOT, 'dist', 'web', '.next');
fs.rmSync(TMP, { recursive: true, force: true });
fs.mkdirSync(TMP, { recursive: true });
let OUT = TMP;

const files = {};
for (const rel of fs.readdirSync(APP, { recursive: true })) {
  const name = String(rel).split(path.sep).join('/');
  const file = path.join(APP, name);
  if (fs.statSync(file).isFile() && name.endsWith('.lua')) files[name] = fs.readFileSync(file, 'utf8');
}
const app = { version: pkg.version, mosa: lock.mosa?.commit ?? lock.source?.mosa ?? null, files };
fs.writeFileSync(path.join(OUT, 'app.json'), JSON.stringify(app));

await build({
  entryPoints: [path.join(ROOT, 'tools', 'web', 'host-browser.mjs')],
  outfile: path.join(OUT, 'host.js'),
  bundle: true,
  format: 'esm',
  platform: 'browser',
  // wasmoon's Node branch (never taken in a page) names these; leave them unresolved.
  external: ['url', 'module', 'fs', 'path'],
  target: 'es2022',
  minify: true,
  legalComments: 'eof',
  logLevel: 'warning',
});
fs.copyFileSync(path.join(ROOT, 'node_modules', 'wasmoon', 'dist', 'glue.wasm'), path.join(OUT, 'glue.wasm'));
fs.copyFileSync(path.join(ROOT, 'tools', 'web', 'index.html'), path.join(OUT, 'index.html'));

// The folder is named by version AND content: an unreleased build between two versions never
// takes a released one's name, and a page may cache a folder forever.
const hash = crypto.createHash('sha256');
for (const f of ['host.js', 'glue.wasm', 'app.json']) hash.update(fs.readFileSync(path.join(TMP, f)));
const name = `night-shift-${pkg.version}-${hash.digest('hex').slice(0, 8)}`;
OUT = path.join(ROOT, 'dist', 'web', name);
fs.rmSync(OUT, { recursive: true, force: true });
fs.renameSync(TMP, OUT);
fs.writeFileSync(path.join(ROOT, 'dist', 'web', 'latest.json'), JSON.stringify({ name, version: pkg.version }) + String.fromCharCode(10));

const kb = (f) => (fs.statSync(path.join(OUT, f)).size / 1024).toFixed(1);
console.log(`[build:web] ${path.relative(ROOT, OUT)}: host.js ${kb('host.js')} KB, glue.wasm ${kb('glue.wasm')} KB, app.json ${kb('app.json')} KB`);
