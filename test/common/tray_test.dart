import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/tray.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tray.getTryIcon', () {
    final tray = Tray();
    final suffix = tray.trayIconSuffix;

    test('returns idle icon when core is not started', () {
      expect(
        tray.getTryIcon(isStart: false, tunEnable: false),
        'assets/images/icon/status_1.$suffix',
      );
    });

    test('returns normal mode icon when core is started without TUN', () {
      expect(
        tray.getTryIcon(isStart: true, tunEnable: false),
        Platform.isMacOS
            ? 'assets/images/icon/status_1.$suffix'
            : 'assets/images/icon/status_2.$suffix',
      );
    });

    test('returns enhanced mode icon when core is started with TUN', () {
      expect(
        tray.getTryIcon(isStart: true, tunEnable: true),
        Platform.isMacOS
            ? 'assets/images/icon/status_1.$suffix'
            : 'assets/images/icon/status_3.$suffix',
      );
    });
  });

  test('tray update waits for the title update', () async {
    final titleUpdate = Completer<void>();
    var completed = false;

    final update = awaitTrayTitleUpdate(() => titleUpdate.future).then((_) {
      completed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    titleUpdate.complete();
    await update;
    expect(completed, isTrue);
  });

  test('tray menu failures are reported without escaping', () async {
    final reported = Completer<Object>();

    runTrayMenuOperation(
      operation: () => throw StateError('menu failed'),
      onError: (error, _) => reported.complete(error),
    );

    expect(await reported.future, isA<StateError>());
  });
}
