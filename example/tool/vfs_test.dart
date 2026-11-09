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
