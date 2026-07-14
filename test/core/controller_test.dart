import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

class FakeCompleter extends Fake implements Completer<dynamic> {
  @override
  bool get isCompleted => true;
}

void main() {
  late MockCoreHandlerInterface mock;
  late CoreController controller;

  setUpAll(() {
    registerFallbackValue(
      const SetupParams(selectedMap: {}, testUrl: 'http://x.com'),
    );
    registerFallbackValue(const InitParams(homeDir: '.', version: 1));
    registerFallbackValue(
      const UpdateParams(
        tun: Tun(),
        mixedPort: 7890,
        allowLan: true,
        findProcessMode: FindProcessMode.off,
        mode: Mode.rule,
        logLevel: LogLevel.info,
        ipv6: false,
        tcpConcurrent: false,
        externalController: ExternalControllerStatus.close,
        unifiedDelay: false,
      ),
    );
    registerFallbackValue(
      const ChangeProxyParams(groupName: 'G', proxyName: 'P'),
    );
    registerFallbackValue(
      const UpdateGeoDataParams(geoType: 't', geoName: 'n'),
    );
  });

  setUp(() {
    mock = MockCoreHandlerInterface();
    CoreController.resetInstance();
    controller = CoreController.test(mock);
  });

  tearDown(() {
    CoreController.resetInstance();
  });

  group('CoreController singleton', () {
    test('test constructor injects mock interface', () {
      expect(controller, isA<CoreController>());
    });

    test('resetInstance allows fresh construction', () {
      CoreController.resetInstance();
      final instance = CoreController.test(mock);
      expect(instance, isA<CoreController>());
    });
  });

  group('lifecycle methods', () {
    test('preload delegates to interface', () async {
      when(() => mock.preload()).thenAnswer((_) async => 'ready');
      final result = await controller.preload();
      expect(result, 'ready');
      verify(() => mock.preload()).called(1);
    });

    test('shutdown returns interface success', () async {
      when(() => mock.shutdown(true)).thenAnswer((_) async => true);
      expect(await controller.shutdown(true), isTrue);
      verify(() => mock.shutdown(true)).called(1);
    });

    test('shutdown returns interface failure', () async {
      when(() => mock.shutdown(false)).thenAnswer((_) async => false);

      expect(await controller.shutdown(false), isFalse);
    });

    test('destroy rejects an unconfirmed core shutdown', () async {
      when(() => mock.destroy()).thenAnswer((_) async => false);

      await expectLater(controller.destroy(), throwsStateError);

      verify(() => mock.destroy()).called(1);
    });

    test('shutdown propagates interface errors', () async {
      when(() => mock.shutdown(true)).thenThrow(StateError('failed'));

      await expectLater(controller.shutdown(true), throwsStateError);
    });

    test('isInit delegates to interface', () async {
      when(() => mock.isInit).thenAnswer((_) async => true);
      final result = await controller.isInit;
      expect(result, true);
    });
  });

  group('config methods', () {
    test('validateConfig delegates to interface', () async {
      when(() => mock.validateConfig('/path')).thenAnswer((_) async => 'ok');
      final result = await controller.validateConfig('/path');
      expect(result, 'ok');
      verify(() => mock.validateConfig('/path')).called(1);
    });

    test('updateConfig delegates to interface', () async {
      const params = UpdateParams(
        tun: Tun(enable: false),
        mixedPort: 7890,
        allowLan: true,
        findProcessMode: FindProcessMode.off,
        mode: Mode.rule,
        logLevel: LogLevel.info,
        ipv6: false,
        tcpConcurrent: false,
        externalController: ExternalControllerStatus.close,
        unifiedDelay: false,
      );
      when(() => mock.updateConfig(params)).thenAnswer((_) async => 'ok');
      final result = await controller.updateConfig(params);
      expect(result, 'ok');
    });

    test('setup failure short-circuits preload callback', () async {
      const params = SetupParams(
        selectedMap: {},
        testUrl: 'https://example.com',
      );
      var preloadCalled = false;
      when(
        () => mock.setupConfig(params),
      ).thenThrow(StateError('core disconnected'));

      await expectLater(
        controller.setupConfig(
          params: params,
          setupState: const SetupState(
            profileId: null,
            profileLastUpdateDate: null,
            overwriteType: OverwriteType.standard,
            rules: [],
            proxyGroups: [],
            addedRules: [],
            script: null,
            overrideDns: false,
            dns: Dns(),
          ),
          preloadInvoke: () async {
            preloadCalled = true;
          },
        ),
        throwsStateError,
      );

      expect(preloadCalled, isFalse);
    });

    test(
      'validateConfigWithData uses home temp and always cleans up',
      () async {
        final home = await Directory.systemTemp.createTemp(
          'flclash-core-test-',
        );
        addTearDown(() => home.delete(recursive: true));
        String? validatedPath;
        when(() => mock.validateConfig(any())).thenAnswer((invocation) async {
          validatedPath = invocation.positionalArguments.single as String;
          expect(p.isWithin(home.path, validatedPath!), isTrue);
          expect(await File(validatedPath!).readAsString(), 'mixed-port: 7890');
          return 'ok';
        });

        final result = await controller.validateConfigWithDataAtHome(
          'mixed-port: 7890',
          home.path,
        );

        expect(result, 'ok');
        expect(validatedPath, isNotNull);
        expect(await File(validatedPath!).exists(), isFalse);
      },
    );

    test('validateConfigWithData cleans up after validation error', () async {
      final home = await Directory.systemTemp.createTemp('flclash-core-test-');
      addTearDown(() => home.delete(recursive: true));
      String? validatedPath;
      when(() => mock.validateConfig(any())).thenAnswer((invocation) async {
        validatedPath = invocation.positionalArguments.single as String;
        throw StateError('validation failed');
      });

      await expectLater(
        controller.validateConfigWithDataAtHome('invalid', home.path),
        throwsStateError,
      );

      expect(validatedPath, isNotNull);
      expect(await File(validatedPath!).exists(), isFalse);
    });
  });

  group('proxy methods', () {
    test('changeProxy delegates to interface', () async {
      const params = ChangeProxyParams(groupName: 'G1', proxyName: 'P1');
      when(() => mock.changeProxy(params)).thenAnswer((_) async => 'ok');
      final result = await controller.changeProxy(params);
      expect(result, 'ok');
    });
  });

  group('connection methods', () {
    test('getConnections parses JSON response', () async {
      when(() => mock.getConnections()).thenAnswer(
        (_) async => json.encode({
          'connections': [
            {
              'id': '1',
              'metadata': {'network': 'tcp'},
              'upload': 0,
              'download': 0,
              'start': '2024-01-01',
              'chains': ['Proxy'],
              'rule': 'DIRECT',
              'rulePayload': '',
            },
          ],
        }),
      );
      final result = await controller.getConnections();
      expect(result.length, 1);
      expect(result.first.id, '1');
    });

    test('getConnections handles empty connections', () async {
      when(
        () => mock.getConnections(),
      ).thenAnswer((_) async => json.encode({'connections': []}));
      final result = await controller.getConnections();
      expect(result, isEmpty);
    });

    test('closeConnection delegates', () async {
      when(() => mock.closeConnection('id1')).thenAnswer((_) async => true);
      await controller.closeConnection('id1');
      verify(() => mock.closeConnection('id1')).called(1);
    });

    test('closeConnection rejects a failed core close', () async {
      when(() => mock.closeConnection('id1')).thenAnswer((_) async => false);

      await expectLater(controller.closeConnection('id1'), throwsStateError);
    });

    test('closeConnections rejects a failed core close', () async {
      when(() => mock.closeConnections()).thenAnswer((_) async => false);

      await expectLater(controller.closeConnections(), throwsStateError);
    });
  });

  group('external providers', () {
    test('getExternalProviders parses JSON', () async {
      when(() => mock.getExternalProviders()).thenAnswer(
        (_) async => json.encode([
          {
            'name': 'provider1',
            'type': 'Proxy',
            'count': 5,
            'vehicle-type': 'HTTP',
            'update-at': DateTime.now().toIso8601String(),
          },
        ]),
      );
      final result = await controller.getExternalProviders();
      expect(result.length, 1);
      expect(result.first.name, 'provider1');
    });

    test('getExternalProviders handles empty string', () async {
      when(() => mock.getExternalProviders()).thenAnswer((_) async => '');
      final result = await controller.getExternalProviders();
      expect(result, isEmpty);
    });

    test('getExternalProvider returns null on empty', () async {
      when(() => mock.getExternalProvider(any())).thenAnswer((_) async => '');
      final result = await controller.getExternalProvider('test');
      expect(result, isNull);
    });
  });

  group('traffic methods', () {
    test('getTraffic handles empty string', () async {
      when(() => mock.getTraffic(false)).thenAnswer((_) async => '');
      final result = await controller.getTraffic(false);
      expect(result.up, 0);
      expect(result.down, 0);
    });

    test('getTraffic parses structured map', () async {
      when(
        () => mock.getTraffic(false),
      ).thenAnswer((_) async => {'up': 11, 'down': 22});
      final result = await controller.getTraffic(false);
      expect(result.up, 11);
      expect(result.down, 22);
    });

    test('getTotalTraffic handles empty string', () async {
      when(() => mock.getTotalTraffic(false)).thenAnswer((_) async => '');
      final result = await controller.getTotalTraffic(false);
      expect(result.up, 0);
      expect(result.down, 0);
    });

    test('getTrafficSnapshot parses now and total from string', () async {
      when(() => mock.getTrafficSnapshot(false)).thenAnswer(
        (_) async => json.encode({
          'now': {'up': 10, 'down': 20},
          'total': {'up': 100, 'down': 200},
        }),
      );
      final result = await controller.getTrafficSnapshot(false);
      expect(result.now.up, 10);
      expect(result.now.down, 20);
      expect(result.total.up, 100);
      expect(result.total.down, 200);
    });

    test('getTrafficSnapshot parses structured map', () async {
      when(() => mock.getTrafficSnapshot(false)).thenAnswer(
        (_) async => {
          'now': {'up': 1, 'down': 2},
          'total': {'up': 3, 'down': 4},
        },
      );
      final result = await controller.getTrafficSnapshot(false);
      expect(result.now.up, 1);
      expect(result.total.down, 4);
    });

    test('getTrafficSnapshot handles empty string', () async {
      when(() => mock.getTrafficSnapshot(false)).thenAnswer((_) async => '');
      final result = await controller.getTrafficSnapshot(false);
      expect(result.now.up, 0);
      expect(result.total.down, 0);
    });

    test('getMemory handles empty string', () async {
      when(() => mock.getMemory()).thenAnswer((_) async => '');
      final result = await controller.getMemory();
      expect(result, 0);
    });
  });

  group('misc methods', () {
    test('getCountryCode returns null on empty string', () async {
      when(() => mock.getCountryCode(any())).thenAnswer((_) async => '');
      final result = await controller.getCountryCode('8.8.8.8');
      expect(result, isNull);
    });

    test('getDelay parses JSON response', () async {
      when(() => mock.asyncTestDelay(any(), any())).thenAnswer(
        (_) async =>
            json.encode({'name': 'P1', 'value': 100, 'url': 'test.com'}),
      );
      final result = await controller.getDelay('test.com', 'P1');
      expect(result.name, 'P1');
      expect(result.value, 100);
    });

    test('startListener delegates', () async {
      when(() => mock.startListener()).thenAnswer((_) async => true);
      final result = await controller.startListener();
      expect(result, true);
    });

    test('stopListener delegates', () async {
      when(() => mock.stopListener()).thenAnswer((_) async => false);
      final result = await controller.stopListener();
      expect(result, false);
    });

    test('updateGeoData delegates', () async {
      when(() => mock.updateGeoData('MMDB')).thenAnswer((_) async => 'ok');
      final result = await controller.updateGeoData('MMDB');
      expect(result, 'ok');
    });

    test('requestGc delegates to forceGc', () async {
      when(() => mock.forceGc()).thenAnswer((_) async => true);
      await controller.requestGc();
      verify(() => mock.forceGc()).called(1);
    });

    test(
      'traffic and log commands await and propagate interface errors',
      () async {
        when(() => mock.resetTraffic()).thenAnswer((_) async {});
        when(
          () => mock.startLog(),
        ).thenAnswer((_) async => throw StateError('disconnected'));
        when(() => mock.stopLog()).thenAnswer((_) async {});

        await controller.resetTraffic();
        await expectLater(controller.startLog(), throwsStateError);
        await controller.stopLog();

        verify(() => mock.resetTraffic()).called(1);
        verify(() => mock.startLog()).called(1);
        verify(() => mock.stopLog()).called(1);
      },
    );

    test('prepareTunHelper delegates and rejects helper errors', () async {
      when(() => mock.prepareTunHelper()).thenAnswer((_) async => '');
      await controller.prepareTunHelper();
      verify(() => mock.prepareTunHelper()).called(1);

      when(
        () => mock.prepareTunHelper(),
      ).thenAnswer((_) async => 'authorization denied');
      await expectLater(controller.prepareTunHelper(), throwsStateError);
    });

    test('releaseTunHelper delegates and rejects helper errors', () async {
      when(() => mock.releaseTunHelper()).thenAnswer((_) async => '');
      await controller.releaseTunHelper();
      verify(() => mock.releaseTunHelper()).called(1);

      when(
        () => mock.releaseTunHelper(),
      ).thenAnswer((_) async => 'helper did not exit');
      await expectLater(controller.releaseTunHelper(), throwsStateError);
    });

    test('deleteFile delegates', () async {
      when(() => mock.deleteFile('/tmp/x')).thenAnswer((_) async => 'ok');
      final result = await controller.deleteFile('/tmp/x');
      expect(result, 'ok');
    });
  });
}
