// Read a Night Shift report code (the `?shift=` on a badge's report QR).
//
// This is the reference decoder for the museum side (docs/MOSA-INTEGRATION.md):
// copy it into apps/api when the /at/defcon landing learns to read shifts.
// Layout, most significant bit first, Crockford base32 lowercase:
//   4 bits   format (1)
//   16 bits  rooms visited, by registry index (mosa.lock.json registry.rooms)
//   N bits   pieces found, by registry index (registry.pieces), N = registry length
//
// The code is NOT proof of anything: the app is open source and anyone can
// write any code. Treat it as a claim; see docs/SOLANA.md for how a claim
// becomes trustworthy (presence beacons, then badge signatures).
const ALPHABET = '0123456789abcdefghjkmnpqrstvwxyz';

export function decodeShift(code, registry) {
  const bits = [];
  for (const ch of String(code).toLowerCase()) {
    const v = ALPHABET.indexOf(ch);
    if (v < 0) throw new Error(`not a shift code character: ${ch}`);
    for (let i = 4; i >= 0; i--) bits.push((v >> i) & 1);
  }
  const read = (n) => { let v = 0; for (let i = 0; i < n; i++) v = (v << 1) | (bits.shift() ?? 0); return v; };
  const format = read(4);
  if (format !== 1) throw new Error(`unknown shift format ${format}`);
  const rooms = [];
  for (let i = 0; i < 16; i++) if (read(1) && registry.rooms[i]) rooms.push(registry.rooms[i]);
  const pieces = [];
  for (let i = 0; i < registry.pieces.length; i++) if (read(1)) pieces.push(registry.pieces[i]);
  return { format, rooms, pieces };
}
