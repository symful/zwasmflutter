import 'dart:typed_data';

import 'src/common.dart';
import 'src/stub_backend.dart'
    if (dart.library.io) 'src/native_backend.dart'
    if (dart.library.js_interop) 'src/web_backend.dart' as backend;

export 'src/common.dart'
    show
        ZwasmEngineKind,
        ZwasmException,
        ZwasmExport,
        ZwasmExternKind,
        ZwasmHostFunction,
        ZwasmHostImport,
        ZwasmImportInfo,
        ZwasmSignature,
        ZwasmValue,
        ZwasmValueKind,
        ZwasmVfsWriteCallback;

/// Entry point for the zwasm runtime.
///
/// On the web, call [initialize] once (it loads the wasm module) before
/// creating an engine. On Android/Windows it is a no-op and may be awaited
/// unconditionally.
class Zwasm {
  Zwasm._();

  static final ZwasmBackend _backend = backend.createBackend();

  /// Loads the browser backend. No-op on native platforms.
  static Future<void> initialize() => _backend.initialize();

  /// zwasm semantic version.
  static String get version => _backend.version;

  /// Creates an independent engine (owns its compiled modules).
  static ZwasmEngine createEngine() => ZwasmEngine._(_backend.engineNew());
}

/// Controls how an instance is executed.
enum ZwasmEngineChoice { auto, jit, interp }

class ZwasmEngine {
  final int _handle;
  bool _disposed = false;

  ZwasmEngine._(this._handle);

  /// Compiles [bytes] into a module (parse + validate).
  ZwasmModule compile(Uint8List bytes) {
    _check();
    return ZwasmModule._(Zwasm._backend.moduleNew(_handle, bytes));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    Zwasm._backend.engineDelete(_handle);
  }

  void _check() {
    if (_disposed) throw StateError('ZwasmEngine has been disposed');
  }
}

class ZwasmModule {
  final int _handle;
  bool _disposed = false;
  late final List<ZwasmExport> exports = _readExports();
  late final List<ZwasmImportInfo> imports = _readImports();

  ZwasmModule._(this._handle);

  static ZwasmExternKind _kindFromCode(int code) => switch (code) {
        0 => ZwasmExternKind.function,
        1 => ZwasmExternKind.table,
        2 => ZwasmExternKind.memory,
        3 => ZwasmExternKind.global,
        _ => ZwasmExternKind.tag,
      };

  List<ZwasmExport> _readExports() {
    final b = Zwasm._backend;
    final n = b.moduleExportCount(_handle);
    return List.generate(
        n, (i) => ZwasmExport(b.moduleExportName(_handle, i),
            _kindFromCode(b.moduleExportKind(_handle, i))));
  }

  List<ZwasmImportInfo> _readImports() {
    final b = Zwasm._backend;
    final n = b.moduleImportCount(_handle);
    return List.generate(
        n,
        (i) => ZwasmImportInfo(
            b.moduleImportModule(_handle, i),
            b.moduleImportName(_handle, i),
            _kindFromCode(b.moduleImportKind(_handle, i))));
  }

  /// Instantiates the module.
  ///
  /// [fuel] and [maxMemoryPages] are metered budgets; `null` means unmetered.
  /// [wasi] installs a WASI 0.1 host (args/envs/stdio/preopens). [imports]
  /// supplies Dart implementations of the module's function imports.
  ZwasmInstance instantiate({
    ZwasmEngineChoice engine = ZwasmEngineChoice.auto,
    int? fuel,
    int? maxMemoryPages,
    ZwasmWasiConfig? wasi,
    List<ZwasmHostImport> imports = const [],
  }) {
    _check();
    final k = switch (engine) {
      ZwasmEngineChoice.auto => ZwasmEngineKind.auto,
      ZwasmEngineChoice.jit => ZwasmEngineKind.jit,
      ZwasmEngineChoice.interp => ZwasmEngineKind.interp,
    };
    return ZwasmInstance._(
      Zwasm._backend.instanceNew(
          _handle, k, fuel, maxMemoryPages, wasi?._handle, imports),
      exports,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    Zwasm._backend.moduleDelete(_handle);
  }

  void _check() {
    if (_disposed) throw StateError('ZwasmModule has been disposed');
  }
}

class ZwasmInstance {
  final int _handle;
  final List<ZwasmExport> _exports;
  bool _disposed = false;

  ZwasmInstance._(this._handle, this._exports);

  /// Export signature, or null when [name] is not an exported function.
  ZwasmSignature? signatureOf(String name) {
    _check();
    try {
      return Zwasm._backend.funcSig(_handle, name);
    } on ZwasmException catch (e) {
      if (e.code == 4) return null; // ZW_ERR_NOT_FOUND
      rethrow;
    }
  }

  /// The exported function [name], or null if it is not a function export.
  ZwasmFunction? findFunction(String name) {
    final sig = signatureOf(name);
    return sig == null ? null : ZwasmFunction._(this, name, sig);
  }

  /// First exported function, if any.
  ZwasmFunction? get mainFunction {
    for (final e in _exports) {
      if (e.kind != ZwasmExternKind.function) continue;
      final fn = findFunction(e.name);
      if (fn != null) return fn;
    }
    return null;
  }

  /// Exported memory, or null when the module has none.
  ZwasmMemory? get memory {
    _check();
    final size = Zwasm._backend.memorySize(_handle);
    return size == 0 ? null : ZwasmMemory._(this);
  }

  /// Exported global [name], or null.
  ZwasmGlobal? findGlobal(String name) {
    _check();
    final info = Uint8List(2);
    try {
      Zwasm._backend.globalInfo(_handle, name, info);
    } on ZwasmException catch (e) {
      if (e.code == 4) return null;
      rethrow;
    }
    return ZwasmGlobal._(this, name,
        ZwasmValueKind.fromCode(info[0]), info[1] != 0);
  }

  /// Sets (or clears, with null) the deterministic fuel budget.
  void setFuel(int? fuel) {
    _check();
    Zwasm._backend.setFuel(_handle, fuel);
  }

  /// Remaining fuel, or null when unmetered.
  int? get fuelRemaining {
    _check();
    final v = Zwasm._backend.fuelRemaining(_handle);
    return v < 0 ? null : v;
  }

  /// Host memory ceiling in 64 KiB pages (null clears it).
  void setMemoryLimit(int? pages) {
    _check();
    Zwasm._backend.setMemoryLimit(_handle, pages);
  }

  /// Asks a running guest to stop at its next poll point.
  void interrupt() => Zwasm._backend.interrupt(_handle);

  void clearInterrupt() => Zwasm._backend.clearInterrupt(_handle);

  /// Guest `proc_exit` status, or null if the guest did not exit.
  int? get wasiExitCode {
    final v = Zwasm._backend.wasiExitCode(_handle);
    return v < 0 ? null : v;
  }

  /// Serializes the in-memory VFS mount at [root] (e.g. `/data`).
  /// Format: u32 count, then { u32 path_len, path, u64 size, bytes }.
  Uint8List exportMount(String root) =>
      Zwasm._backend.exportMount(_handle, root);

  /// Replaces the files under [root] from an `exportMount` blob.
  void importMount(String root, Uint8List data) =>
      Zwasm._backend.importMount(_handle, root, data);

  /// Installs a write-through callback for `/data` file writes. The callback
  /// runs synchronously on the wasm thread; return normally to accept.
  void setVfsWriteCallback(ZwasmVfsWriteCallback? callback) =>
      Zwasm._backend.setVfsWriteCallback(_handle, callback);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    Zwasm._backend.instanceDelete(_handle);
  }

  void _check() {
    if (_disposed) throw StateError('ZwasmInstance has been disposed');
  }
}

class ZwasmFunction {
  final ZwasmInstance _instance;
  final String name;
  final ZwasmSignature signature;

  ZwasmFunction._(this._instance, this.name, this.signature);

  List<ZwasmValueKind> get parameterTypes => signature.params;
  List<ZwasmValueKind> get resultTypes => signature.results;

  /// Calls the export with [args].
  List<ZwasmValue> call(List<ZwasmValue> args) {
    _instance._check();
    if (args.length != signature.params.length) {
      throw ArgumentError(
          'expected ${signature.params.length} arguments, got ${args.length}');
    }
    final argsLo = <int>[];
    final argsHi = <int>[];
    for (var i = 0; i < args.length; i++) {
      if (args[i].kind != signature.params[i]) {
        throw ArgumentError(
            'argument $i is ${args[i].kind}, expected ${signature.params[i]}');
      }
      argsLo.add(args[i].lo & 0xFFFFFFFF);
      argsHi.add(args[i].hi & 0xFFFFFFFF);
    }
    final resultSlots =
        Zwasm._backend.invoke(_instance._handle, name, argsLo, argsHi);
    return [
      for (var i = 0; i < signature.results.length; i++)
        ZwasmValue.fromHalves(
            signature.results[i], resultSlots[i * 2], resultSlots[i * 2 + 1]),
    ];
  }
}

class ZwasmMemory {
  final ZwasmInstance _instance;

  ZwasmMemory._(this._instance);

  /// Size in bytes.
  int get sizeInBytes => Zwasm._backend.memorySize(_instance._handle);

  /// Size in 64 KiB pages.
  int get pages => Zwasm._backend.memoryPages(_instance._handle);

  /// A byte view. On native this aliases wasm memory (re-fetch after growth);
  /// on the web it is a copy.
  Uint8List asUint8List() => Zwasm._backend.memoryBytes(_instance._handle);

  /// Copies [data] into guest memory at [address]. Use this on web; writing to
  /// [asUint8List] only mutates a copy there.
  void write(int address, Uint8List data) =>
      Zwasm._backend.memoryWrite(_instance._handle, address, data);

  /// Copies [length] bytes from guest memory at [address].
  Uint8List read(int address, int length) =>
      Zwasm._backend.memoryRead(_instance._handle, address, length);

  /// Grows by [deltaPages], returning the previous page count, or null when
  /// the runtime refuses the growth.
  int? grow(int deltaPages) {
    final old = Zwasm._backend.memoryGrow(_instance._handle, deltaPages);
    return old < 0 ? null : old;
  }
}

class ZwasmGlobal {
  final ZwasmInstance _instance;
  final String name;
  final ZwasmValueKind kind;
  final bool mutable;

  ZwasmGlobal._(this._instance, this.name, this.kind, this.mutable);

  ZwasmValue get value {
    final halves = Zwasm._backend.globalGet(_instance._handle, name);
    return ZwasmValue.fromHalves(kind, halves[0], halves[1]);
  }

  set value(ZwasmValue v) {
    if (v.kind != kind) {
      throw ArgumentError('global is $kind, got ${v.kind}');
    }
    Zwasm._backend.globalSet(_instance._handle, name, v.lo, v.hi);
  }
}

/// WASI 0.1 host configuration.
class ZwasmWasiConfig {
  final int _handle;
  bool _disposed = false;

  ZwasmWasiConfig._(this._handle);

  factory ZwasmWasiConfig() {
    return ZwasmWasiConfig._(Zwasm._backend.wasiConfigNew());
  }

  void addArg(String arg) {
    _check();
    Zwasm._backend.wasiAddArg(_handle, arg);
  }

  void addEnv(String key, String value) {
    _check();
    Zwasm._backend.wasiAddEnv(_handle, key, value);
  }

  void inheritStdio() {
    _check();
    Zwasm._backend.wasiInheritStdio(_handle);
  }

  /// Maps [hostPath] into the guest at [guestPath] (a WASI preview1 preopen,
  /// fd 3, 4, ... in call order). Native only; unsupported on the web.
  void preopenDir(String hostPath, String guestPath) {
    _check();
    Zwasm._backend.wasiPreopenDir(_handle, hostPath, guestPath);
  }

  /// Adds a file to the in-memory WASI VFS. [guestPath] must be under
  /// `/app`, `/data`, or `/tmp`. `/app` is read-only.
  void addFile(String guestPath, Uint8List data, {bool writable = false}) {
    _check();
    Zwasm._backend.wasiAddFile(_handle, guestPath, data, writable);
  }

  /// Adds an explicit directory to the in-memory WASI VFS.
  void addDir(String guestPath, {bool writable = false}) {
    _check();
    Zwasm._backend.wasiAddDir(_handle, guestPath, writable);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    Zwasm._backend.wasiConfigDelete(_handle);
  }

  void _check() {
    if (_disposed) throw StateError('ZwasmWasiConfig has been disposed');
  }
}
