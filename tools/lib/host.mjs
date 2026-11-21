// The headless Solana OS in Node: tests, `pnpm preview` and `pnpm play`.
//
// The host itself is host-core.mjs, which needs no Node module (the museum's
// arcade cabinet runs the same file in a browser, tools/web/). This adapter
// reads the app from a folder (default apps/mosa) or a files map, and writes
// screenshots as PNG.
import fs from 'node:fs';
import path from 'node:path';
import { PNG } from 'pngjs';
import { SolanaOS as CoreOS, WIDTH, HEIGHT } from './host-core.mjs';

export { WIDTH, HEIGHT, luaLiteral, storageFromJson } from './host-core.mjs';

export class SolanaOS extends CoreOS {
  /**
   * @param {{ dir?: string, files?: Record<string,string|Buffer>, storage?: string, storageJson?: string, seed?: number,
   *   cabinet?: { open: (url: string) => void } }} options
   *   dir: an app folder (default apps/mosa); storage: a previous run's storageDump();
   *   cabinet: play the arcade cabinet's host (`cabinet.open(url)`, tools/web/).
   */
  constructor(options = {}) {
    const dir = options.dir ?? path.resolve('apps/mosa');
    const files = options.files ?? null;
    const read = (rel) => {
      if (files) return files[rel] === undefined ? undefined : String(files[rel]);
      const p = path.join(dir, rel);
      return fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : undefined;
    };
    super({ ...options, read });
  }

  /** Write the app area as a PNG, scaled up by an integer factor. */
  screenshot(file, scale = 2) {
    const src = this.rgba();
    const png = new PNG({ width: WIDTH * scale, height: HEIGHT * scale });
    for (let y = 0; y < HEIGHT * scale; y++) {
      for (let x = 0; x < WIDTH * scale; x++) {
        const s = (((y / scale) | 0) * WIDTH + ((x / scale) | 0)) * 4;
        const d = (y * WIDTH * scale + x) * 4;
        png.data[d] = src[s]; png.data[d + 1] = src[s + 1]; png.data[d + 2] = src[s + 2]; png.data[d + 3] = 255;
      }
    }
    fs.writeFileSync(file, PNG.sync.write(png));
  }
}
