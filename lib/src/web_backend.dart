import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'common.dart';

@JS('ZwasmBridge')
external _Bridge get _bridge;

extension type _Bridge(JSObject _) implements JSObject {
  external int get apiVersion;
  external String get abi;
  external JSPromise<JSAny?> init(JSUint8Array bytes);
  external String version();
  external int lastErrorCode();
  external String lastErrorMessage();

  external int engineNew();
  external void engineDelete(int handle);

  external int moduleNew(int engine, JSUint8Array bytes);
  external void moduleDelete(int module);
  external int moduleExportCount(int module);
  external int moduleExportKind(int module, int index);
  external String? moduleExportName(int module, int index);

  external int moduleImportCount(int module);
  external int moduleImportKind(int module, int index);
  external String? moduleImportModule(int module, int index);
  external String? moduleImportName(int module, int index);

  external int wasiConfigNew();
  external void wasiConfigDelete(int config);
  external int wasiConfigAddArg(int config, String arg);
  external int wasiConfigAddEnv(int config, String key, String value);
  external void wasiConfigInheritStdio(int config);
  external int wasiConfigPreopenDir(
      int config, String hostPath, String guestPath);
  external int wasiConfigAddFile(
      int config, String guestPath, JSUint8Array data, int writable);
  external int wasiConfigAddDir(
      int config, String guestPath, int writable);

  external int instanceNew(
      int module, int engine, int fuel, int maxMemoryPages, int wasiConfig);
  external int instanceNewWithImports(
      int module,
      int engine,
      int fuel,
      int maxMemoryPages,
      int wasiConfig,
      JSArray modules,
      JSArray names,
      JSArray params,
      JSArray results,
      JSFunction callback);
  external int instanceSetVfsWriteCallback(
      int instance, JSFunction? callback);
  external void instanceDelete(int instance);

  external JSUint32Array? funcSig(int instance, String name);
  external JSUint32Array invoke(
      int instance, String name, JSUint32Array argsLo, JSUint32Array argsHi);
  external int wasiExitCode(int instance);

  external void setFuel(int instance, int fuel);
  external int fuelRemaining(int instance);
  external void setMemoryLimit(int instance, int pages);
  external void interrupt(int instance);
  external void clearInterrupt(int instance);

  external int memorySize(int instance);
  external int memoryPages(int instance);
  external int memoryGrow(int instance, int delta);
  external JSUint8Array memoryBytes(int instance);
  external int memoryWrite(
      int instance, int address, JSUint8Array data);
  external JSUint8Array? memoryRead(
      int instance, int address, int length);
  external JSUint8Array exportMount(int instance, String root);
  external int importMount(
      int instance, String root, JSUint8Array data);
  external int setMountQuota(int instance, String root, int bytes);

  external JSUint8Array? globalInfo(int instance, String name);
  external JSUint32Array globalGet(int instance, String name);
  external int globalSet(int instance, String name, int lo, int hi);
}

class WebZwasmBackend implements ZwasmBackend {
  bool _ready = false;

  @override
  Future<void> initialize() async {
    if (_ready) return;
    final data = await rootBundle.load('packages/zwasm/web/zwasm_plugin.wasm');
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    try {
      if (_bridge.apiVersion != 1) {
        throw StateError(
            'zwasm web bridge API version ${_bridge.apiVersion}, expected 1');
      }
      await _bridge.init(bytes.toJS).toDart;
    } catch (e) {
      throw StateError(
          'zwasm web backend is not loaded. Add '
          '<script src="assets/packages/zwasm/web/zwasm_bridge.js"></script> '
          'to web/index.html before flutter_bootstrap.js. ($e)');
    }
    _ready = true;
  }

  @override
  String get version => _bridge.version();

  @override
  String get lastError => _bridge.lastErrorMessage();

  @override
  int get lastErrorCode => _bridge.lastErrorCode();

  @override
  int engineNew() => _bridge.engineNew();

  @override
  void engineDelete(int handle) => _bridge.engineDelete(handle);

  @override
  int moduleNew(int engine, Uint8List bytes) =>
      _bridge.moduleNew(engine, bytes.toJS);

  @override
  void moduleDelete(int module) => _bridge.moduleDelete(module);

  @override
  int moduleExportCount(int module) => _bridge.moduleExportCount(module);

  @override
  int moduleExportKind(int module, int index) =>
      _bridge.moduleExportKind(module, index);

  @override
  String moduleExportName(int module, int index) =>
      _bridge.moduleExportName(module, index) ?? '';

  @override
  int moduleImportCount(int module) => _bridge.moduleImportCount(module);

  @override
  int moduleImportKind(int module, int index) =>
      _bridge.moduleImportKind(module, index);

  @override
  String moduleImportModule(int module, int index) =>
      _bridge.moduleImportModule(module, index) ?? '';

  @override
  String moduleImportName(int module, int index) =>
      _bridge.moduleImportName(module, index) ?? '';

  @override
  int wasiConfigNew() => _bridge.wasiConfigNew();

  @override
  void wasiConfigDelete(int config) => _bridge.wasiConfigDelete(config);

  @override
  void wasiAddArg(int config, String arg) =>
      _bridge.wasiConfigAddArg(config, arg);

  @override
  void wasiAddEnv(int config, String key, String value) =>
      _bridge.wasiConfigAddEnv(config, key, value);

  @override
  void wasiInheritStdio(int config) => _bridge.wasiConfigInheritStdio(config);

  @override
  void wasiPreopenDir(int config, String hostPath, String guestPath) {
    _bridge.wasiConfigPreopenDir(config, hostPath, guestPath);
  }

  @override
  void wasiAddFile(
      int config, String guestPath, Uint8List data, bool writable) {
    final rc = _bridge.wasiConfigAddFile(
        config, guestPath, data.toJS, writable ? 1 : 0);
    if (rc != 0) _fail();
  }

  @override
  void wasiAddDir(int config, String guestPath, bool writable) {
    final rc =
        _bridge.wasiConfigAddDir(config, guestPath, writable ? 1 : 0);
    if (rc != 0) _fail();
  }

  @override
  int instanceNew(int module, ZwasmEngineKind engine, int? fuel,
      int? maxMemoryPages, int? wasiConfig, List<ZwasmHostImport> imports) {
    if (imports.isEmpty) {
      return _bridge.instanceNew(module, engine.index, fuel ?? -1,
          maxMemoryPages ?? -1, wasiConfig ?? 0);
    }
    final modules = [for (final i in imports) i.module.toJS].toJS;
    final names = [for (final i in imports) i.name.toJS].toJS;
    final params = [
      for (final i in imports)
        Uint8List.fromList([for (final k in i.params) k.index]).toJS
    ].toJS;
    final results = [
      for (final i in imports)
        Uint8List.fromList([for (final k in i.results) k.index]).toJS
    ].toJS;

    JSAny? dispatch(JSAny? indexAny, JSAny? argsAny) {
      final index = (indexAny as JSNumber).toDartInt;
      final args = (argsAny as JSUint32Array).toDart;
      final imp = imports[index];
      final values = <ZwasmValue>[
        for (var i = 0; i < imp.params.length; i++)
          ZwasmValue.fromHalves(
              imp.params[i], args[i * 2], args[i * 2 + 1])
      ];
      try {
        final res = imp.function(values);
        final out = <int>[
          for (var i = 0; i < imp.results.length; i++) ...[
            res[i].lo & 0xFFFFFFFF,
            res[i].hi & 0xFFFFFFFF,
          ]
        ];
        return [for (final v in out) v.toJS].toJS;
      } catch (_) {
        return null;
      }
    }

    return _bridge.instanceNewWithImports(module, engine.index, fuel ?? -1,
        maxMemoryPages ?? -1, wasiConfig ?? 0, modules, names, params,
        results, dispatch.toJS);
  }

  @override
  void instanceDelete(int instance) => _bridge.instanceDelete(instance);

  @override
  ZwasmSignature funcSig(int instance, String name) {
    final raw = _bridge.funcSig(instance, name);
    if (raw == null) _fail();
    final a = raw.toDart;
    if (a.length < 2) _fail();
    final params = a[0];
    final results = a[1];
    return ZwasmSignature(
      [for (var i = 0; i < params; i++) ZwasmValueKind.fromCode(a[2 + i])],
      [
        for (var i = 0; i < results; i++)
          ZwasmValueKind.fromCode(a[2 + params + i])
      ],
    );
  }

  @override
  List<int> invoke(int instance, String name, List<int> argsLo,
      List<int> argsHi) {
    final lo = Uint32List.fromList(argsLo);
    final hi = Uint32List.fromList(argsHi);
    final raw = _bridge.invoke(instance, name, lo.toJS, hi.toJS).toDart;
    final rc = raw[0];
    if (rc != 0) _fail();
    final out = <int>[];
    for (var i = 1; i + 1 < raw.length; i += 2) {
      out.add(raw[i]);
      out.add(raw[i + 1]);
    }
    return out;
  }

  @override
  int wasiExitCode(int instance) => _bridge.wasiExitCode(instance);

  @override
  void setFuel(int instance, int? fuel) => _bridge.setFuel(instance, fuel ?? -1);

  @override
  int fuelRemaining(int instance) => _bridge.fuelRemaining(instance);

  @override
  void setMemoryLimit(int instance, int? pages) =>
      _bridge.setMemoryLimit(instance, pages ?? -1);

  @override
  void interrupt(int instance) => _bridge.interrupt(instance);

  @override
  void clearInterrupt(int instance) => _bridge.clearInterrupt(instance);

  @override
  int memorySize(int instance) => _bridge.memorySize(instance);

  @override
  int memoryPages(int instance) => _bridge.memoryPages(instance);

  @override
  int memoryData(int instance) => 0;

  @override
  int memoryGrow(int instance, int delta) =>
      _bridge.memoryGrow(instance, delta);

  @override
  Uint8List memoryBytes(int instance) => _bridge.memoryBytes(instance).toDart;

  @override
  void memoryWrite(int instance, int address, Uint8List data) {
    final rc = _bridge.memoryWrite(instance, address, data.toJS);
    if (rc != 0) _fail();
  }

  @override
  Uint8List memoryRead(int instance, int address, int length) {
    final raw = _bridge.memoryRead(instance, address, length);
    if (raw == null) _fail();
    return raw.toDart;
  }

  @override
  Uint8List exportMount(int instance, String root) =>
      _bridge.exportMount(instance, root).toDart;

  @override
  void importMount(int instance, String root, Uint8List data) {
    final rc = _bridge.importMount(instance, root, data.toJS);
    if (rc != 0) _fail();
  }

  @override
  void setMountQuota(int instance, String root, int bytes) {
    final rc = _bridge.setMountQuota(instance, root, bytes);
    if (rc != 0) _fail();
  }

  @override
  void setVfsWriteCallback(
      int instance, ZwasmVfsWriteCallback? callback) {
    if (callback == null) {
      _bridge.instanceSetVfsWriteCallback(instance, null);
      return;
    }
    final fn = ((JSAny? path, JSAny? offset, JSAny? data) {
      callback((path as JSString).toDart, (offset as JSNumber).toDartInt,
          (data as JSUint8Array).toDart);
      return 0;
    }).toJS;
    final rc = _bridge.instanceSetVfsWriteCallback(instance, fn);
    if (rc != 0) _fail();
  }

  @override
  void globalInfo(int instance, String name, Uint8List out) {
    final raw = _bridge.globalInfo(instance, name);
    if (raw == null) _fail();
    final bytes = raw.toDart;
    out[0] = bytes[0];
    out[1] = bytes[1];
  }

  @override
  List<int> globalGet(int instance, String name) {
    final a = _bridge.globalGet(instance, name).toDart;
    return [a[0], a[1]];
  }

  @override
  void globalSet(int instance, String name, int lo, int hi) {
    final rc = _bridge.globalSet(instance, name, lo & 0xFFFFFFFF,
        hi & 0xFFFFFFFF);
    if (rc != 0) _fail();
  }

  Never _fail() => throw ZwasmException(_bridge.lastErrorCode(),
      _bridge.lastErrorMessage());
}

ZwasmBackend createBackend() => WebZwasmBackend();
