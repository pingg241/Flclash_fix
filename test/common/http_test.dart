import 'package:fl_clash/common/http.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('local proxy route', () {
    const remoteUrl = 'https://subscriptions.example/profile';
    final cases =
        <
          ({
            String name,
            CoreStatus coreStatus,
            bool isStart,
            bool isStarting,
            bool suspend,
            String url,
            bool expected,
          })
        >[
          (
            name: 'fully connected and started',
            coreStatus: CoreStatus.connected,
            isStart: true,
            isStarting: false,
            suspend: false,
            url: remoteUrl,
            expected: true,
          ),
          (
            name: 'core connecting',
            coreStatus: CoreStatus.connecting,
            isStart: true,
            isStarting: false,
            suspend: false,
            url: remoteUrl,
            expected: false,
          ),
          (
            name: 'core disconnected',
            coreStatus: CoreStatus.disconnected,
            isStart: true,
            isStarting: false,
            suspend: false,
            url: remoteUrl,
            expected: false,
          ),
          (
            name: 'runtime stopped',
            coreStatus: CoreStatus.connected,
            isStart: false,
            isStarting: false,
            suspend: false,
            url: remoteUrl,
            expected: false,
          ),
          (
            name: 'runtime starting',
            coreStatus: CoreStatus.connected,
            isStart: true,
            isStarting: true,
            suspend: false,
            url: remoteUrl,
            expected: false,
          ),
          (
            name: 'runtime suspended',
            coreStatus: CoreStatus.connected,
            isStart: true,
            isStarting: false,
            suspend: true,
            url: remoteUrl,
            expected: false,
          ),
          (
            name: 'loopback target',
            coreStatus: CoreStatus.connected,
            isStart: true,
            isStarting: false,
            suspend: false,
            url: 'http://127.0.0.1:9090/configs',
            expected: false,
          ),
        ];

    for (final testCase in cases) {
      test(testCase.name, () {
        expect(
          FlClashHttpOverrides.shouldUseLocalProxy(
            url: Uri.parse(testCase.url),
            coreStatus: testCase.coreStatus,
            isStart: testCase.isStart,
            isStarting: testCase.isStarting,
            suspend: testCase.suspend,
          ),
          testCase.expected,
        );
      });
    }
  });

  test('safe endpoint excludes credentials and resource details', () {
    const secret = 'query-secret';
    final endpoint = safeHttpEndpoint(
      Uri.parse(
        'https://user:password@subscriptions.example:8443/private/profile'
        '?token=$secret#fragment',
      ),
    );

    expect(endpoint, 'https://subscriptions.example:8443');
    expect(endpoint, isNot(contains('user')));
    expect(endpoint, isNot(contains('password')));
    expect(endpoint, isNot(contains('private')));
    expect(endpoint, isNot(contains(secret)));
    expect(endpoint, isNot(contains('fragment')));
  });
}
