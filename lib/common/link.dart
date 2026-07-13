import 'dart:async';

import 'package:app_links/app_links.dart';

import 'print.dart';

typedef InstallConfigCallback = FutureOr<void> Function(String url);

class LinkManager {
  static const _allowedSchemes = {'clash', 'clashmeta', 'flclash'};
  static LinkManager? _instance;
  final AppLinks? _appLinks;
  final Stream<Uri>? _uriLinkStream;
  StreamSubscription<Uri>? _subscription;
  int _generation = 0;

  LinkManager._internal() : _appLinks = AppLinks(), _uriLinkStream = null;

  LinkManager.test(Stream<Uri> uriLinkStream)
    : _appLinks = null,
      _uriLinkStream = uriLinkStream;

  Future<void> initAppLinksListen(
    InstallConfigCallback installConfigCallback,
  ) async {
    commonPrint.log('initAppLinksListen');
    final generation = ++_generation;
    await _cancelSubscription();
    if (generation != _generation) {
      return;
    }
    final stream = _uriLinkStream ?? _appLinks!.uriLinkStream;
    _subscription = stream.listen(
      (uri) => _handleUri(uri, generation, installConfigCallback),
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _generation) {
          return;
        }
        commonPrint.log('App link stream failed: $error\n$stackTrace');
      },
    );
  }

  void _handleUri(
    Uri uri,
    int generation,
    InstallConfigCallback installConfigCallback,
  ) {
    if (generation != _generation) {
      return;
    }
    commonPrint.log('onAppLink: $uri');
    if (!_allowedSchemes.contains(uri.scheme.toLowerCase()) ||
        uri.host.toLowerCase() != 'install-config' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return;
    }
    final url = uri.queryParameters['url'];
    if (url == null) {
      return;
    }
    unawaited(
      Future<void>.sync(() => installConfigCallback(url)).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        commonPrint.log('App link callback failed: $error\n$stackTrace');
      }),
    );
  }

  Future<void> destroy() async {
    _generation++;
    await _cancelSubscription();
  }

  Future<void> _cancelSubscription() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  factory LinkManager() {
    _instance ??= LinkManager._internal();
    return _instance!;
  }
}

final linkManager = LinkManager();
