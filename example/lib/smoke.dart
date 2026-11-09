import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zwasm/zwasm.dart';

final addWasm = Uint8List.fromList(const [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
  0x01, 0x07, 0x01, 0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f,
  0x03, 0x02, 0x01, 0x00,
  0x07, 0x07, 0x01, 0x03, 0x61, 0x64, 0x64, 0x00, 0x00,
  0x0a, 0x09, 0x01, 0x07, 0x00, 0x20, 0x00, 0x20, 0x01, 0x6a, 0x0b,
]);

void main() {
  runApp(const MaterialApp(home: SmokePage()));
}

class SmokePage extends StatefulWidget {
  const SmokePage({super.key});

  @override
  State<SmokePage> createState() => _SmokePageState();
}

class _SmokePageState extends State<SmokePage> {
  String log = 'running';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final out = <String>[];
    try {
      await Zwasm.initialize();
      out.add('SMOKE zwasm ${Zwasm.version}');
      final engine = Zwasm.createEngine();
      final module = engine.compile(addWasm);
      final instance = module.instantiate(engine: ZwasmEngineChoice.interp);
      final add = instance.findFunction('add')!;
      final r = add.call([ZwasmValue.i32(2), ZwasmValue.i32(3)]).single;
      out.add('SMOKE add(2,3)=${r.asInt}');
      instance.dispose();
      module.dispose();
      engine.dispose();
      out.add('SMOKE OK');
    } catch (e) {
      out.add('SMOKE ERROR $e');
    }
    for (final line in out) {
      debugPrint(line);
    }
    if (mounted) setState(() => log = out.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(log, textAlign: TextAlign.center),
      ),
    );
  }
}
