// Lets the vendored emulator (vendor/solana-badge/app/...) run under plain Node
// without touching the submodule:
//  - its bare npm imports (wasmoon, pako, upng-js, ...) resolve from this repo's
//    node_modules, so nothing is installed inside vendor/;
//  - its extensionless relative imports (written for Vite/Bun) get `.ts`.
import { pathToFileURL } from 'node:url';
import { resolve as resolvePath } from 'node:path';

const parent = pathToFileURL(resolvePath('package.json')).href;
const fromVendor = (ctx) => ctx.parentURL && ctx.parentURL.includes('/vendor/solana-badge/');

export async function resolve(specifier, context, next) {
  if (!fromVendor(context)) return next(specifier, context);
  if (/^[a-z@]/.test(specifier) && !specifier.startsWith('node:')) {
    return next(specifier, { ...context, parentURL: parent });
  }
  if (specifier.startsWith('.') && !/\.[cm]?[jt]s$/.test(specifier)) {
    for (const suffix of ['.ts', '/index.ts']) {
      try { return await next(specifier + suffix, context); } catch { /* try the next */ }
    }
  }
  return next(specifier, context);
}
