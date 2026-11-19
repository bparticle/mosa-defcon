// The badge's Lua QR encoder, decoded by an independent reader (jsQR) straight
// off the emulator's framebuffer: what a phone camera would see.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import jsQR from 'jsqr';
import { HeadlessBadge, WIDTH, HEIGHT } from '../tools/lib/emulator.mjs';

const qrLua = fs.readFileSync(new URL('../src/qr.lua', import.meta.url), 'utf8');

async function render(text) {
  const b = await new HeadlessBadge().boot();
  b.install('qrt', {
    'qr.lua': qrLua,
    'main.lua': `
      local qr = require("qr")
      local code = qr.encode(${JSON.stringify(text)})
      badge.log("version " .. code.version .. " mask " .. code.mask)
      function on_draw()
        local g = badge.gfx
        g.clear(g.WHITE)
        local s = math.max(1, (230 // (code.size + 8)))
        local ox = (320 - code.size * s) // 2
        local oy = (240 - code.size * s) // 2
        for y = 0, code.size - 1 do
          for x = 0, code.size - 1 do
            if qr.dark(code, x, y) then g.fill_rect(ox + x * s, oy + y * s, s, s, g.BLACK) end
          end
        end
      end`,
  });
  await b.launch('qrt');
  await b.frames(2);
  assert.equal(b.errors.length, 0, JSON.stringify(b.errors));
  const version = Number(/version (\d+)/.exec(b.logs.join('\n'))?.[1]);
  const decoded = jsQR(new Uint8ClampedArray(b.rgba()), WIDTH, HEIGHT);
  return { decoded: decoded?.data ?? null, version };
}

const cases = [
  'https://mosa.center',
  'https://mosa.center/at/defcon',
  'https://mosa.center/at/find/bottle/bottle-barokahdimlmhr',
  'https://mosa.center/at/defcon?shift=1zzzzzzzzzzzzzzzz',
  'https://mosa.center/at/find/bottle/bottle-createdby-imrie?from=badge&shift=0123456789abcdef', // v6
  'x'.repeat(150), // v7: version information blocks
  'y'.repeat(210), // v10: 16-bit length
];

for (const text of cases) {
  test(`QR round-trips ${text.length} bytes`, async () => {
    const { decoded, version } = await render(text);
    assert.equal(decoded, text, `version ${version}`);
  });
}
