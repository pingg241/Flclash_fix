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

  test('safeCopy fails without creating a missing source or target', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flclash-safe-copy-',
    );
    addTearDown(() => directory.safeDelete(recursive: true));
    final source = File('${directory.path}/missing/source.yaml');
    final target = File('${directory.path}/target/profile.yaml');

    await expectLater(
      source.safeCopy(target.path),
      throwsA(isA<FileSystemException>()),
    );

    expect(await source.exists(), isFalse);
    expect(await target.exists(), isFalse);
  });

  test('safeCopy creates the target parent and copies the source', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flclash-safe-copy-',
    );
    addTearDown(() => directory.safeDelete(recursive: true));
    final source = File('${directory.path}/source.yaml');
    final target = File('${directory.path}/nested/profile.yaml');
    await source.writeAsString('proxies: []');

    await source.safeCopy(target.path);

    expect(await target.readAsString(), 'proxies: []');
  });

  test(
    'atomic source replacement preserves target when staging fails',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'flclash-atomic-copy-',
      );
      addTearDown(() => directory.safeDelete(recursive: true));
      final source = File('${directory.path}/source.zip');
      final target = File('${directory.path}/backup.zip');
      await source.writeAsString('new archive');
      await target.writeAsString('old archive');

      await expectLater(
        replaceFileFromSourceAtomically(
          source,
          target,
          copyToStage: (_, staged) async {
            await staged.writeAsString('partial');
            throw const FileSystemException('copy interrupted');
          },
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await target.readAsString(), 'old archive');
      expect(
        await directory
            .list()
            .where((entity) => entity.path.contains('.staged-'))
            .isEmpty,
        isTrue,
      );
    },
  );

  test('atomic source replacement installs a fully staged file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flclash-atomic-copy-',
    );
    addTearDown(() => directory.safeDelete(recursive: true));
    final source = File('${directory.path}/source.zip');
    final target = File('${directory.path}/backup.zip');
    await source.writeAsString('new archive');
    await target.writeAsString('old archive');

    await replaceFileFromSourceAtomically(source, target);

    expect(await target.readAsString(), 'new archive');
  });
}
