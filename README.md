# zwasm for Flutter

A WebAssembly runtime for Flutter, powered by [zwasm](https://github.com/zwasm/zwasm)
— a spec-compliant WebAssembly engine written in Zig. This package vendors
zwasm and exposes it through an idiomatic Dart API.

## Status

| Target | Build | Runtime verified |
| --- | --- | --- |
| Windows | ✅ `zwasm.dll` | ✅ `add(2,3)=5`, memory, globals |
| Android | ✅ `libzwasm.so` (arm64-v8a, x86_64) | ✅ ran on Android 15 / x86_64 (MuMu Player), `add(2,3)=5` |
| Web | ✅ wasm64-wasi module + JS bridge | ✅ `add(2,3)=5` in Chromium |

Both native builds and the browser module use zwasm's **interpreter** engine.
The web target is `wasm64-wasi`: zwasm assumes 64-bit `usize`, and Zig does
not ship a 32-bit wasm64 libc.

## Install

```yaml
dependencies:
  zwasm:
    git:
      url: https://github.com/your-org/zwasm-flutter.git
```

## Quick start

```dart
import 'package:zwasm/zwasm.dart';

Future<void> run(Uint8List wasmBytes) async {
  await Zwasm.initialize(); // no-op on Android/Windows, loads wasm on web

  final engine = Zwasm.createEngine();
  final module = engine.compile(wasmBytes);
  final instance = module.instantiate(
    engine: ZwasmEngineChoice.interp,
    fuel: null,          // null = unmetered
    maxMemoryPages: null,
  );

  final add = instance.findFunction('add')!;
  final result = add.call([ZwasmValue.i32(2), ZwasmValue.i32(3)]);
  print('add(2, 3) = ${result.single.asInt}');

  instance.dispose();
  module.dispose();
  engine.dispose();
}
```

Use `ZwasmEngineChoice.auto` to let zwasm pick JIT where available (native) and
fall back to the interpreter. On the web the engine is always the
interpreter.

## API

* `Zwasm.version` — zwasm semantic version.
* `Zwasm.initialize()` — loads the web backend (no-op natively). Call once
  before creating an engine; safe to await on every platform.
* `ZwasmEngine` — `compile(Uint8List)` → `ZwasmModule`, `dispose()`.
* `ZwasmModule` — `exports` (`List<ZwasmExport>`), `imports`
  (`List<ZwasmImportInfo>`), `instantiate(...)`, `dispose()`.
  * `instantiate({engine, fuel, maxMemoryPages, wasi, imports})`
* `ZwasmInstance` — `signatureOf(name)`, `findFunction(name)`,
  `mainFunction`, `memory`, `findGlobal(name)`, `setFuel`, `fuelRemaining`,
  `setMemoryLimit`, `interrupt`, `clearInterrupt`, `wasiExitCode`,
  `exportMount(root)`, `dispose()`.
* `ZwasmFunction` — `parameterTypes`, `resultTypes`, `call(List<ZwasmValue>)`.
* `ZwasmMemory` — `sizeInBytes`, `pages`, `asUint8List()`, `grow(deltaPages)`.
* `ZwasmGlobal` — `kind`, `mutable`, `value` (get/set).
* `ZwasmHostImport` — `module`, `name`, `params`, `results`, `function`:
  a Dart implementation of one host import.
* `ZwasmWasiConfig` — `addArg`, `addEnv`, `inheritStdio`, `preopenDir`,
  `dispose()`.
* `ZwasmValue` — `i32`, `i64`, `f32`, `f64`, `funcref`, `externref`;
  `asInt`, `asDouble`.
* `ZwasmException` — thrown for compile / instantiate / trap / binding errors.
  `isWasiExit` is true for a guest `proc_exit`; read
  `instance.wasiExitCode` for the status.

### Values and 64-bit precision

Values cross the ABI as two 32-bit halves, so `f64` and `i64` are exact on
every platform. `ZwasmValue.asInt` for an `i64` above 2^53 is lossy on the web
(Dart web integers are JavaScript numbers); use `asDouble` for large floats.

### Host imports

A module's function imports can be implemented in Dart. Signatures must match
the module's declared types exactly; the callback runs synchronously on the
wasm thread and must not call back into the same instance.

```dart
final instance = module.instantiate(
  imports: [
    ZwasmHostImport(
      module: 'env',
      name: 'add',
      params: const [ZwasmValueKind.i32, ZwasmValueKind.i32],
      results: const [ZwasmValueKind.i32],
      function: (args) => [
        ZwasmValue.i32(args[0].asInt + args[1].asInt),
      ],
    ),
  ],
);
```

Inspect imports before instantiating with `module.imports`. Host imports are
implemented for native FFI targets (Windows, Android, Linux); the web backend
throws `UnsupportedError` because the JS bridge cannot pass a wasm callback
pointer yet.

### WASI

```dart
final wasi = ZwasmWasiConfig()
  ..addArg('prog')
  ..addEnv('MODE', 'test')
  ..inheritStdio();

final instance = module.instantiate(wasi: wasi);
instance.findFunction('_start')!.call([]); // a WASI command exits via proc_exit
print(instance.wasiExitCode);              // 0
```

`ZwasmWasiConfig` is only read during `instantiate`; dispose it afterwards.

#### Preopened directories

```dart
final wasi = ZwasmWasiConfig()..preopenDir('.', '/sandbox');
```

Native only, and **disabled on Windows**: after a preopen is materialized,
zwasm's `std.Io` teardown crashes the process when the Dart runtime exits.
The shim still exposes `zw_wasi_config_preopen_dir`, but the Dart backend
throws `UnsupportedError` on Windows until the upstream issue is fixed. Use
the in-memory VFS instead. Web has no host directories, so preopens are
unsupported there too.

### In-memory WASI VFS

For cartridges, use the in-memory filesystem instead of host preopens:

```dart
final wasi = ZwasmWasiConfig()
  ..addFile('/app/hello.txt', Uint8List.fromList(utf8.encode('hello')))
  ..addDir('/data', writable: true);

final instance = module.instantiate(wasi: wasi);
// ... run the cart ...
final data = instance.exportMount('/data');
```

Mounts: `/app` read-only, `/data` and `/tmp` writable. There is no host path
involved and no `std.Io`; the same code works on native and web.

`exportMount(root)` returns:
`u32 count`, then per file `{ u32 path_len, path, u64 size, bytes }`.
The host can persist that blob per profile/cart and restore it later.

## Web setup

The web backend is a wasm64 module plus a small JavaScript bridge. Add the
bridge **before** `flutter_bootstrap.js` in `web/index.html`:

```html
<script src="assets/packages/zwasm/web/zwasm_bridge.js"></script>
<script src="flutter_bootstrap.js" async></script>
```

`Zwasm.initialize()` then loads `assets/packages/zwasm/web/zwasm_plugin.wasm`
from the package assets. The bridge registers a single frozen global,
`globalThis.ZwasmBridge` (`apiVersion: 1`, `abi: 'wasm64-wasi-interp'`);
`Zwasm.initialize()` verifies the version before use.

Requirements: a browser with **WebAssembly memory64** support (current
Chromium / Edge / Firefox; Safari support varies).

## Building

The Zig toolchain is the only extra prerequisite (`zig` 0.17 on `PATH`).
Flutter's CMake/Gradle build invokes:

```bash
cd src/zwasm
zig build plugin-lib -Doptimize=ReleaseSafe -Dtarget=<target>
```

where `<target>` is `x86_64-windows-msvc`, `aarch64-linux-android`, or
`x86_64-linux-android`. Android is limited to `arm64-v8a` and `x86_64`
(see `android/build.gradle`); 32-bit ABIs are not supported by zwasm.

Rebuild the browser module and copy it into the package:

```bash
cd src/zwasm
zig build plugin-wasm
cp zig-out/bin/zwasm_plugin.wasm ../../web/zwasm_plugin.wasm
```

`plugin-lib` is built with PIC and single-threaded code so Android can link it
into a shared library (Bionic has no general-dynamic TLS stub).

## Testing

Windows (loads the plugin DLL built by `flutter build windows`):

```bash
cd example
flutter build windows --debug
set PATH=%CD%\build\windows\x64\runner\Debug;%PATH%
dart run tool/smoke_test.dart
```

Android (MuMu Player over adb, port from the emulator config):

```bash
adb connect 127.0.0.1:16384
cd example
flutter run -d 127.0.0.1:16384 -t lib/smoke.dart
adb -s 127.0.0.1:16384 logcat -s flutter
```

Web:

```bash
cd example
flutter build web --release -t lib/smoke.dart
python -m http.server 8088 --directory build/web
# open http://localhost:8088
```

You can also exercise the bridge without Flutter:

```bash
node tool/web_bridge_test.js
```

## Upstream notes

The port needed a handful of zwasm-side changes (wasm64 allocator seam, JIT
comptime gates, function-alignment guard, a zero-length-array fix, and a
PIC/single-threaded build). `docs/UPSTREAM.md` explains which issues belong to
this bridge, which belong to zwasm, and which belong to the Zig/wasm
toolchain — and lists the patches worth contributing upstream.

## License

This plugin is MIT licensed. Vendored zwasm is Apache-2.0 — see
`src/zwasm/LICENSE`.
