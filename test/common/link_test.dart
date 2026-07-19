import 'dart:async';

import 'package:fl_clash/common/link.dart';
import 'package:flutter/foundation.dart';
import 'package:test/test.dart';

void main() {
  late StreamController<Uri> controller;
  late LinkManager manager;

  setUp(() {
    controller = StreamController<Uri>.broadcast();
    manager = LinkManager.test(controller.stream);
  });

  tearDown(() async {
    await manager.destroy();
    await controller.close();
  });

  test('forwards only install-config URLs', () async {
    final urls = <String>[];
    await manager.initAppLinksListen(urls.add);

    controller.add(Uri.parse('flclash://other?url=https://ignored.example'));
    controller.add(
      Uri.parse('https://install-config?url=https://ignored.example/scheme'),
    );
    controller.add(
      Uri.parse(
        'flclash://user@install-config?url=https://ignored.example/user',
      ),
    );
    controller.add(
      Uri.parse(
        'flclash://install-config/path?url=https://ignored.example/path',
      ),
    );
    controller.add(
      Uri.parse(
        'flclash://install-config?url=https%3A%2F%2Fexample.com%2Fa.yaml',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(urls, ['https://example.com/a.yaml']);
  });

  test('reinitialization detaches the previous callback', () async {
    final firstUrls = <String>[];
    final secondUrls = <String>[];
    await manager.initAppLinksListen(firstUrls.add);
    await manager.initAppLinksListen(secondUrls.add);

    controller.add(
      Uri.parse(
        'flclash://install-config?url=https%3A%2F%2Fexample.com%2Fb.yaml',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(firstUrls, isEmpty);
    expect(secondUrls, ['https://example.com/b.yaml']);
  });

  test('destroy prevents late events from reaching the callback', () async {
    final urls = <String>[];
    await manager.initAppLinksListen(urls.add);
    await manager.destroy();

    controller.add(
      Uri.parse(
        'flclash://install-config?url=https%3A%2F%2Fexample.com%2Fc.yaml',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(urls, isEmpty);
  });

  test('does not write subscription credentials to debug logs', () async {
    final messages = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = previousDebugPrint);
    await manager.initAppLinksListen((_) {});

    controller.add(
      Uri.parse(
        'flclash://install-config?url='
        'https%3A%2F%2Fexample.com%2Fprofile%3Ftoken%3Dsecret-token',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(messages.join('\n'), isNot(contains('secret-token')));
    expect(messages.join('\n'), isNot(contains('token%3D')));
  });
}
