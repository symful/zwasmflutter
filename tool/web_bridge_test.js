const fs = require('fs');
const vm = require('vm');
vm.runInThisContext(fs.readFileSync('web/zwasm_bridge.js', 'utf8'));
const wasm = fs.readFileSync('web/zwasm_plugin.wasm');
const addWasm = Buffer.from([
  0x00,0x61,0x73,0x6d,0x01,0x00,0x00,0x00,
  0x01,0x07,0x01,0x60,0x02,0x7f,0x7f,0x01,0x7f,
  0x03,0x02,0x01,0x00,
  0x07,0x07,0x01,0x03,0x61,0x64,0x64,0x00,0x00,
  0x0a,0x09,0x01,0x07,0x00,0x20,0x00,0x20,0x01,0x6a,0x0b,
]);
function step(name, fn) {
  try { const r = fn(); console.log(name, '=>', r); return r; }
  catch (e) { console.log(name, 'FAILED:', e.message, e.stack); process.exit(1); }
}
(async () => {
  await ZwasmBridge.init(wasm);
  step('version', () => ZwasmBridge.version());
  const e = step('engineNew', () => ZwasmBridge.engineNew());
  const m = step('moduleNew', () => ZwasmBridge.moduleNew(e, addWasm));
  step('exportCount', () => ZwasmBridge.moduleExportCount(m));
  step('exportKind', () => ZwasmBridge.moduleExportKind(m, 0));
  step('exportName', () => ZwasmBridge.moduleExportName(m, 0));
  const inst = step('instanceNew', () => ZwasmBridge.instanceNew(m, 2, -1, -1, 0));
  step('funcSig', () => Array.from(ZwasmBridge.funcSig(inst, 'add')));
  step('invoke', () => Array.from(ZwasmBridge.invoke(inst, 'add', new Uint32Array([2]), new Uint32Array([0]))));
})();
