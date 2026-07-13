import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('$packageName/app');
  final app = App();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    app.clearPackageIconCache();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'package icon requests are single-flight and reuse the same result',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getPackageIcon') {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return 'C:\\icons\\test.png';
        }
        return null;
      });

      final first = app.getPackageIcon('test.package');
      final second = app.getPackageIcon('test.package');

      expect(identical(first, second), isTrue);
      final providers = await Future.wait([first, second]);
      expect(calls, 1);
      expect(identical(providers.first, providers.last), isTrue);
    },
  );

  test('failed package icon requests are not cached', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      if (calls == 1) {
        throw PlatformException(code: 'failed');
      }
      return 'C:\\icons\\test.png';
    });

    expect(await app.getPackageIcon('test.package'), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(await app.getPackageIcon('test.package'), isNotNull);
    expect(calls, 2);
  });

  test('expired package icon entries are refreshed', () async {
    var calls = 0;
    app.packageIconCacheDuration = Duration.zero;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return 'C:\\icons\\test-$calls.png';
    });

    await app.getPackageIcon('test.package');
    await app.getPackageIcon('test.package');

    expect(calls, 2);
  });

  test('timed out package icon requests release the in-flight entry', () async {
    var shouldHang = true;
    var calls = 0;
    app.packageIconLoadTimeout = const Duration(milliseconds: 10);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      if (shouldHang) {
        return Completer<String>().future;
      }
      return 'C:\\icons\\test.png';
    });

    expect(await app.getPackageIcon('test.package'), isNull);
    await Future<void>.delayed(Duration.zero);
    shouldHang = false;
    expect(await app.getPackageIcon('test.package'), isNotNull);
    expect(calls, 2);
  });

  test(
    'package icon cache is bounded and uses least-recently-used eviction',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        final packageName = (call.arguments as Map)['packageName'];
        return 'C:\\icons\\$packageName.png';
      });

      for (var index = 0; index < 129; index++) {
        await app.getPackageIcon('package.$index');
      }

      expect(app.packageIconCacheLength, 128);
      await app.getPackageIcon('package.0');
      expect(calls, 130);
    },
  );

  test('package updates and memory pressure invalidate cached icons', () async {
    var iconCalls = 0;
    var packageVersion = 1;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getPackageIcon':
          iconCalls++;
          return 'C:\\icons\\test-$iconCalls.png';
        case 'getPackages':
          return jsonEncode([
            {
              'packageName': 'test.package',
              'label': 'Test',
              'system': false,
              'internet': true,
              'lastUpdateTime': packageVersion,
            },
          ]);
      }
      return null;
    });

    await app.getPackageIcon('test.package');
    await app.getPackages();
    await app.getPackageIcon('test.package');
    await app.getPackages();
    await app.getPackageIcon('test.package');
    expect(iconCalls, 2);

    packageVersion = 2;
    await app.getPackages();
    await app.getPackageIcon('test.package');
    expect(iconCalls, 3);

    app.didHaveMemoryPressure();
    await app.getPackageIcon('test.package');
    expect(iconCalls, 4);
  });
}
