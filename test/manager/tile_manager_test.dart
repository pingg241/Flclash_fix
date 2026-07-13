import 'package:fl_clash/manager/tile_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('start failure is returned without showing a success tip', () async {
    var tipCalls = 0;

    await expectLater(
      performTileTransition(
        target: true,
        update: () async => false,
        readCurrent: () => false,
        showTip: () async => tipCalls++,
      ),
      throwsStateError,
    );

    expect(tipCalls, 0);
  });

  test('stop false is returned without showing a success tip', () async {
    var tipCalls = 0;

    await expectLater(
      performTileTransition(
        target: false,
        update: () async => false,
        readCurrent: () => true,
        showTip: () async => tipCalls++,
      ),
      throwsStateError,
    );

    expect(tipCalls, 0);
  });

  test('tip is shown only after the target state is confirmed', () async {
    var current = false;
    var tipCalls = 0;

    await performTileTransition(
      target: true,
      update: () async {
        current = true;
        return true;
      },
      readCurrent: () => current,
      showTip: () async => tipCalls++,
    );

    expect(tipCalls, 1);
  });
}
