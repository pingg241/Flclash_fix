import 'dart:async';

import 'package:fl_clash/views/backup_and_restore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('late WebDAV ping cannot overwrite the current account', () async {
    var generation = 1;
    final first = Completer<bool>();
    final second = Completer<bool>();
    final published = <bool>[];
    final firstUpdate = publishLatestDavPing(
      ping: first.future,
      generation: generation,
      currentGeneration: () => generation,
      canPublish: () => true,
      publish: published.add,
    );
    generation++;
    final secondUpdate = publishLatestDavPing(
      ping: second.future,
      generation: generation,
      currentGeneration: () => generation,
      canPublish: () => true,
      publish: published.add,
    );

    second.complete(true);
    await secondUpdate;
    first.complete(false);
    await firstUpdate;

    expect(published, [true]);
  });
}
