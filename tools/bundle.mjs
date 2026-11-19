#!/usr/bin/env node
// pnpm build          src/*.lua + src/data → scripts/mosa.lua and apps/mosa/
// pnpm check          rebuild in memory; exit 1 if the committed outputs are stale
//
// Why a bundle: the Solana badge App Store installs ONE .lua file per app from
// a repo's scripts/ folder (the filename is the app id, the first `--` line is
// its description, 96 KB max). So every module is folded into package.preload
// and the store gets a single self-contained script. apps/mosa/ is the same
// code as a directory, for pushing over USB/Wi-Fi with badge-push.py.
//
// The build is reproducible (no timestamps): `pnpm check` in CI proves the
// committed scripts/mosa.lua is exactly what src/ produces.
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const CHECK = process.argv.includes('--check');
const STORE_LIMIT = 96 * 1024;

const APP_ID = 'mosa';
const APP_NAME = 'M.O.S.A. Night Shift';
const DESCRIPTION = 'M.O.S.A. Night Shift: walk the museum after hours, find the bottles, scan into the HD museum.';

// Dependency order; main last.
const MODULES = ['util', 'qr', 'ui', 'world', 'record', 'net', 'data.mosa_data', 'build_info'];

const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));
const lock = JSON.parse(fs.readFileSync(path.join(ROOT, 'mosa.lock.json'), 'utf8'));
const repo = typeof pkg.repository === 'string' ? pkg.repository : pkg.repository?.url ?? '';

function source(mod) {
  if (mod === 'build_info') {
    return `return { version = ${JSON.stringify(pkg.version)}, mosa = ${JSON.stringify(lock.mosa.commit.slice(0, 12))}, data = ${JSON.stringify(lock.data)}, repo = ${JSON.stringify(repo)} }\n`;
  }
  const file = path.join(ROOT, 'src', ...mod.split('.')) + '.lua';
  return fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
}

/** Drop full-line comments, indentation and blank lines. Safe because src/ has no long strings. */
function strip(text, name) {
  if (/\[=*\[/.test(text.replace(/"(?:[^"\\]|\\.)*"/g, '""'))) {
    throw new Error(`${name}: long strings/comments ([[ ]]) are not allowed in src/ (the bundler strips by line)`);
  }
  return text
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l !== '' && !(l.startsWith('--') && !l.startsWith('--[')))
    .join('\n');
}

function build() {
  const parts = [
    `-- ${DESCRIPTION}`,
    `-- v${pkg.version} · MOSA ${lock.mosa.describe} · data ${lock.data}${repo ? ` · ${repo.replace(/^git\+/, '').replace(/\.git$/, '')}` : ''}`,
    '-- Built by tools/bundle.mjs from src/. Edit the sources, not this file.',
  ];
  for (const mod of MODULES) {
    parts.push(`package.preload[${JSON.stringify(mod)}] = function(...)`, strip(source(mod), mod), 'end');
  }
  parts.push(strip(source('main'), 'main'));
  const script = parts.join('\n') + '\n';
  const ini = [
    `name=${APP_NAME}`,
    `version=${pkg.version}`,
    'author=Sirius Crocodile / M.O.S.A.',
    `description=${DESCRIPTION}`,
    'entry=main.lua',
    '',
  ].join('\n');
  return {
    [`scripts/${APP_ID}.lua`]: script,
    [`apps/${APP_ID}/main.lua`]: script,
    [`apps/${APP_ID}/app.ini`]: ini,
  };
}

const outputs = build();
const size = Buffer.byteLength(outputs[`scripts/${APP_ID}.lua`]);
if (size > STORE_LIMIT) {
  console.error(`[build] scripts/${APP_ID}.lua is ${size} bytes, over the store's ${STORE_LIMIT}-byte limit`);
  process.exit(1);
}

if (CHECK) {
  const stale = Object.entries(outputs).filter(([rel, text]) => {
    const p = path.join(ROOT, rel);
    return !fs.existsSync(p) || fs.readFileSync(p, 'utf8') !== text;
  });
  if (stale.length) {
    console.error(`[build] stale: ${stale.map(([r]) => r).join(', ')}. Run \`pnpm build\` and commit.`);
    process.exit(1);
  }
  console.error(`[build] up to date (${(size / 1024).toFixed(1)} KB of ${STORE_LIMIT / 1024} KB)`);
} else {
  for (const [rel, text] of Object.entries(outputs)) {
    const p = path.join(ROOT, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, text);
  }
  console.error(`[build] scripts/${APP_ID}.lua ${(size / 1024).toFixed(1)} KB of ${STORE_LIMIT / 1024} KB (${Math.round((size / STORE_LIMIT) * 100)}%), v${pkg.version}`);
}
