import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'directory lookup failures propagate instead of staying pending',
    () async {
      final directory = Directory.systemTemp;
      final path = AppPath.test(
        dataDirectory: Future<Directory>.error(StateError('path failed')),
        downloadsDirectory: Future.value(directory),
        temporaryDirectory: Future.value(directory),
        applicationCacheDirectory: Future.value(directory),
      );

      await expectLater(
        path.homeDirPath.timeout(const Duration(milliseconds: 100)),
        throwsStateError,
      );
    },
  );

  test(
    'directory lookup remains single-flight for concurrent readers',
    () async {
      final directory = Directory.systemTemp;
      final dataDirectory = Completer<Directory>();
      final path = AppPath.test(
        dataDirectory: dataDirectory.future,
        downloadsDirectory: Future.value(directory),
        temporaryDirectory: Future.value(directory),
        applicationCacheDirectory: Future.value(directory),
      );

      final first = path.homeDirPath;
      final second = path.profilesPath;
      dataDirectory.complete(directory);

      expect(await first, directory.path);
      expect(await second, startsWith(directory.path));
    },
  );
}
