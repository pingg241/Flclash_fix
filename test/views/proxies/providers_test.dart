import 'dart:convert';

import 'package:fl_clash/models/core.dart';
import 'package:fl_clash/views/proxies/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final provider = ExternalProvider(
    name: 'provider',
    type: 'Proxy',
    vehicleType: 'HTTP',
    count: 1,
    updateAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  test('provider side-load validates before reading refreshed state', () async {
    var getCalls = 0;

    await expectLater(
      sideLoadProviderBytes(
        providerName: provider.name,
        bytes: utf8.encode('invalid'),
        sideLoad: ({required providerName, required data}) async =>
            'invalid provider',
        getProvider: (_) async {
          getCalls++;
          return provider;
        },
      ),
      throwsA('invalid provider'),
    );

    expect(getCalls, 0);
  });

  test('provider side-load publishes only the validated provider', () async {
    final updated = provider.copyWith(count: 2);
    String? receivedData;

    final result = await sideLoadProviderBytes(
      providerName: provider.name,
      bytes: utf8.encode('proxies: []'),
      sideLoad: ({required providerName, required data}) async {
        expect(providerName, provider.name);
        receivedData = data;
        return '';
      },
      getProvider: (providerName) async {
        expect(providerName, provider.name);
        return updated;
      },
    );

    expect(receivedData, 'proxies: []');
    expect(result, updated);
  });

  test(
    'provider side-load rejects malformed UTF-8 before core invocation',
    () async {
      var sideLoadCalls = 0;

      await expectLater(
        sideLoadProviderBytes(
          providerName: provider.name,
          bytes: const [0xC3, 0x28],
          sideLoad: ({required providerName, required data}) async {
            sideLoadCalls++;
            return '';
          },
          getProvider: (_) async => provider,
        ),
        throwsA(isA<FormatException>()),
      );

      expect(sideLoadCalls, 0);
    },
  );
}
