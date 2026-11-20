#!/usr/bin/env node
// pnpm build          src/ → apps/mosa/, the Solana OS app folder
// pnpm check          rebuild in memory; exit 1 if the committed folder is stale
//
// A Solana OS app is a folder (vendor/solana-os/docs/LUA_API.md, "The package"):
// main.lua runs first, app.json is the manifest, and every other file ships
// with it (our modules, loaded with require). The sources go in as they are,
// comments included, so an error's line number on the badge is the line in
// src/: the App Store compiles them, and compiled code runs from flash, so
// comments cost nothing on a badge. The build adds build_info.lua and app.json.
//
// The build is reproducible (no timestamps): `pnpm check` in CI proves the
// committed apps/mosa/ is exactly what src/ produces.
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const CHECK = process.argv.includes('--check');
const OUT = 'apps/mosa';

// Solana OS limits (LUA_API.md, "The package" and "Limits").
const MAIN_LIMIT = 64 * 1024;
const FILE_LIMIT = 256 * 1024;
const TOTAL_LIMIT = 1024 * 1024;
const MAX_FILES = 64;
const PATH_OK = /^(?!.*(?:^|\/)\.)(?!.*\.(?:\/|$))[a-z0-9_\-./]{1,64}$/;

const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));
const lock = JSON.parse(fs.readFileSync(path.join(ROOT, 'mosa.lock.json'), 'utf8'));
const repo = typeof pkg.repository === 'string' ? pkg.repository : pkg.repository?.url ?? '';

const MANIFEST = {
  id: 'mosa-night-shift',
  name: 'M.O.S.A. Night Shift',
  version: pkg.version,
  author: 'Sirius Crocodile',
  summary: 'The Museum of Sirius Art after hours. Catch the thieves. See the art in HD.',
  icon: 'eye',
  accent: '7EE8A8',
  category: 'games',
  permissions: ['led', 'mesh', 'lamps', 'background'],
};

function sources() {
  const out = {};
  const walk = (dir) => {
    for (const entry of fs.readdirSync(path.join(ROOT, 'src', dir), { withFileTypes: true })) {
      const rel = dir ? `${dir}/${entry.name}` : entry.name;
      if (entry.isDirectory()) walk(rel);
      else if (rel.endsWith('.lua')) out[rel] = fs.readFileSync(path.join(ROOT, 'src', rel), 'utf8').replace(/\r\n/g, '\n');
    }
  };
  walk('');
  return out;
}

function build() {
  const files = sources();
  for (const [rel, text] of Object.entries(files)) {
    if (/\[=*\[/.test(text.replace(/"(?:[^"\\]|\\.)*"/g, '""'))) {
      throw new Error(`src/${rel}: long strings/comments ([[ ]]) are not allowed in src/`);
    }
  }
  files['build_info.lua'] =
    `-- Written by tools/bundle.mjs. v${pkg.version}, MOSA ${lock.mosa.describe}, data ${lock.data}.\n` +
    `return { version = ${JSON.stringify(pkg.version)}, mosa = ${JSON.stringify(lock.mosa.commit.slice(0, 12))}, data = ${JSON.stringify(lock.data)}, repo = ${JSON.stringify(repo.replace(/^git\+/, '').replace(/\.git$/, ''))} }\n`;
  files['app.json'] = JSON.stringify(MANIFEST, null, 2) + '\n';
  return Object.fromEntries(Object.entries(files).sort(([a], [b]) => a.localeCompare(b)).map(([rel, text]) => [`${OUT}/${rel}`, text]));
}

function validate(outputs) {
  const problems = [];
  const bundled = Object.entries(outputs).filter(([rel]) => !/\/(main\.lua|app\.json)$/.test(rel));
  const bytes = (t) => Buffer.byteLength(t);
  const main = bytes(outputs[`${OUT}/main.lua`]);
  if (main > MAIN_LIMIT) problems.push(`main.lua is ${main} bytes, over ${MAIN_LIMIT}`);
  if (bundled.length > MAX_FILES) problems.push(`${bundled.length} bundled files, over ${MAX_FILES}`);
  let total = 0;
  for (const [rel, text] of bundled) {
    const name = rel.slice(OUT.length + 1);
    total += bytes(text);
    if (bytes(text) > FILE_LIMIT) problems.push(`${name} is over ${FILE_LIMIT} bytes`);
    if (!PATH_OK.test(name) || name.split('/').length > 5) problems.push(`${name}: not a path Solana OS accepts`);
  }
  if (total > TOTAL_LIMIT) problems.push(`bundled files are ${total} bytes together, over ${TOTAL_LIMIT}`);
  if (!/^[a-z0-9-]{3,24}$/.test(MANIFEST.id)) problems.push(`app id ${MANIFEST.id}`);
  if (MANIFEST.name.length > 20) problems.push(`app name is over 20 characters`);
  if (MANIFEST.summary.length > 80) problems.push(`summary is over 80 characters (the App Store's limit)`);
  return { problems, main, total };
}

const outputs = build();
const { problems, main, total } = validate(outputs);
if (problems.length) {
  console.error(`[build] ${problems.join('; ')}`);
  process.exit(1);
}
const summary = `main.lua ${(main / 1024).toFixed(1)} of ${MAIN_LIMIT / 1024} KB, ${Object.keys(outputs).length - 2} modules ${(total / 1024).toFixed(1)} KB, v${pkg.version}`;

const existing = fs.existsSync(path.join(ROOT, OUT))
  ? fs.readdirSync(path.join(ROOT, OUT), { recursive: true, withFileTypes: true })
    .filter((e) => e.isFile())
    .map((e) => path.relative(ROOT, path.join(e.parentPath ?? e.path, e.name)).replace(/\\/g, '/'))
  : [];
const extra = existing.filter((rel) => !(rel in outputs));

if (CHECK) {
  const stale = Object.entries(outputs).filter(([rel, text]) => {
    const p = path.join(ROOT, rel);
    return !fs.existsSync(p) || fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n') !== text;
  }).map(([r]) => r);
  if (stale.length || extra.length) {
    console.error(`[build] stale: ${[...stale, ...extra].join(', ')}. Run \`pnpm build\` and commit.`);
    process.exit(1);
  }
  console.error(`[build] up to date (${summary})`);
} else {
  for (const rel of extra) fs.rmSync(path.join(ROOT, rel));
  for (const [rel, text] of Object.entries(outputs)) {
    const p = path.join(ROOT, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, text);
  }
  console.error(`[build] ${OUT}/: ${summary}`);
}
