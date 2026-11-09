import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'common.dart';

const String _libName = 'zwasm';

DynamicLibrary _openLibrary() {
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  throw UnsupportedError('zwasm does not support ${Platform.operatingSystem}');
}

final DynamicLibrary _lib = _openLibrary();

Pointer<Uint8> Function(int) _allocFn() => _lib.lookupFunction<
    Pointer<Uint8> Function(Size), Pointer<Uint8> Function(int)>('zw_alloc');
void Function(Pointer<Uint8>, int) _freeFn() => _lib.lookupFunction<
    Void Function(Pointer<Uint8>, Size),
    void Function(Pointer<Uint8>, int)>('zw_free');

class NativeZwasmBackend implements ZwasmBackend {
  NativeZwasmBackend() {
    _alloc = _allocFn();
    _free = _freeFn();
    _versionLen = _lib.lookupFunction<Uint32 Function(), int Function()>(
        'zw_version_len');
    _versionPtr = _lib.lookupFunction<Pointer<Uint8> Function(),
        Pointer<Uint8> Function()>('zw_version');
    _lastCode = _lib.lookupFunction<Int32 Function(), int Function()>(
        'zw_last_error_code');
    _lastMessage = _lib.lookupFunction<
        IntPtr Function(Pointer<Uint8>, Size),
        int Function(Pointer<Uint8>, int)>('zw_last_error_message');

    _engineNew =
        _lib.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'zw_engine_new');
    _engineDelete = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('zw_engine_delete');
    _moduleNew = _lib.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Size),
        Pointer<Void> Function(
            Pointer<Void>, Pointer<Uint8>, int)>('zw_module_new');
    _moduleDelete = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('zw_module_delete');
    _exportCount = _lib.lookupFunction<
        Uint32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('zw_module_export_count');
    _exportKind = _lib.lookupFunction<
        Uint8 Function(Pointer<Void>, Uint32),
        int Function(Pointer<Void>, int)>('zw_module_export_kind');
    _exportName = _lib.lookupFunction<
        Uint32 Function(Pointer<Void>, Uint32, Pointer<Uint8>, Size),
        int Function(Pointer<Void>, int, Pointer<Uint8>,
            int)>('zw_module_export_name');

    _wasiNew = _lib.lookupFunction<Pointer<Void> Function(),
        Pointer<Void> Function()>('zw_wasi_config_new');
    _wasiDelete = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('zw_wasi_config_delete');
    _wasiAddArg = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Size),
        int Function(Pointer<Void>, Pointer<Uint8>, int)>(
        'zw_wasi_config_add_arg');
    _wasiAddEnv = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint8>, Size),
        int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>,
            int)>('zw_wasi_config_add_env');
    _wasiStdio = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('zw_wasi_config_inherit_stdio');

    _instanceNew = _lib.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint8, Int64, Int64, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, int, int, int,
            Pointer<Void>)>('zw_instance_new');
    _instanceDelete = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('zw_instance_delete');
    _funcSig = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint8>,
            Pointer<Uint32>, Pointer<Uint32>),
        int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>,
            Pointer<Uint32>, Pointer<Uint32>)>('zw_instance_func_sig');
    _invoke = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint64>,
            Uint32, Pointer<Uint64>, Uint32),
        int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>, int,
            Pointer<Uint64>, int)>('zw_instance_invoke');
    _wasiExit = _lib.lookupFunction<Int64 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('zw_instance_wasi_exit_code');

    _setFuel = _lib.lookupFunction<
        Void Function(Pointer<Void>, Int64),
        void Function(Pointer<Void>, int)>('zw_instance_set_fuel');
    _fuelLeft = _lib.lookupFunction<Int64 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('zw_instance_fuel_remaining');
    _setMemLimit = _lib.lookupFunction<
        Void Function(Pointer<Void>, Int64),
        void Function(Pointer<Void>, int)>('zw_instance_set_memory_limit');
    _interrupt = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('zw_instance_interrupt');
    _clearInterrupt = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('zw_instance_clear_interrupt');

    _memSize = _lib.lookupFunction<Uint64 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('zw_instance_memory_size');
    _memPages = _lib.lookupFunction<Uint32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('zw_instance_memory_pages');
    _memData = _lib.lookupFunction<Uint64 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('zw_instance_memory_data');
    _memGrow = _lib.lookupFunction<
        Int64 Function(Pointer<Void>, Uint32),
        int Function(Pointer<Void>, int)>('zw_instance_memory_grow');

    _globalInfo = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint8>,
            Pointer<Uint8>),
        int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>,
            Pointer<Uint8>)>('zw_instance_global_info');
    _globalGet = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Uint64>),
        int Function(Pointer<Void>, Pointer<Uint8>, int,
            Pointer<Uint64>)>('zw_instance_global_get');
    _globalSet = _lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Uint64),
        int Function(Pointer<Void>, Pointer<Uint8>, int,
            int)>('zw_instance_global_set');
  }

  late final Pointer<Uint8> Function(int) _alloc;
  late final void Function(Pointer<Uint8>, int) _free;
  late final int Function() _versionLen;
  late final Pointer<Uint8> Function() _versionPtr;
  late final int Function() _lastCode;
  late final int Function(Pointer<Uint8>, int) _lastMessage;

  late final Pointer<Void> Function() _engineNew;
  late final void Function(Pointer<Void>) _engineDelete;
  late final Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int) _moduleNew;
  late final void Function(Pointer<Void>) _moduleDelete;
  late final int Function(Pointer<Void>) _exportCount;
  late final int Function(Pointer<Void>, int) _exportKind;
  late final int Function(Pointer<Void>, int, Pointer<Uint8>, int) _exportName;

  late final Pointer<Void> Function() _wasiNew;
  late final void Function(Pointer<Void>) _wasiDelete;
  late final int Function(Pointer<Void>, Pointer<Uint8>, int) _wasiAddArg;
  late final int Function(
      Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>, int) _wasiAddEnv;
  late final void Function(Pointer<Void>) _wasiStdio;

  late final Pointer<Void> Function(
          Pointer<Void>, int, int, int, Pointer<Void>) _instanceNew;
  late final void Function(Pointer<Void>) _instanceDelete;
  late final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>,
      Pointer<Uint32>, Pointer<Uint32>) _funcSig;
  late final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>,
      int, Pointer<Uint64>, int) _invoke;
  late final int Function(Pointer<Void>) _wasiExit;

  late final void Function(Pointer<Void>, int) _setFuel;
  late final int Function(Pointer<Void>) _fuelLeft;
  late final void Function(Pointer<Void>, int) _setMemLimit;
  late final void Function(Pointer<Void>) _interrupt;
  late final void Function(Pointer<Void>) _clearInterrupt;

  late final int Function(Pointer<Void>) _memSize;
  late final int Function(Pointer<Void>) _memPages;
  late final int Function(Pointer<Void>) _memData;
  late final int Function(Pointer<Void>, int) _memGrow;

  late final int Function(
      Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>,
      Pointer<Uint8>) _globalInfo;
  late final int Function(
      Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint64>) _globalGet;
  late final int Function(
      Pointer<Void>, Pointer<Uint8>, int, int) _globalSet;

  @override
  String get version {
    final len = _versionLen();
    return utf8.decode(_versionPtr().asTypedList(len), allowMalformed: true);
  }

  @override
  Future<void> initialize() async {}

  @override
  String get lastError {
    final p = _alloc(1024);
    if (p == nullptr) return '';
    try {
      final n = _lastMessage(p, 1024);
      return utf8.decode(p.asTypedList(n), allowMalformed: true);
    } finally {
      _free(p, 1024);
    }
  }

  @override
  int get lastErrorCode => _lastCode();

  Pointer<Void> _h(int handle) => Pointer<Void>.fromAddress(handle);

  @override
  int engineNew() {
    final h = _engineNew();
    if (h == nullptr) _fail();
    return h.address;
  }

  @override
  void engineDelete(int handle) => _engineDelete(_h(handle));

  @override
  int moduleNew(int engine, Uint8List bytes) {
    final buf = _alloc(bytes.isEmpty ? 1 : bytes.length);
    if (buf == nullptr) _fail();
    if (bytes.isNotEmpty) buf.asTypedList(bytes.length).setAll(0, bytes);
    try {
      final h = _moduleNew(_h(engine), buf, bytes.length);
      if (h == nullptr) _fail();
      return h.address;
    } finally {
      _free(buf, bytes.isEmpty ? 1 : bytes.length);
    }
  }

  @override
  void moduleDelete(int module) => _moduleDelete(_h(module));

  @override
  int moduleExportCount(int module) => _exportCount(_h(module));

  @override
  int moduleExportKind(int module, int index) =>
      _exportKind(_h(module), index);

  @override
  String moduleExportName(int module, int index) {
    var cap = 256;
    while (true) {
      final buf = _alloc(cap);
      if (buf == nullptr) _fail();
      final full = _exportName(_h(module), index, buf, cap);
      final name = utf8.decode(buf.asTypedList(full.clamp(0, cap)),
          allowMalformed: true);
      _free(buf, cap);
      if (full <= cap) return name;
      cap = full;
    }
  }

  @override
  int wasiConfigNew() {
    final h = _wasiNew();
    if (h == nullptr) _fail();
    return h.address;
  }

  @override
  void wasiConfigDelete(int config) => _wasiDelete(_h(config));

  @override
  void wasiAddArg(int config, String arg) {
    final b = _utf8(arg);
    final buf = _stage(b);
    try {
      if (_wasiAddArg(_h(config), buf, b.length) != 0) _fail();
    } finally {
      _unstage(buf, b.length);
    }
  }

  @override
  void wasiAddEnv(int config, String key, String value) {
    final kb = _utf8(key);
    final vb = _utf8(value);
    final kp = _stage(kb);
    final vp = _stage(vb);
    try {
      if (_wasiAddEnv(_h(config), kp, kb.length, vp, vb.length) != 0) _fail();
    } finally {
      _unstage(kp, kb.length);
      _unstage(vp, vb.length);
    }
  }

  @override
  void wasiInheritStdio(int config) => _wasiStdio(_h(config));

  @override
  int instanceNew(int module, ZwasmEngineKind engine, int? fuel,
      int? maxMemoryPages, int? wasiConfig) {
    final h = _instanceNew(
      _h(module),
      engine.index,
      fuel ?? -1,
      maxMemoryPages ?? -1,
      wasiConfig == null ? nullptr : _h(wasiConfig),
    );
    if (h == nullptr) _fail();
    return h.address;
  }

  @override
  void instanceDelete(int instance) => _instanceDelete(_h(instance));

  @override
  ZwasmSignature funcSig(int instance, String name) {
    final nb = _utf8(name);
    final np = _stage(nb);
    final kinds = _alloc(64);
    final counts = _alloc(8).cast<Uint32>();
    try {
      final rc = _funcSig(_h(instance), np, nb.length, kinds, counts, counts + 1);
      if (rc != 0) _fail();
      final params = counts[0];
      final results = counts[1];
      final all = kinds.asTypedList(64);
      return ZwasmSignature(
        List.generate(params, (i) => ZwasmValueKind.fromCode(all[i])),
        List.generate(
            results, (i) => ZwasmValueKind.fromCode(all[params + i])),
      );
    } finally {
      _unstage(np, nb.length);
      _free(kinds, 64);
      _free(counts.cast<Uint8>(), 8);
    }
  }

  @override
  List<int> invoke(int instance, String name, List<int> argsLo,
      List<int> argsHi) {
    final sig = funcSig(instance, name);
    final nb = _utf8(name);
    final np = _stage(nb);
    final ap = _alloc(argsLo.isEmpty ? 8 : argsLo.length * 8).cast<Uint64>();
    final rp = _alloc(sig.results.isEmpty ? 8 : sig.results.length * 8)
        .cast<Uint64>();
    try {
      if (argsLo.isNotEmpty) {
        final typed = ap.asTypedList(argsLo.length);
        for (var i = 0; i < argsLo.length; i++) {
          typed[i] =
              ((argsHi[i] & 0xFFFFFFFF) << 32) | (argsLo[i] & 0xFFFFFFFF);
        }
      }
      final rc = _invoke(_h(instance), np, nb.length, ap, argsLo.length, rp,
          sig.results.length);
      if (rc != 0) _fail();
      final out = <int>[];
      for (final v in rp.asTypedList(sig.results.length)) {
        out.add(v & 0xFFFFFFFF);
        out.add((v >> 32) & 0xFFFFFFFF);
      }
      return out;
    } finally {
      _unstage(np, nb.length);
      _free(ap.cast<Uint8>(), argsLo.isEmpty ? 8 : argsLo.length * 8);
      _free(rp.cast<Uint8>(), sig.results.isEmpty ? 8 : sig.results.length * 8);
    }
  }

  @override
  int wasiExitCode(int instance) => _wasiExit(_h(instance));

  @override
  void setFuel(int instance, int? fuel) =>
      _setFuel(_h(instance), fuel ?? -1);

  @override
  int fuelRemaining(int instance) => _fuelLeft(_h(instance));

  @override
  void setMemoryLimit(int instance, int? pages) =>
      _setMemLimit(_h(instance), pages ?? -1);

  @override
  void interrupt(int instance) => _interrupt(_h(instance));

  @override
  void clearInterrupt(int instance) => _clearInterrupt(_h(instance));

  @override
  int memorySize(int instance) => _memSize(_h(instance));

  @override
  int memoryPages(int instance) => _memPages(_h(instance));

  @override
  int memoryData(int instance) => _memData(_h(instance));

  @override
  int memoryGrow(int instance, int delta) => _memGrow(_h(instance), delta);

  @override
  Uint8List memoryBytes(int instance) {
    final ptr = _memData(_h(instance));
    final size = _memSize(_h(instance));
    if (ptr == 0 || size == 0) return Uint8List(0);
    return Pointer<Uint8>.fromAddress(ptr).asTypedList(size);
  }

  @override
  void globalInfo(int instance, String name, Uint8List out) {
    final nb = _utf8(name);
    final np = _stage(nb);
    final buf = _alloc(2);
    try {
      final rc =
          _globalInfo(_h(instance), np, nb.length, buf, buf + 1);
      if (rc != 0) _fail();
      out[0] = buf[0];
      out[1] = buf[1];
    } finally {
      _unstage(np, nb.length);
      _free(buf, 2);
    }
  }

  @override
  List<int> globalGet(int instance, String name) {
    final nb = _utf8(name);
    final np = _stage(nb);
    final out = _alloc(8).cast<Uint64>();
    try {
      final rc = _globalGet(_h(instance), np, nb.length, out);
      if (rc != 0) _fail();
      final v = out[0];
      return [v & 0xFFFFFFFF, (v >> 32) & 0xFFFFFFFF];
    } finally {
      _unstage(np, nb.length);
      _free(out.cast<Uint8>(), 8);
    }
  }

  @override
  void globalSet(int instance, String name, int lo, int hi) {
    final nb = _utf8(name);
    final np = _stage(nb);
    try {
      final rc = _globalSet(_h(instance), np, nb.length,
          ((hi & 0xFFFFFFFF) << 32) | (lo & 0xFFFFFFFF));
      if (rc != 0) _fail();
    } finally {
      _unstage(np, nb.length);
    }
  }

  Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

  Pointer<Uint8> _stage(Uint8List bytes) {
    final len = bytes.isEmpty ? 1 : bytes.length;
    final p = _alloc(len);
    if (p == nullptr) _fail();
    if (bytes.isNotEmpty) p.asTypedList(bytes.length).setAll(0, bytes);
    return p;
  }

  void _unstage(Pointer<Uint8> p, int len) => _free(p, len == 0 ? 1 : len);

  Never _fail() {
    final code = _lastCode();
    throw ZwasmException(code, lastError);
  }
}

ZwasmBackend createBackend() => NativeZwasmBackend();
