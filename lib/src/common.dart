import 'dart:typed_data';

/// WebAssembly value kinds as exposed at the host boundary.
enum ZwasmValueKind {
  i32,
  i64,
  f32,
  f64,
  v128,
  funcref,
  externref;

  static ZwasmValueKind fromCode(int code) => switch (code) {
        0 => ZwasmValueKind.i32,
        1 => ZwasmValueKind.i64,
        2 => ZwasmValueKind.f32,
        3 => ZwasmValueKind.f64,
        4 => ZwasmValueKind.v128,
        5 => ZwasmValueKind.funcref,
        _ => ZwasmValueKind.externref,
      };
}

enum ZwasmEngineKind { auto, jit, interp }

/// Kinds of module export.
enum ZwasmExternKind { function, table, memory, global, tag }

/// One Wasm value.
///
/// The ABI slot is 64 bits. Because Dart code on the web is limited to 53-bit
/// integers, the value is stored as two 32-bit halves; this keeps f64 and i64
/// exact on every platform. [asInt] for i64 values beyond 2^53 is necessarily
/// lossy on the web (the same limitation as a JS number).
class ZwasmValue {
  final ZwasmValueKind kind;
  final int lo;
  final int hi;

  const ZwasmValue._(this.kind, this.lo, this.hi);

  factory ZwasmValue.i32(int value) =>
      ZwasmValue._(ZwasmValueKind.i32, value & 0xFFFFFFFF, 0);
  factory ZwasmValue.i64(int value) => ZwasmValue._(
      ZwasmValueKind.i64, value & 0xFFFFFFFF, (value >> 32) & 0xFFFFFFFF);
  factory ZwasmValue.f32(double value) => ZwasmValue._(
      ZwasmValueKind.f32,
      (ByteData(4)..setFloat32(0, value)).getUint32(0, Endian.little),
      0);
  factory ZwasmValue.f64(double value) {
    final bd = ByteData(8)..setFloat64(0, value);
    return ZwasmValue._(ZwasmValueKind.f64,
        bd.getUint32(0, Endian.little), bd.getUint32(4, Endian.little));
  }

  factory ZwasmValue.funcref(int? ref) => ZwasmValue._(
      ZwasmValueKind.funcref, (ref ?? 0) & 0xFFFFFFFF, ((ref ?? 0) >> 32) & 0xFFFFFFFF);
  factory ZwasmValue.externref(int? ref) => ZwasmValue._(ZwasmValueKind.externref,
      (ref ?? 0) & 0xFFFFFFFF, ((ref ?? 0) >> 32) & 0xFFFFFFFF);

  /// Construct from the two ABI halves.
  factory ZwasmValue.fromHalves(ZwasmValueKind kind, int lo, int hi) =>
      ZwasmValue._(kind, lo & 0xFFFFFFFF, hi & 0xFFFFFFFF);

  /// Combined 64-bit slot. Exact only on the VM (web ints are 53-bit).
  int get bits => ((hi & 0xFFFFFFFF) << 32) | (lo & 0xFFFFFFFF);

  int get asInt => switch (kind) {
        ZwasmValueKind.i32 => (lo & 0xFFFFFFFF).toSigned(32),
        ZwasmValueKind.i64 => bits,
        _ => bits,
      };

  double get asDouble => switch (kind) {
        ZwasmValueKind.f32 =>
          (ByteData(4)..setUint32(0, lo & 0xFFFFFFFF, Endian.little))
              .getFloat32(0, Endian.little),
        ZwasmValueKind.f64 =>
          (ByteData(8)
                ..setUint32(0, lo & 0xFFFFFFFF, Endian.little)
                ..setUint32(4, hi & 0xFFFFFFFF, Endian.little))
              .getFloat64(0, Endian.little),
        _ => asInt.toDouble(),
      };

  @override
  String toString() => switch (kind) {
        ZwasmValueKind.i32 || ZwasmValueKind.i64 => '$asInt',
        ZwasmValueKind.f32 || ZwasmValueKind.f64 => '$asDouble',
        _ => '$kind($bits)',
      };
}

/// Error raised by zwasm. [code] mirrors the shim's `ZW_ERR_*` values.
class ZwasmException implements Exception {
  final int code;
  final String message;

  const ZwasmException(this.code, this.message);

  /// A guest `proc_exit`. Read [ZwasmInstance.wasiExitCode] for the status.
  bool get isWasiExit => code == 10;

  @override
  String toString() => 'ZwasmException($code): $message';
}

/// Function signature returned by [ZwasmBackend.funcSig].
class ZwasmSignature {
  final List<ZwasmValueKind> params;
  final List<ZwasmValueKind> results;

  const ZwasmSignature(this.params, this.results);
}

/// A module export.
class ZwasmExport {
  final String name;
  final ZwasmExternKind kind;

  const ZwasmExport(this.name, this.kind);
}

/// A module import descriptor.
class ZwasmImportInfo {
  final String module;
  final String name;
  final ZwasmExternKind kind;

  const ZwasmImportInfo(this.module, this.name, this.kind);

  @override
  String toString() => '$module.$name ($kind)';
}

/// Dart implementation of one host import.
typedef ZwasmHostFunction = List<ZwasmValue> Function(List<ZwasmValue> args);

/// Receives a write-through VFS file write.
typedef ZwasmVfsWriteCallback = void Function(
    String path, int offset, Uint8List data);

/// Registers a Dart function as a host import. The signature must match the
/// importing module's declared type exactly; [function] receives one value per
/// parameter and must return one value per result.
class ZwasmHostImport {
  final String module;
  final String name;
  final List<ZwasmValueKind> params;
  final List<ZwasmValueKind> results;
  final ZwasmHostFunction function;

  const ZwasmHostImport({
    required this.module,
    required this.name,
    required this.params,
    required this.results,
    required this.function,
  });
}

/// Backend contract implemented by the FFI (native) and JS-interop (web)
/// layers. Handles are opaque integers allocated by the runtime.
abstract class ZwasmBackend {
  String get version;
  Future<void> initialize();

  String get lastError;
  int get lastErrorCode;

  int engineNew();
  void engineDelete(int handle);

  int moduleNew(int engine, Uint8List bytes);
  void moduleDelete(int module);
  int moduleExportCount(int module);
  String moduleExportName(int module, int index);
  int moduleExportKind(int module, int index);

  int moduleImportCount(int module);
  String moduleImportModule(int module, int index);
  String moduleImportName(int module, int index);
  int moduleImportKind(int module, int index);

  int wasiConfigNew();
  void wasiConfigDelete(int config);
  void wasiAddArg(int config, String arg);
  void wasiAddEnv(int config, String key, String value);
  void wasiInheritStdio(int config);
  void wasiPreopenDir(int config, String hostPath, String guestPath);
  void wasiAddFile(
      int config, String guestPath, Uint8List data, bool writable);
  void wasiAddDir(int config, String guestPath, bool writable);

  int instanceNew(int module, ZwasmEngineKind engine, int? fuel,
      int? maxMemoryPages, int? wasiConfig, List<ZwasmHostImport> imports);
  void instanceDelete(int instance);

  ZwasmSignature funcSig(int instance, String name);

  /// Returns interleaved result halves: `[lo0, hi0, lo1, hi1, ...]`.
  List<int> invoke(
      int instance, String name, List<int> argsLo, List<int> argsHi);
  int wasiExitCode(int instance);

  void setFuel(int instance, int? fuel);
  int fuelRemaining(int instance);
  void setMemoryLimit(int instance, int? pages);
  void interrupt(int instance);
  void clearInterrupt(int instance);

  int memorySize(int instance);
  int memoryPages(int instance);
  int memoryData(int instance);
  int memoryGrow(int instance, int delta);
  Uint8List memoryBytes(int instance);
  void memoryWrite(int instance, int address, Uint8List data);
  Uint8List memoryRead(int instance, int address, int length);
  Uint8List exportMount(int instance, String root);
  void importMount(int instance, String root, Uint8List data);
  void setVfsWriteCallback(
      int instance, ZwasmVfsWriteCallback? callback);

  void globalInfo(int instance, String name, Uint8List out);

  /// Returns `[lo, hi]`.
  List<int> globalGet(int instance, String name);
  void globalSet(int instance, String name, int lo, int hi);
}
