import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/common/resource_limits.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    globalState.coreSHA256 = '';
  });

  test('accepts a streamed response exactly at the byte limit', () async {
    final client = Request(
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
    final client = Request(httpClientAdapter: adapter);

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
      final client = Request(httpClientAdapter: adapter);
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
      final client = Request(httpClientAdapter: adapter);

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
