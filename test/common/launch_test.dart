import 'package:fl_clash/common/launch.dart';
import 'package:test/test.dart';

class _FakeAutoLaunchPlatform implements AutoLaunchPlatform {
  bool enabled;
  bool updateResult;
  bool applyUpdate;
  int enableCalls = 0;
  int disableCalls = 0;

  _FakeAutoLaunchPlatform({
    required this.enabled,
    this.updateResult = true,
    this.applyUpdate = true,
  });

  @override
  Future<bool> disable() async {
    disableCalls++;
    if (updateResult && applyUpdate) {
      enabled = false;
    }
    return updateResult;
  }

  @override
  Future<bool> enable() async {
    enableCalls++;
    if (updateResult && applyUpdate) {
      enabled = true;
    }
    return updateResult;
  }

  @override
  Future<bool> isEnabled() async => enabled;
}

void main() {
  test('does not update when status already matches', () async {
    final platform = _FakeAutoLaunchPlatform(enabled: true);
    final autoLaunch = AutoLaunch.test(platform);

    expect(await autoLaunch.updateStatus(true), isTrue);
    expect(platform.enableCalls, 0);
    expect(platform.disableCalls, 0);
  });

  test('returns false when the platform rejects the update', () async {
    final platform = _FakeAutoLaunchPlatform(
      enabled: false,
      updateResult: false,
    );
    final autoLaunch = AutoLaunch.test(platform);

    expect(await autoLaunch.updateStatus(true), isFalse);
    expect(platform.enableCalls, 1);
  });

  test(
    'returns false when verification does not match the requested state',
    () async {
      final platform = _FakeAutoLaunchPlatform(
        enabled: false,
        applyUpdate: false,
      );
      final autoLaunch = AutoLaunch.test(platform);

      expect(await autoLaunch.updateStatus(true), isFalse);
      expect(platform.enableCalls, 1);
    },
  );

  test('awaits and verifies a successful update', () async {
    final platform = _FakeAutoLaunchPlatform(enabled: true);
    final autoLaunch = AutoLaunch.test(platform);

    expect(await autoLaunch.updateStatus(false), isTrue);
    expect(platform.disableCalls, 1);
    expect(platform.enabled, isFalse);
  });
}
