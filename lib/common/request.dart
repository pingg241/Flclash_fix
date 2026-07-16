import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

class Request {
  // Must remain longer than helper OPERATION_TIMEOUT (5s) so a normal local
  // operation completes before reconciliation starts.
  static const _defaultHelperRequestTimeout = Duration(seconds: 7);
  static const _defaultHelperReconciliationTimeout = Duration(seconds: 2);
  static const _defaultHelperStatusPollInterval = Duration(milliseconds: 50);
  static final Random _helperRequestRandom = Random.secure();

  late final Dio dio;
  late final Dio _clashDio;
  final Duration _helperRequestTimeout;
  final Duration _helperReconciliationTimeout;
  final Duration _helperStatusPollInterval;
  String? userAgent;

  Request({
    this.userAgent,
    HttpClientAdapter? httpClientAdapter,
    Duration helperRequestTimeout = _defaultHelperRequestTimeout,
    Duration helperReconciliationTimeout = _defaultHelperReconciliationTimeout,
    Duration helperStatusPollInterval = _defaultHelperStatusPollInterval,
  }) : _helperRequestTimeout = helperRequestTimeout,
       _helperReconciliationTimeout = helperReconciliationTimeout,
       _helperStatusPollInterval = helperStatusPollInterval {
    dio = Dio(
      BaseOptions(
        headers: {'User-Agent': browserUa},
        connectTimeout: ExternalInputLimits.connectTimeout,
        receiveTimeout: ExternalInputLimits.receiveTimeout,
      ),
    );
    _clashDio = Dio(
      BaseOptions(
        connectTimeout: ExternalInputLimits.connectTimeout,
        receiveTimeout: ExternalInputLimits.receiveTimeout,
      ),
    );
    _clashDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['User-Agent'] = userAgent ?? globalState.ua;
          handler.next(options);
        },
      ),
    );
    _clashDio.httpClientAdapter =
        httpClientAdapter ??
        IOHttpClientAdapter(
          createHttpClient: () {
            final client = HttpClient();
            client.findProxy = (Uri uri) {
              client.userAgent = userAgent ?? globalState.ua;
              return FlClashHttpOverrides.handleFindProxy(uri);
            };
            return client;
          },
        );
  }

  Future<Response<Uint8List>> getFileResponseForUrl(
    String url, {
    int maxBytes = ExternalInputLimits.profileBytes,
    String inputName = 'Profile',
    Duration timeout = ExternalInputLimits.downloadTimeout,
  }) async {
    try {
      return await _getBytesResponseForUrl(
        url,
        maxBytes: maxBytes,
        inputName: inputName,
        timeout: timeout,
      );
    } catch (e) {
      commonPrint.log(
        'getFileResponseForUrl failed (${e.runtimeType})',
        logLevel: LogLevel.warning,
      );
      if (e is InputTooLargeException || e is TimeoutException) {
        rethrow;
      }
      if (e is DioException) {
        final cause = e.error;
        if (cause is InputTooLargeException) throw cause;
        if (cause is TimeoutException) {
          throw TimeoutException('$inputName download timed out', timeout);
        }
        switch (e.type) {
          case DioExceptionType.cancel:
            throw DioException.requestCancelled(
              requestOptions: RequestOptions(path: 'about:blank'),
              reason: 'Request cancelled',
              stackTrace: e.stackTrace,
            );
          case DioExceptionType.connectionTimeout:
          case DioExceptionType.sendTimeout:
          case DioExceptionType.receiveTimeout:
          case DioExceptionType.transformTimeout:
            throw TimeoutException('$inputName download timed out', timeout);
          case DioExceptionType.unknown:
            throw currentAppLocalizations.unknownNetworkError;
          case DioExceptionType.badCertificate:
          case DioExceptionType.badResponse:
          case DioExceptionType.connectionError:
            throw currentAppLocalizations.networkException;
        }
      }
      throw currentAppLocalizations.unknownNetworkError;
    }
  }

  Future<Response<String>> getTextResponseForUrl(
    String url, {
    int maxBytes = ExternalInputLimits.editorTextBytes,
    String inputName = 'Text',
    Duration timeout = ExternalInputLimits.downloadTimeout,
  }) async {
    final response = await _getBytesResponseForUrl(
      url,
      maxBytes: maxBytes,
      inputName: inputName,
      timeout: timeout,
    );
    return Response<String>(
      data: utf8.decode(response.data ?? Uint8List(0)),
      requestOptions: response.requestOptions,
      statusCode: response.statusCode,
      statusMessage: response.statusMessage,
      isRedirect: response.isRedirect,
      redirects: response.redirects,
      extra: response.extra,
      headers: response.headers,
    );
  }

  Future<MemoryImage?> getImage(String url) async {
    if (url.isEmpty) return null;
    final response = await _getBytesResponseForUrl(
      url,
      maxBytes: ExternalInputLimits.imageBytes,
      inputName: 'Image',
      client: dio,
      timeout: ExternalInputLimits.downloadTimeout,
    );
    final data = response.data;
    if (data == null) return null;
    return MemoryImage(data);
  }

  Future<Response<Uint8List>> _getBytesResponseForUrl(
    String url, {
    required int maxBytes,
    required String inputName,
    required Duration timeout,
    Dio? client,
  }) async {
    final cancelToken = CancelToken();
    final effectiveClient = client ?? _clashDio;
    Future<Response<Uint8List>> download() async {
      final response = await effectiveClient.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.stream),
      );
      final declaredLength = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      if (declaredLength != null && declaredLength > maxBytes) {
        cancelToken.cancel('$inputName response is too large');
        throw InputTooLargeException(inputName, maxBytes);
      }
      final body = response.data;
      final bytes = body == null
          ? Uint8List(0)
          : await collectBytesWithLimit(
              body.stream,
              maxBytes: maxBytes,
              inputName: inputName,
              onLimitExceeded: () {
                cancelToken.cancel('$inputName response is too large');
              },
            );
      return Response<Uint8List>(
        data: bytes,
        requestOptions: response.requestOptions,
        statusCode: response.statusCode,
        statusMessage: response.statusMessage,
        isRedirect: response.isRedirect,
        redirects: response.redirects,
        extra: response.extra,
        headers: response.headers,
      );
    }

    return download().timeout(
      timeout,
      onTimeout: () {
        cancelToken.cancel('$inputName download timed out');
        throw TimeoutException('$inputName download timed out', timeout);
      },
    );
  }

  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final response = await dio.get(
        'https://api.github.com/repos/$repository/releases/latest',
        options: Options(responseType: ResponseType.json),
      );
      if (response.statusCode != 200) return null;
      final data = response.data as Map<String, dynamic>;
      final remoteVersion = data['tag_name'];
      final version = globalState.packageInfo.version;
      final hasUpdate =
          utils.compareVersions(remoteVersion.replaceAll('v', ''), version) > 0;
      if (!hasUpdate) return null;
      return data;
    } catch (e) {
      commonPrint.log('checkForUpdate failed', logLevel: LogLevel.warning);
      return null;
    }
  }

  final Map<String, IpInfo Function(Map<String, dynamic>)> _ipInfoSources = {
    'https://ipwho.is': IpInfo.fromIpWhoIsJson,
    'https://api.myip.com': IpInfo.fromMyIpJson,
    'https://ipapi.co/json': IpInfo.fromIpApiCoJson,
    'https://ident.me/json': IpInfo.fromIdentMeJson,
    'http://ip-api.com/json': IpInfo.fromIpAPIJson,
    'https://api.ip.sb/geoip': IpInfo.fromIpSbJson,
    'https://ipinfo.io/json': IpInfo.fromIpInfoIoJson,
  };

  Future<Result<IpInfo?>> checkIp({CancelToken? cancelToken}) async {
    var failureCount = 0;
    final token = cancelToken ?? CancelToken();
    final futures = _ipInfoSources.entries.map((source) async {
      final Completer<Result<IpInfo?>> completer = Completer();
      void handleFailRes() {
        if (!completer.isCompleted && failureCount == _ipInfoSources.length) {
          completer.complete(Result.success(null));
        }
      }

      final future = dio
          .get<Map<String, dynamic>>(
            source.key,
            cancelToken: token,
            options: Options(responseType: ResponseType.json),
          )
          .timeout(const Duration(seconds: 10));
      future
          .then((res) {
            if (res.statusCode == HttpStatus.ok && res.data != null) {
              completer.complete(Result.success(source.value(res.data!)));
              return;
            }
            commonPrint.log('checkIp data empty', logLevel: LogLevel.info);
            failureCount++;
            handleFailRes();
          })
          .catchError((e) {
            failureCount++;
            if (e is DioException && e.type == DioExceptionType.cancel) {
              completer.complete(Result.error('cancelled'));
              return;
            }
            commonPrint.log('checkIp error $e', logLevel: LogLevel.warning);
            handleFailRes();
          });
      return completer.future;
    });
    final res = await Future.any(futures);
    token.cancel();
    return res;
  }

  Map<String, String> get _helperHeaders {
    final token = globalState.coreSHA256;
    if (token.isEmpty) {
      return const {};
    }
    return {'x-flclash-token': token};
  }

  Future<bool> pingHelper() async {
    if (kDebugMode) return true;
    try {
      final response = await dio
          .get(
            'http://$localhost:$helperPort/ping',
            options: Options(
              responseType: ResponseType.plain,
              headers: _helperHeaders,
            ),
          )
          .timeout(const Duration(milliseconds: 2000));
      if (response.statusCode != HttpStatus.ok) {
        return false;
      }
      return (response.data as String) == globalState.coreSHA256;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startCoreByHelper({
    required List<String> args,
    required String ipcToken,
  }) async {
    return _runHelperOperation(
      'start',
      data: {'path': appPath.corePath, 'args': args, 'ipcToken': ipcToken},
    );
  }

  Future<bool> stopCoreByHelper() async {
    return _runHelperOperation('stop');
  }

  Future<bool> _runHelperOperation(String operation, {Object? data}) async {
    final serverDeadline = DateTime.now().add(_helperRequestTimeout);
    final requestId = List.generate(
      16,
      (_) =>
          _helperRequestRandom.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final headers = {..._helperHeaders, 'x-flclash-request-id': requestId};
    try {
      final response = await dio
          .post(
            'http://$localhost:$helperPort/$operation',
            data: data,
            options: Options(responseType: ResponseType.json, headers: headers),
          )
          .timeout(_helperRequestTimeout);
      final result = _helperOperationResult(response);
      if (result != null && result.$1) {
        return result.$2.isEmpty;
      }
    } catch (_) {
      // The operation may still have completed; reconcile by request id.
    }

    final responseMarginDeadline = DateTime.now().add(
      _helperReconciliationTimeout,
    );
    final deadline = serverDeadline.isAfter(responseMarginDeadline)
        ? serverDeadline
        : responseMarginDeadline;
    do {
      try {
        final response = await dio
            .get(
              'http://$localhost:$helperPort/operation/$requestId',
              options: Options(
                responseType: ResponseType.json,
                headers: _helperHeaders,
              ),
            )
            .timeout(_helperStatusPollInterval * 10);
        final result = _helperOperationResult(response);
        if (result != null && result.$1) {
          return result.$2.isEmpty;
        }
      } catch (_) {
        // Keep polling until the server-side operation deadline has elapsed.
      }
      await Future<void>.delayed(_helperStatusPollInterval);
    } while (DateTime.now().isBefore(deadline));
    return false;
  }

  (bool, String)? _helperOperationResult(Response<dynamic> response) {
    if (response.statusCode != HttpStatus.ok || response.data is! Map) {
      return null;
    }
    final data = response.data as Map<dynamic, dynamic>;
    final done = data['done'];
    final error = data['error'];
    if (done is! bool || error is! String) {
      return null;
    }
    return (done, error);
  }
}

final request = Request();
