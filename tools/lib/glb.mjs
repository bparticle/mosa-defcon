// The named empties of a room GLB, in world space.
//
// MOSA's rooms place things with Blender empties: `find_placement__bottle.NNN`
// where a bottle lies, `<room>_placement_<slot>` and `sirial_placement_<N>`
// where a work hangs. The renderer reads them from the room GLB at runtime;
// the sync reads the same nodes here so the badge hangs and scatters things
// where the HD museum does. Only the JSON chunk is read: no geometry.
import fs from 'node:fs';

const IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

/** Column-major 4x4 multiply, a * b. */
function mul(a, b) {
  const o = new Array(16).fill(0);
  for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) for (let k = 0; k < 4; k++) o[j * 4 + i] += a[k * 4 + i] * b[j * 4 + k];
  return o;
}

function local(n) {
  if (n.matrix) return n.matrix;
  const [x, y, z, w] = n.rotation ?? [0, 0, 0, 1];
  const [sx, sy, sz] = n.scale ?? [1, 1, 1];
  const [tx, ty, tz] = n.translation ?? [0, 0, 0];
  return [
    (1 - 2 * (y * y + z * z)) * sx, 2 * (x * y + z * w) * sx, 2 * (x * z - y * w) * sx, 0,
    2 * (x * y - z * w) * sy, (1 - 2 * (x * x + z * z)) * sy, 2 * (y * z + x * w) * sy, 0,
    2 * (x * z + y * w) * sz, 2 * (y * z - x * w) * sz, (1 - 2 * (x * x + y * y)) * sz, 0,
    tx, ty, tz, 1,
  ];
}

/** Every node whose name passes `match`: [{ name, x, y, z, nx, nz }] (n = local -Z, the way an empty faces). */
export function glbEmpties(file, match) {
  const buf = fs.readFileSync(file);
  if (buf.readUInt32LE(0) !== 0x46546c67) throw new Error(`${file} is not a GLB`);
  const json = JSON.parse(buf.subarray(20, 20 + buf.readUInt32LE(12)).toString('utf8'));
  const out = [];
  const walk = (i, parent) => {
    const n = json.nodes[i];
    const m = mul(parent, local(n));
    if (n.name && match(n.name)) out.push({ name: n.name, x: m[12], y: m[13], z: m[14], nx: -m[8], nz: -m[10] });
    for (const c of n.children ?? []) walk(c, m);
  };
  for (const s of json.scenes[json.scene ?? 0].nodes) walk(s, IDENTITY);
  return out;
}
