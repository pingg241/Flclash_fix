import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/common/resource_limits.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Locale, debugPrint;
import 'package:riverpod/riverpod.dart';

const _testClashUserAgent = 'FlClash/test';

void main() {
  late ProviderContainer providerContainer;

  setUpAll(() async {
    globalState.coreSHA256 = '';
    providerContainer = ProviderContainer();
    globalState.container = providerContainer;
    await AppLocalizations.load(const Locale('en'));
  });

  tearDownAll(() => providerContainer.dispose());

  test('accepts a streamed response exactly at the byte limit', () async {
    final client = Request(
      userAgent: _testClashUserAgent,
      httpClientAdapter: _ResponseAdapter(
        ResponseBody.fromBytes(
          [1, 2, 3, 4],
          200,
          headers: {
            Headers.contentLengthHeader: ['4'],
          },
        ),
      ),
    );

    final response = await client.getFileResponseForUrl(
      'https://example.com/profile',
      maxBytes: 4,
    );

    expect(response.data, [1, 2, 3, 4]);
  });

  test('keeps the browser user agent on general requests', () async {
    final profileAdapter = _RecordingResponseAdapter();
    final generalAdapter = _RecordingResponseAdapter();
    final client = Request(
      userAgent: _testClashUserAgent,
      httpClientAdapter: profileAdapter,
    );
    client.dio.httpClientAdapter = generalAdapter;

    await client.dio.get<Uint8List>(
      'https://example.com/image',
      options: Options(responseType: ResponseType.bytes),
    );

    expect(
      _headerValue(generalAdapter.requests.single, 'User-Agent'),
      browserUa,
    );
  });

  test('forced IP routing tracks the mixed port and keeps direct direct', () {
    final notifier = providerContainer.read(patchClashConfigProvider.notifier);
    notifier.update((state) => state.copyWith(mixedPort: 7891));

    expect(
      Request.resolveIpProxy(useLocalProxy: true),
      'PROXY $localhost:7891',
    );

    notifier.update((state) => state.copyWith(mixedPort: 17890));
    expect(
      Request.resolveIpProxy(useLocalProxy: true),
      'PROXY $localhost:17890',
    );
    expect(Request.resolveIpProxy(useLocalProxy: false), 'DIRECT');
  });

  test('uses the current Clash user agent for profile requests', () async {
    final adapter = _RecordingResponseAdapter();
    final client = Request(httpClientAdapter: adapter);

    client.userAgent = 'FlClash/test-one';
    await client.getFileResponseForUrl('https://example.com/profile-one');
    client.userAgent = 'FlClash/test-two';
    await client.getFileResponseForUrl('https://example.com/profile-two');

    expect(
      adapter.requests
          .map((options) => _headerValue(options, 'User-Agent'))
          .toList(),
      ['FlClash/test-one', 'FlClash/test-two'],
    );
  });

  test('keeps the Clash user agent across automatic redirects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final userAgents = <String?>[];
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      paths.add(request.uri.path);
      userAgents.add(request.headers.value(HttpHeaders.userAgentHeader));
      if (request.uri.path == '/redirect') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/profile');
      } else {
        request.response.add([1, 2, 3]);
      }
      await request.response.close();
    });
    final client = Request(userAgent: _testClashUserAgent);

    final response = await client.getFileResponseForUrl(
      'http://$localhost:${server.port}/redirect',
    );

    expect(response.data, [1, 2, 3]);
    expect(paths, ['/redirect', '/profile']);
    expect(userAgents, [_testClashUserAgent, _testClashUserAgent]);
  });

  test('retries a proxied subscription GET directly exactly once', () async {
    final proxyAdapter = _FailingAdapter(
      DioExceptionType.unknown,
      error: const SocketException('local proxy unavailable'),
    );
    final directAdapter = _RecordingResponseAdapter(body: const [1, 2, 3]);
    final client = Request(
      userAgent: _testClashUserAgent,
      httpClientAdapter: proxyAdapter,
      directHttpClientAdapter: directAdapter,
      subscriptionUsesLocalProxy: (_) => true,
    );

    final response = await client.getFileResponseForUrl(
      'https://subscriptions.example/profile?token=secret',
    );

    expect(response.data, [1, 2, 3]);
    expect(proxyAdapter.requestCount, 1);
    expect(directAdapter.requests, hasLength(1));
    expect(
      _headerValue(directAdapter.requests.single, 'User-Agent'),
      _testClashUserAgent,
    );
  });

  test('does not retry again when the direct attempt fails', () async {
    final proxyAdapter = _FailingAdapter(DioExceptionType.connectionError);
    final directAdapter = _FailingAdapter(DioExceptionType.connectionError);
    final client = Request(
      userAgent: _testClashUserAgent,
      httpClientAdapter: proxyAdapter,
      directHttpClientAdapter: directAdapter,
      subscriptionUsesLocalProxy: (_) => true,
    );

    await expectLater(
      client.getFileResponseForUrl('https://subscriptions.example/profile'),
      throwsA(anything),
    );

    expect(proxyAdapter.requestCount, 1);
    expect(directAdapter.requestCount, 1);
  });

  for (final type in const [
    DioExceptionType.cancel,
    DioExceptionType.badResponse,
  ]) {
    test('does not retry ${type.name} directly', () async {
      final proxyAdapter = _FailingAdapter(type);
      final directAdapter = _RecordingResponseAdapter();
      final client = Request(
        userAgent: _testClashUserAgent,
        httpClientAdapter: proxyAdapter,
        directHttpClientAdapter: directAdapter,
        subscriptionUsesLocalProxy: (_) => true,
      );

      await expectLater(
        client.getFileResponseForUrl('https://subscriptions.example/profile'),
        throwsA(anything),
      );

      expect(proxyAdapter.requestCount, 1);
      expect(directAdapter.requests, isEmpty);
    });
  }

  test('does not retry an oversized response directly', () async {
    final directAdapter = _RecordingResponseAdapter();
    final client = Request(
      userAgent: _testClashUserAgent,
      httpClientAdapter: _ResponseAdapter(
        ResponseBody.fromBytes(
          const [],
          200,
          headers: {
            Headers.contentLengthHeader: ['5'],
          },
        ),
      ),
      directHttpClientAdapter: directAdapter,
      subscriptionUsesLocalProxy: (_) => true,
    );

    await expectLater(
      client.getFileResponseForUrl(
        'https://subscriptions.example/profile',
        maxBytes: 4,
      ),
      throwsA(isA<InputTooLargeException>()),
    );

    expect(directAdapter.requests, isEmpty);
  });

  test('rejects an oversized declared content length and cancels', () async {
    final adapter = _ResponseAdapter(
      ResponseBody.fromBytes(
        const [],
        200,
        headers: {
          Headers.contentLengthHeader: ['5'],
        },
      ),
    );
    final client = Request(
      userAgent: _testClashUserAgent,
      httpClientAdapter: adapter,
    );

    await expectLater(
      client.getFileResponseForUrl('https://example.com/profile', maxBytes: 4),
      throwsA(isA<InputTooLargeException>()),
    );
    await adapter.cancelled;
  });

  test(
    'cancels a chunked response when accumulated bytes exceed limit',
    () async {
      final controller = StreamController<Uint8List>();
      final adapter = _ResponseAdapter(ResponseBody(controller.stream, 200));
      final client = Request(
        userAgent: _testClashUserAgent,
        httpClientAdapter: adapter,
      );
      scheduleMicrotask(() {
        controller.add(Uint8List.fromList([1, 2]));
        controller.add(Uint8List.fromList([3, 4, 5]));
      });

      await expectLater(
        client.getFileResponseForUrl(
          'https://example.com/profile',
          maxBytes: 4,
        ),
        throwsA(isA<InputTooLargeException>()),
      );
      await adapter.cancelled;
      await controller.close();
    },
  );

  test(
    'a total timeout cancels a response body that never completes',
    () async {
      final adapter = _HangingBodyAdapter();
      final client = Request(
        userAgent: _testClashUserAgent,
        httpClientAdapter: adapter,
      );

      await expectLater(
        client.getFileResponseForUrl(
          'https://example.com/profile',
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await adapter.cancelled;
    },
  );

  for (final entry in const {
    'token': 'fake-token-secret',
    'OwO': 'fake-owo-secret',
  }.entries) {
    test('redacts ${entry.key} query values from errors and logs', () async {
      final client = Request(
        userAgent: _testClashUserAgent,
        httpClientAdapter: _FailingAdapter(DioExceptionType.connectionError),
      );
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) logs.add(message);
      };
      Object? error;
      try {
        await client.getFileResponseForUrl(
          'https://user:password@subscriptions.example/private/profile'
          '?${entry.key}=${entry.value}#fragment',
        );
      } catch (caught) {
        error = caught;
      } finally {
        debugPrint = previousDebugPrint;
      }

      expect(error, currentAppLocalizations.networkException);
      expect(error.toString(), isNot(contains(entry.value)));
      expect(logs.join('\n'), isNot(contains(entry.value)));
      final output = logs.join('\n');
      expect(output, contains('https://subscriptions.example'));
      expect(output, isNot(contains('user')));
      expect(output, isNot(contains('password')));
      expect(output, isNot(contains('/private')));
      expect(output, isNot(contains('fragment')));
      expect(output, isNot(contains(entry.value)));
    });
  }

  test(
    'preserves cancellation type without exposing its request URI',
    () async {
      const secret = 'fake-cancel-secret';
      final client = Request(
        userAgent: _testClashUserAgent,
        httpClientAdapter: _FailingAdapter(DioExceptionType.cancel),
      );
      Object? error;
      try {
        await client.getFileResponseForUrl(
          'https://subscriptions.example/profile?token=$secret',
        );
      } catch (caught) {
        error = caught;
      }

      expect(
        error,
        isA<DioException>().having(
          (exception) => exception.type,
          'type',
          DioExceptionType.cancel,
        ),
      );
      expect(error.toString(), isNot(contains(secret)));
      expect((error! as DioException).requestOptions.uri.query, isEmpty);
    },
  );

  test('maps Dio timeouts to a URL-free TimeoutException', () async {
    const secret = 'fake-timeout-secret';
    final client = Request(
      userAgent: _testClashUserAgent,
      httpClientAdapter: _FailingAdapter(DioExceptionType.receiveTimeout),
    );

    await expectLater(
      client.getFileResponseForUrl(
        'https://subscriptions.example/profile?OwO=$secret',
      ),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains(secret)),
        ),
      ),
    );
  });

  test('maps a safe unknown TLS failure to a network error', () async {
    const secret = 'fake-handshake-secret';
    final client = Request(
      userAgent: _testClashUserAgent,
      httpClientAdapter: _FailingAdapter(
        DioExceptionType.unknown,
        error: const HandshakeException('TLS failed: $secret'),
      ),
    );
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
    Object? error;
    try {
      await client.getFileResponseForUrl(
        'https://subscriptions.example/profile?token=$secret',
      );
    } catch (caught) {
      error = caught;
    } finally {
      debugPrint = previousDebugPrint;
    }

    expect(error, currentAppLocalizations.networkException);
    expect(logs.join('\n'), isNot(contains(secret)));
  });

  test('helper operation reconciles a lost response by request id', () async {
    final adapter = _HelperReconciliationAdapter();
    final client = Request(
      helperRequestTimeout: const Duration(milliseconds: 50),
      helperReconciliationTimeout: const Duration(milliseconds: 20),
      helperStatusPollInterval: const Duration(milliseconds: 1),
    );
    client.dio.httpClientAdapter = adapter;

    expect(await client.stopCoreByHelper(), isTrue);
    expect(adapter.postRequestId, isNotEmpty);
    expect(adapter.statusRequestId, adapter.postRequestId);
  });
}

Object? _headerValue(RequestOptions options, String name) {
  final normalizedName = name.toLowerCase();
  for (final entry in options.headers.entries) {
    if (entry.key.toLowerCase() == normalizedName) {
      return entry.value;
    }
  }
  return null;
}

class _RecordingResponseAdapter implements HttpClientAdapter {
  final List<int> body;
  final List<RequestOptions> requests = [];

  _RecordingResponseAdapter({this.body = const []});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromBytes(body, 200);
  }

  @override
  void close({bool force = false}) {}
}

class _ResponseAdapter implements HttpClientAdapter {
  final ResponseBody response;
  final Completer<void> _cancelled = Completer<void>();

  _ResponseAdapter(this.response);

  Future<void> get cancelled => _cancelled.future;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    cancelFuture?.then(
      (_) => _completeCancellation(),
      onError: (_) => _completeCancellation(),
    );
    return response;
  }

  void _completeCancellation() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }

  @override
  void close({bool force = false}) {}
}

class _HangingBodyAdapter implements HttpClientAdapter {
  final Completer<void> _cancelled = Completer<void>();
  final StreamController<Uint8List> _body = StreamController<Uint8List>();

  Future<void> get cancelled => _cancelled.future;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    cancelFuture?.then(
      (_) => _completeCancellation(),
      onError: (_) => _completeCancellation(),
    );
    return Future.value(ResponseBody(_body.stream, 200));
  }

  void _completeCancellation() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
    if (!_body.isClosed) {
      _body.close();
    }
  }

  @override
  void close({bool force = false}) {}
}

class _FailingAdapter implements HttpClientAdapter {
  final DioExceptionType type;
  final Object? error;
  int requestCount = 0;

  _FailingAdapter(this.type, {this.error});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requestCount++;
    throw DioException(
      requestOptions: options,
      type: type,
      error: error ?? 'failed request: ${options.uri}',
      message: 'failed request: ${options.uri}',
    );
  }

  @override
  void close({bool force = false}) {}
}

class _HelperReconciliationAdapter implements HttpClientAdapter {
  String postRequestId = '';
  String statusRequestId = '';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST') {
      postRequestId = options.headers['x-flclash-request-id'] as String;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    statusRequestId = options.path.split('/').last;
    return ResponseBody.fromString(
      '{"done":true,"error":""}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
