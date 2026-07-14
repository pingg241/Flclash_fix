import 'dart:async';

typedef StorageRecoveryOperation = Future<void> Function();

class StorageRecoveryCoordinator {
  final StorageRecoveryOperation recoverClearTransactions;
  final StorageRecoveryOperation recoverRestoreTransactions;
  final StorageRecoveryOperation recoverConfigTransactions;
  Future<void>? _recovery;

  StorageRecoveryCoordinator({
    required this.recoverClearTransactions,
    required this.recoverRestoreTransactions,
    required this.recoverConfigTransactions,
  });

  Future<void> recover() {
    return _recovery ??= _run();
  }

  Future<void> _run() async {
    await recoverClearTransactions();
    await recoverRestoreTransactions();
    await recoverConfigTransactions();
  }
}
