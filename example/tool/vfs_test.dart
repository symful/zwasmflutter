// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:zwasm/zwasm.dart';

Future<void> main() async {
  await Zwasm.initialize();
  final bytes = File('tool/vfs_test.wasm').readAsBytesSync();
  final engine = Zwasm.createEngine();
  final module = engine.compile(bytes);
  print('imports: ${module.imports.length}');
  print('exports: ${module.exports.map((e) => e.name).toList()}');
  print('imports: ${module.imports.map((e) => '${e.module}.${e.name}').toList()}');

  final wasi = ZwasmWasiConfig()
    ..addFile('/app/hello.txt', Uint8List.fromList(utf8.encode('hello')));
  final instance =
      module.instantiate(engine: ZwasmEngineChoice.interp, wasi: wasi);
  final writes = <String>[];
  instance.setVfsWriteCallback((path, offset, data) {
    writes.add('$path:$offset:${utf8.decode(data)}');
  });
  var code = 0;
  try {
    instance.findFunction('_start')!.call([]);
  } on ZwasmException catch (e) {
    if (e.isWasiExit) {
      code = instance.wasiExitCode ?? -1;
    } else {
      print('trap: $e');
      code = -2;
    }
  }
  print('vfs cart exit=$code wasiExit=${instance.wasiExitCode}');
  print('write-through: $writes');
  if (!writes.contains('/data/out.txt:0:hello')) {
    throw StateError('write-through callback did not fire');
  }
  final mount = instance.exportMount('/data');
  final bd = ByteData.sublistView(mount);
  var off = 0;
  final count = bd.getUint32(off, Endian.little);
  off += 4;
  String? outText;
  for (var i = 0; i < count; i++) {
    final plen = bd.getUint32(off, Endian.little);
    off += 4;
    final path = utf8.decode(mount.sublist(off, off + plen));
    off += plen;
    final size = bd.getUint64(off, Endian.little);
    off += 8;
    final bytes = mount.sublist(off, off + size);
    off += size;
    print('  /data file: $path (${bytes.length})');
    if (path == '/data/out.txt') outText = utf8.decode(bytes);
  }
  final wasi2 = ZwasmWasiConfig()..addDir('/data', writable: true);
  final instance2 =
      module.instantiate(engine: ZwasmEngineChoice.interp, wasi: wasi2);
  instance2.importMount('/data', mount);
  final roundTrip = instance2.exportMount('/data');
  instance2.dispose();
  wasi2.dispose();
  if (roundTrip.length != mount.length) {
    throw StateError('import/export length mismatch');
  }
  for (var i = 0; i < mount.length; i++) {
    if (roundTrip[i] != mount[i]) {
      throw StateError('import/export byte mismatch at $i');
    }
  }
  print('import/export round-trip OK');

  instance.dispose();
  wasi.dispose();
  module.dispose();
  engine.dispose();
  if (code != 0) throw StateError('VFS test failed');
  if (outText != 'hello') {
    throw StateError('VFS write failed: $outText');
  }
  print('OK');
}
