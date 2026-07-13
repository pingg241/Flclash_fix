import 'dart:async';

import 'package:fl_clash/core/lib.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockService extends Mock implements Service {}

class FakeAction extends Fake implements Action {}

void main() {
  late MockService service;

  setUpAll(() {
    registerFallbackValue(FakeAction());
  });

  setUp(() {
    service = MockService();
  });

  test('startListener compensates core when Android service fails', () async {
    when(() => service.invokeAction(any())).thenAnswer((invocation) async {
      final action = invocation.positionalArguments.first as Action;
      return ActionResult(method: action.method, data: true);
    });
    when(service.start).thenAnswer((_) async => false);
    final core = CoreLib.test(service, connected: true);

    expect(await core.startListener(), isFalse);
    final actions = verify(
      () => service.invokeAction(captureAny()),
    ).captured.cast<Action>();
    expect(actions.map((action) => action.method), [
      ActionMethod.startListener,
      ActionMethod.stopListener,
    ]);
  });

  test(
    'startListener compensates core before propagating service errors',
    () async {
      when(() => service.invokeAction(any())).thenAnswer((invocation) async {
        final action = invocation.positionalArguments.first as Action;
        return ActionResult(method: action.method, data: true);
      });
      when(service.start).thenThrow(StateError('service failed'));
      final core = CoreLib.test(service, connected: true);

      await expectLater(core.startListener(), throwsStateError);
      final actions = verify(
        () => service.invokeAction(captureAny()),
      ).captured.cast<Action>();
      expect(actions.map((action) => action.method), [
        ActionMethod.startListener,
        ActionMethod.stopListener,
      ]);
    },
  );

  test('stopListener returns false when the core rejects stop', () async {
    when(() => service.invokeAction(any())).thenAnswer(
      (_) async =>
          const ActionResult(method: ActionMethod.stopListener, data: false),
    );
    final core = CoreLib.test(service, connected: true);

    expect(await core.stopListener(), isFalse);
    verifyNever(service.stop);
  });

  test(
    'stopListener keeps the stopped core state on service failure',
    () async {
      when(() => service.invokeAction(any())).thenAnswer(
        (_) async =>
            const ActionResult(method: ActionMethod.stopListener, data: true),
      );
      when(service.stop).thenAnswer((_) async => false);
      final core = CoreLib.test(service, connected: true);

      expect(await core.stopListener(), isFalse);
    },
  );

  test('shutdown cannot succeed without an Android service', () async {
    final core = CoreLib.test(null, connected: true);

    expect(await core.shutdown(true), isFalse);
  });

  test('preload cannot succeed without an Android service', () async {
    final core = CoreLib.test(null);

    expect(await core.preload(), contains('unavailable'));
  });

  test('shutdown returns the native service failure', () async {
    when(service.shutdown).thenAnswer((_) async => false);
    final core = CoreLib.test(service, connected: true);

    expect(await core.shutdown(true), isFalse);
    expect(core.completer.isCompleted, isTrue);
  });

  test('shutdown clears the connection only after native success', () async {
    when(service.shutdown).thenAnswer((_) async => true);
    final core = CoreLib.test(service, connected: true);

    expect(await core.shutdown(true), isTrue);
    expect(core.completer.isCompleted, isFalse);
  });

  test('invoke honors the requested timeout', () async {
    when(
      () => service.invokeAction(any()),
    ).thenAnswer((_) => Completer<ActionResult?>().future);
    final core = CoreLib.test(service, connected: true);

    await expectLater(
      core.invoke<bool>(
        method: ActionMethod.getIsInit,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(
        isA<CoreInvocationException>().having(
          (error) => error.failure,
          'failure',
          CoreInvocationFailure.timeout,
        ),
      ),
    );
  });

  test('invoke rejects a missing Android service', () async {
    final core = CoreLib.test(null, connected: true);

    await expectLater(
      core.validateConfig('/profile.yaml'),
      throwsA(
        isA<CoreInvocationException>().having(
          (error) => error.failure,
          'failure',
          CoreInvocationFailure.unavailable,
        ),
      ),
    );
  });

  test('invoke rejects a null Android handler response', () async {
    when(() => service.invokeAction(any())).thenAnswer((_) async => null);
    final core = CoreLib.test(service, connected: true);

    await expectLater(
      core.getConfig('/profile.yaml'),
      throwsA(
        isA<CoreInvocationException>().having(
          (error) => error.failure,
          'failure',
          CoreInvocationFailure.noResponse,
        ),
      ),
    );
  });
}
