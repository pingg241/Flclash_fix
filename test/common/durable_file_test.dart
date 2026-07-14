import 'dart:io';

import 'package:fl_clash/common/durable_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('atomic write syncs the parent directory after rename', () async {
    final root = await Directory.systemTemp.createTemp('durable-file-');
    addTearDown(() => root.delete(recursive: true));
    final calls = <String>[];
    final target = File('${root.path}/state');

    await writeFileAtomicallyDurable(
      target,
      'value',
      syncDirectory: (directory) async => calls.add(directory.path),
    );

    expect(await target.readAsString(), 'value');
    expect(calls, [root.path]);
  });
}
