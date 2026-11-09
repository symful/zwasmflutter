// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:zwasm/zwasm.dart';

/// (module
///   (import "env" "add" (func $add (param i32 i32) (result i32)))
///   (memory (export "memory") 1)
///   (func (export "run") (param i32 i32) (result i32)
///     local.get 0 local.get 1 call $add))
final importWasm = Uint8List.fromList(const [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, //
  0x01, 0x07, 0x01, 0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f,
  0x02, 0x0b, 0x01, 0x03, 0x65, 0x6e, 0x76, 0x03, 0x61, 0x64, 0x64, 0x00,
  0x00,
  0x03, 0x02, 0x01, 0x00,
  0x05, 0x03, 0x01, 0x00, 0x01,
  0x07, 0x10, 0x02, 0x03, 0x72, 0x75, 0x6e, 0x00, 0x00, 0x06, 0x6d, 0x65,
  0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00,
  0x0a, 0x0a, 0x01, 0x08, 0x00, 0x20, 0x00, 0x20, 0x01, 0x10, 0x00, 0x0b,
]);

Future<void> main() async {
  await Zwasm.initialize();
  final engine = Zwasm.createEngine();
  final module = engine.compile(importWasm);
  print('imports: ${module.imports}');
  if (module.imports.length != 1 ||
      module.imports.single.module != 'env' ||
      module.imports.single.name != 'add') {
    throw StateError('import introspection failed: ${module.imports}');
  }

  var calls = 0;
  final instance = module.instantiate(
    engine: ZwasmEngineChoice.interp,
    imports: [
      ZwasmHostImport(
        module: 'env',
        name: 'add',
        params: const [ZwasmValueKind.i32, ZwasmValueKind.i32],
        results: const [ZwasmValueKind.i32],
        function: (args) {
          calls++;
          return [
            ZwasmValue.i32(args[0].asInt + args[1].asInt),
          ];
        },
      ),
    ],
  );

  final run = instance.findFunction('run')!;
  final result = run.call([ZwasmValue.i32(20), ZwasmValue.i32(22)]).single;
  print('host add(20,22) = ${result.asInt} (calls=$calls)');
  if (result.asInt != 42 || calls != 1) {
    throw StateError('host import failed');
  }

  instance.dispose();
  module.dispose();
  engine.dispose();
  print('OK');
}
