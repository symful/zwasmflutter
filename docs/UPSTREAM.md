# Where the bugs came from

This is a layer-by-layer account of every issue hit while taking zwasm to
Android, Windows and web. It separates **our bridge**, **zwasm**, and the
**Zig/wasm toolchain**, and lists the zwasm-side patches that are worth
upstreaming.

## 1. `Cannot convert a BigInt value to a number` (web)

**Layer: ours (the JS bridge).**

The wasm64 module uses `i64` for every pointer and `usize`, but `i32` for
`u32` / `u8` parameters. JavaScript must pass a `Number` to an `i32`
parameter and a `BigInt` to an `i64` parameter. The first bridge draft passed
`BigInt(index)` to `zw_module_export_kind` (whose index is `u32`), so V8
rejected the call. This is the standard WebAssembly JS API rule, not a zwasm
or Zig bug.

Fixed in `web/zwasm_bridge.js`: pointers stay `BigInt(...)`, integer enum /
index / count parameters stay plain `Number`. The bridge now also rejects an
argument-count mismatch before it can read undefined slots.

## 2. `error: expected type 'usize', found 'u64'` on `wasm32-wasi`

**Layer: zwasm (portability).**

52 errors. zwasm's runtime assumes 64-bit `usize`: decoded indices are `u64`
and are used directly as array indices, and `@ptrFromInt` receives `u64`
reference payloads. On a 32-bit wasm target those are hard type errors, and a
few are real data-model problems (a 64-bit reference handle cannot live in a
32-bit pointer).

Verdict: **out of scope for this plugin**. We target `wasm64-wasi`, where
`usize` is 64-bit and the code compiles with only the small gates below.
Fixing wasm32 would need a handle table or a lock to 32-bit indices; that is
an upstream design decision, not a patch we can safely carry. Worth filing as
"wasm32 is not supported" in their issue tracker.

## 3. `dependency on libc must be explicitly specified` on wasm64

**Layer: split — Zig toolchain + zwasm.**

Zig does not ship a wasm64 libc (`unable to provide libc for target
wasm64-wasi...`). zwasm's C ABI pins `std.heap.c_allocator`, `std.c.getenv`
and `std.c.environ`; those references cannot compile without libc.

Our shim uses the Zig facade with `std.heap.wasm_allocator`, and we replaced
the C-ABI allocator and env access with `src/platform/alloc.zig`
(`wasm_allocator` + empty environment on wasm). This is a clean upstream patch:
zwasm already has a host-injected allocator in its Zig API — the C binding
just needs the same platform seam.

## 4. JIT codegen compile errors on wasm

**Layer: zwasm.**

`engine/codegen/shared/compile.zig`, `throw_trampoline.zig`, `linker.zig`,
`thunk.zig` and the entry helpers use `@compileError` for any arch that is not
`aarch64` / `x86_64`. The interpreter engine never reaches them, but Zig still
analyzes them because they are exported through the C surface.

Upstreamable patch: gate those modules with
`switch (builtin.target.cpu.arch) { .aarch64, .x86_64 => ..., else => <stub> }`
exactly as done here. This would let any non-JIT host build the interpreter.

## 5. `target does not support function alignment`

**Layer: zwasm.**

`interp/dispatch.zig` uses `align(64)` on the hot interpreter loop (#541).
wasm rejects function alignment outright. Our patch picks an unaligned
wrapper on wasm and keeps `align(64)` on native. This is upstreamable and
should be guarded the same way.

## 6. `cannot index into empty array` in `liveness.zig`

**Layer: zwasm (genuine bug).**

`local_homing.max_homed` is 0 on wasm, so `Plan.local_idx: [max_homed]u32`
became `[0]u32`. Shared liveness code indexes `local_idx[r]` under a runtime
`count > 0` guard, which Zig still rejects at compile time. Our patch keeps
the storage at least one element wide; the array stays unused when
`max_homed == 0`. This is a real upstream fix regardless of platform.

## 7. Android link: `R_AARCH64_TLSLE_* ... cannot be used with -shared` / `__tls_get_addr`

**Layer: toolchain interaction (Zig std + Bionic).**

The archive is compiled without PIC and uses Zig std's thread-local state
(`Io.Threaded`). Linking it into an Android `.so` produces general-dynamic TLS
relocations, and the NDK link has no `__tls_get_addr` stub for them.

zwasm is explicitly single-threaded (one thread per process; only
`zwasm_instance_interrupt` is callable from another thread). Our fix builds
the plugin archive with `pic = true` and `single_threaded = true`. That is
valid for zwasm's own contract, but a first-class `-Dsingle-threaded` or
"shared-library embedding" build option would be the right upstream shape.

## 8. Windows: `Rtl*` / `Nt*` and no exports

**Layer: ours (integration).**

* The Zig archive calls ntdll (`RtlExitUserProcess`, `NtClose`, …) and
  `RtlAddVectoredExceptionHandler`; the plugin DLL must link `ntdll`.
* CMake's `WINDOWS_EXPORT_ALL_SYMBOLS` does not see symbols inside a linked
  archive, so the plugin ships `src/zwasm_plugin.def` listing the `zw_*`
  surface, plus `/WHOLEARCHIVE` to pull the archive in.

No upstream change needed.

## 9. `std.process.Environ` shape in `zwasm_wasi_config_inherit_env`

**Layer: zwasm (portability).**

The POSIX branch builds `.block = .{ .slice = ... }` while the wasm build's
`std.process.Environ` uses a different `GlobalBlock` shape. We gate the
function to `false` on wasm (there is no process environment there).

## The `globalThis` surface

The web bridge is now a **single frozen, versioned global**:

```js
globalThis.ZwasmBridge = Object.freeze({
  apiVersion: 1,
  abi: 'wasm64-wasi-interp',
  init(bytes), version(), engineNew(), ...
});
```

`Zwasm.initialize()` checks `apiVersion` before calling `init`, so a stale
script tag fails loudly instead of corrupting pointers. This is the only
stable global the plugin touches; all other state lives inside the closure.

## Upstream patch list

If you want to send this to zwasm, the changes are:

| File | Change |
| --- | --- |
| `src/platform/alloc.zig` (new) | `wasm_allocator` / empty-env seam |
| `src/api/{instance,wasi,vec,types,trap_surface,config,module_introspect,ref_base}.zig` | use `platform/alloc.zig` instead of `std.heap.c_allocator` / `std.c.*` |
| `src/zwasm.zig` | skip the C-API eager imports on wasm |
| `src/engine/codegen/shared/{compile,linker,thunk,throw_trampoline,emit_stub}.zig` | comptime-gate JIT for non-JIT hosts |
| `src/engine/codegen/shared/{entry,entry_buffer_write}.zig` | guard the inline-asm cohort clobbers |
| `src/interp/dispatch.zig` | drop `align(64)` on wasm |
| `src/ir/analysis/local_homing.zig` | storage is at least one element wide |
| `src/wasi/preview1.zig` / `src/wasi/host.zig` | unaffected; only the C-ABI env helper changed |
| `build.zig` | add `plugin-lib` / `plugin-wasm` targets (or accept a `-Dsingle-threaded`/PIC build) |

The Android/Windows build glue, Dart FFI layer, and web bridge stay in this
repository; they are not zwasm changes.

A generated unified diff for the zwasm-side changes is checked in at
`docs/zwasm-wasm64-port.patch` (19 files, no plugin-specific code).
