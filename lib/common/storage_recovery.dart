import 'dart:async';

typedef StorageRecoveryOperation = Future<void> Function();

class StorageRecoveryCoordinator {
  final StorageRecoveryOperation recoverClearTransactions;
  final StorageRecoveryOperation recoverRestoreTransactions;
  Future<void>? _recovery;

  StorageRecoveryCoordinator({
    required this.recoverClearTransactions,
    required this.recoverRestoreTransactions,
  });

  Future<void> recover() {
    return _recovery ??= _run();
  }

  Future<void> _run() async {
    await recoverClearTransactions();
    await recoverRestoreTransactions();
  }
}
