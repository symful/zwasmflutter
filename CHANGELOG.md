## Unreleased

* Add Dart host imports (`ZwasmHostImport`) and `ZwasmModule.imports`
  introspection.
* Add an in-memory WASI VFS (`ZwasmWasiConfig.addFile/addDir`): `/app`
  read-only, `/data` + `/tmp` writable. No host preopens, no `std::Io`;
  native and web.
* Add `ZwasmInstance.exportMount(root)` for save persistence.
* Add `ZwasmInstance.importMount(root, blob)` for save restore.
* Add `ZwasmInstance.setVfsWriteCallback` for write-through host persistence.
* Add web host imports: the JS bridge dispatches wasm host calls into Dart.
* Add web VFS write-through through a second JS import.
* Normalize 32-bit host-import arguments (clear the high half).
* Include the import's module and name in host-call failure messages.
* Add `ZwasmMemory.read` / `ZwasmMemory.write` for host imports (bridge v7).
* Bootstrap the `src/zwasm` submodule when building from a pub git dependency.
* Add `ZwasmWasiConfig.preopenDir` (native; Windows disabled pending a
  `std.Io` teardown fix).
* Fix module lifetime: the shim now owns a copy of the compile input because
  zwasm's parser borrows section bodies from it.
* Keep the `Linker` and host-call contexts alive for the instance lifetime.
* Add the `zw_instance_new_with_imports`, `zw_module_import_*`,
  `zw_instance_export_mount`, and `zw_wasi_config_*` C exports.
* Bump the web bridge API to version 4 (imports, VFS, export).

## 0.0.1

* TODO: Describe initial release.
