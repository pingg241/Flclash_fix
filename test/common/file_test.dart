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
}
