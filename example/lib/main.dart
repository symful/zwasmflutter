import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zwasm/zwasm.dart';

/// (module
///   (func (export "add") (param i32 i32) (result i32)
///     local.get 0 local.get 1 i32.add))
final Uint8List addWasm = Uint8List.fromList(const [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, //
  0x01, 0x07, 0x01, 0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f,
  0x03, 0x02, 0x01, 0x00,
  0x07, 0x07, 0x01, 0x03, 0x61, 0x64, 0x64, 0x00, 0x00,
  0x0a, 0x09, 0x01, 0x07, 0x00, 0x20, 0x00, 0x20, 0x01, 0x6a, 0x0b,
]);

/// (module (memory (export "mem") 1)
///   (global (export "g") (mut i32) (i32.const 41)))
final Uint8List stateWasm = Uint8List.fromList(const [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, //
  0x05, 0x03, 0x01, 0x00, 0x01,
  0x06, 0x06, 0x01, 0x7f, 0x01, 0x41, 0x29, 0x0b,
  0x07, 0x0b, 0x02, 0x03, 0x6d, 0x65, 0x6d, 0x02, 0x00, 0x01, 0x67,
  0x03, 0x00,
]);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: DemoPage());
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  String _log = 'Press Run.';

  Future<void> _run() async {
    final lines = <String>[];
    try {
      await Zwasm.initialize();
      lines.add('zwasm ${Zwasm.version}');

      final engine = Zwasm.createEngine();
      try {
        final module = engine.compile(addWasm);
        lines.add(
            'exports: ${module.exports.map((e) => '${e.name}:${e.kind.name}').join(', ')}');
        final instance =
            module.instantiate(engine: ZwasmEngineChoice.interp);
        try {
          final add = instance.findFunction('add')!;
          final r = add.call([ZwasmValue.i32(20), ZwasmValue.i32(22)]);
          lines.add('add(20, 22) = ${r.single.asInt}');
        } finally {
          instance.dispose();
        }
        module.dispose();
      } finally {
        engine.dispose();
      }

      final engine2 = Zwasm.createEngine();
      try {
        final module = engine2.compile(stateWasm);
        final instance =
            module.instantiate(engine: ZwasmEngineChoice.interp);
        try {
          final memory = instance.memory!;
          lines.add(
              'memory: ${memory.pages} page(s), ${memory.sizeInBytes} bytes');
          final global = instance.findGlobal('g')!;
          lines.add(
              'global g = ${global.value.asInt} (mutable: ${global.mutable})');
          global.value = ZwasmValue.i32(99);
          lines.add('global g after set = ${global.value.asInt}');
          memory.asUint8List()[0] = 7;
          lines.add('memory[0] = ${memory.asUint8List()[0]}');
        } finally {
          instance.dispose();
        }
        module.dispose();
      } finally {
        engine2.dispose();
      }
    } on ZwasmException catch (e) {
      lines.add('ERROR ${e.code}: ${e.message}');
    } catch (e) {
      lines.add('ERROR: $e');
    }
    setState(() => _log = lines.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('zwasm Flutter demo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(onPressed: _run, child: const Text('Run')),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  _log,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
