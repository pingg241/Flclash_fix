import 'dart:io';

import 'package:fl_clash/common/file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty native file result is accepted', () {
    expect(
      () => throwIfFileSystemOperationFailed('', '/tmp/profile'),
      returnsNormally,
    );
  });

  test('native file error is converted to FileSystemException', () {
    expect(
      () => throwIfFileSystemOperationFailed('permission denied', '/tmp/a'),
      throwsA(
        isA<FileSystemException>()
            .having((error) => error.message, 'message', 'permission denied')
            .having((error) => error.path, 'path', '/tmp/a'),
      ),
    );
  });

  test('safeDelete accepts a file removed before cleanup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flclash-safe-delete-',
    );
    addTearDown(() => directory.safeDelete(recursive: true));
    final file = await File('${directory.path}/profile.yaml').create();
    await file.delete();

    await expectLater(file.safeDelete(), completes);
  });

  test('safeDelete is idempotent across concurrent cleanup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flclash-safe-delete-',
    );
    addTearDown(() => directory.safeDelete(recursive: true));
    final file = await File('${directory.path}/profile.yaml').create();

    await Future.wait(List.generate(8, (_) => file.safeDelete()));

    expect(await file.exists(), isFalse);
  });

  test('safeDelete still propagates real file-system failures', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flclash-safe-delete-',
    );
    addTearDown(() => directory.safeDelete(recursive: true));
    await File('${directory.path}/profile.yaml').create();

    await expectLater(
      directory.safeDelete(),
      throwsA(isA<FileSystemException>()),
    );
  });
}
