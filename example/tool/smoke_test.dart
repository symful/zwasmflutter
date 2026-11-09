// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:zwasm/zwasm.dart';

final addWasm = Uint8List.fromList(const [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, //
  0x01, 0x07, 0x01, 0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f,
  0x03, 0x02, 0x01, 0x00,
  0x07, 0x07, 0x01, 0x03, 0x61, 0x64, 0x64, 0x00, 0x00,
  0x0a, 0x09, 0x01, 0x07, 0x00, 0x20, 0x00, 0x20, 0x01, 0x6a, 0x0b,
]);

final stateWasm = Uint8List.fromList(const [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, //
  0x05, 0x03, 0x01, 0x00, 0x01,
  0x06, 0x06, 0x01, 0x7f, 0x01, 0x41, 0x29, 0x0b,
  0x07, 0x0b, 0x02, 0x03, 0x6d, 0x65, 0x6d, 0x02, 0x00, 0x01, 0x67,
  0x03, 0x00,
]);

Future<void> main() async {
  await Zwasm.initialize();
  print('zwasm ${Zwasm.version}');

  final engine = Zwasm.createEngine();
  final module = engine.compile(addWasm);
  print('exports: ${module.exports.map((e) => '${e.name}:${e.kind.name}')}');
  final instance = module.instantiate(engine: ZwasmEngineChoice.interp);
  final add = instance.findFunction('add')!;
  final result = add.call([ZwasmValue.i32(2), ZwasmValue.i32(3)]).single;
  print('add(2, 3) = ${result.asInt}');
  instance.dispose();
  module.dispose();
  engine.dispose();

  final engine2 = Zwasm.createEngine();
  final module2 = engine2.compile(stateWasm);
  final instance2 = module2.instantiate(engine: ZwasmEngineChoice.interp);
  final memory = instance2.memory!;
  print('memory pages=${memory.pages} bytes=${memory.sizeInBytes}');
  final global = instance2.findGlobal('g')!;
  print('g=${global.value.asInt} mutable=${global.mutable}');
  global.value = ZwasmValue.i32(100);
  memory.asUint8List()[0] = 9;
  print('g after set=${global.value.asInt} mem0=${memory.asUint8List()[0]}');
  instance2.dispose();
  module2.dispose();
  engine2.dispose();

  print('OK');
}
