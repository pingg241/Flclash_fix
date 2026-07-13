import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingScripts extends Scripts {
  @override
  Stream<List<Script>> build() {
    return Stream.error(StateError('DAO read failed'));
  }
}

void main() {
  group('withRollback', () {
    test('rolls back with snapshot and rethrows async errors', () async {
      final error = StateError('write failed');
      final previous = [1, 2, 3];
      List<int>? rolledBack;

      await expectLater(
        withRollback(
          snapshot: previous,
          optimistic: previous,
          current: () => previous,
          action: () async {
            throw error;
          },
          rollback: (value) => rolledBack = value,
        ),
        throwsA(same(error)),
      );

      expect(rolledBack, previous);
    });

    test('does not roll back when action succeeds', () async {
      var rollbackCalled = false;

      await withRollback(
        snapshot: [1, 2, 3],
        optimistic: const [4, 5, 6],
        current: () => const [4, 5, 6],
        action: () async {},
        rollback: (_) => rollbackCalled = true,
      );

      expect(rollbackCalled, false);
    });

    test(
      'does not let a stale failure replace newer optimistic state',
      () async {
        final previous = [1];
        final optimistic = [1, 2];
        final newer = [1, 2, 3];
        var current = newer;

        await expectLater(
          withRollback(
            snapshot: previous,
            optimistic: optimistic,
            current: () => current,
            action: () => Future<void>.error(StateError('write failed')),
            rollback: (value) => current = value,
          ),
          throwsStateError,
        );

        expect(identical(current, newer), true);
      },
    );
  });

  test('first DAO error notifies listeners after initial loading', () async {
    final container = ProviderContainer(
      overrides: [scriptsProvider.overrideWith(_FailingScripts.new)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    final states = <AsyncValue<List<Script>>>[];
    final subscription = container.listen(
      scriptsProvider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await expectLater(container.read(scriptsProvider.future), throwsStateError);

    expect(states, hasLength(2));
    expect(states.first.isLoading, isTrue);
    expect(states.last.hasError, isTrue);
    expect(states.last.error, isA<StateError>());
  });
}
