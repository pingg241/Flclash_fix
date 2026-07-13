import 'dart:async';

Future<void> _setupChain = Future<void>.value();
const Symbol _setupZoneKey = #flclashSetupSerialized;

/// Serialize setup/restart critical paths. Nested calls on the same chain
/// re-enter directly to avoid deadlock (e.g. applyProfile -> restartCore).
Future<T> serializedSetup<T>(Future<T> Function() fn) {
  if (Zone.current[_setupZoneKey] == true) {
    return fn();
  }
  final completer = Completer<T>();
  _setupChain = _setupChain.catchError((_) {}).then((_) {
    return runZoned(() async {
      try {
        completer.complete(await fn());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    }, zoneValues: {_setupZoneKey: true});
  });
  return completer.future;
}
