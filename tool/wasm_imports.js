const fs = require('fs');
const buf = fs.readFileSync(process.argv[2]);
let p = 8;
function u32() {
  let r = 0, s = 0;
  for (;;) {
    const b = buf[p++];
    r |= (b & 0x7f) << s;
    if (!(b & 0x80)) return r >>> 0;
    s += 7;
  }
}
function name() {
  const n = u32();
  const s = buf.toString('utf8', p, p + n);
  p += n;
  return s;
}
const vt = { 0x7f: 'i32', 0x7e: 'i64', 0x7d: 'f32', 0x7c: 'f64', 0x7b: 'v128', 0x70: 'funcref', 0x6f: 'externref' };
let types = [];
let imports = [];
while (p < buf.length) {
  const id = buf[p++];
  const size = u32();
  const end = p + size;
  if (id === 1) {
    const n = u32();
    for (let i = 0; i < n; i++) {
      const form = buf[p++];
      const np = u32();
      const params = [];
      for (let j = 0; j < np; j++) params.push(vt[buf[p++]] || buf[p++]);
      const nr = u32();
      const results = [];
      for (let j = 0; j < nr; j++) results.push(vt[buf[p++]] || buf[p++]);
      types.push({ form, params, results });
    }
  } else if (id === 2) {
    const n = u32();
    for (let i = 0; i < n; i++) {
      const mod = name(), field = name();
      const kind = buf[p++];
      if (kind === 0) {
        const ti = u32();
        imports.push({ mod, field, sig: types[ti] });
      } else if (kind === 1) {
        p++; u32();
      } else if (kind === 2) {
        const flags = buf[p++]; u32(); if (flags & 1) u32();
      } else if (kind === 3) {
        p++; p++;
      } else if (kind === 4) {
        p++; u32();
      }
    }
  }
  p = end;
}
for (const im of imports) console.log(`${im.field}(${im.sig.params.join(', ')}) -> (${im.sig.results.join(', ')})`);
