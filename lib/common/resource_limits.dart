import 'dart:async';
import 'dart:typed_data';

abstract final class ExternalInputLimits {
  static const int profileBytes = 16 * 1024 * 1024;
  static const int editorTextBytes = 4 * 1024 * 1024;
  static const int scriptBytes = 1024 * 1024;
  static const int imageBytes = 5 * 1024 * 1024;

  static const int javascriptStackBytes = 1024 * 1024;
  static const int javascriptMemoryBytes = 64 * 1024 * 1024;
  static const int javascriptConfigBytes = profileBytes;
  static const int javascriptResultBytes = profileBytes;
  static const Duration javascriptTimeout = Duration(seconds: 15);

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration downloadTimeout = Duration(minutes: 2);
}

class InputTooLargeException implements Exception {
  final String inputName;
  final int maxBytes;

  const InputTooLargeException(this.inputName, this.maxBytes);

  @override
  String toString() {
    final String limit;
    if (maxBytes < 1024) {
      limit = '$maxBytes bytes';
    } else if (maxBytes < 1024 * 1024) {
      limit = '${(maxBytes / 1024).toStringAsFixed(1)} KiB';
    } else {
      final maxMiB = maxBytes / (1024 * 1024);
      limit = maxMiB == maxMiB.roundToDouble()
          ? '${maxMiB.toInt()} MiB'
          : '${maxMiB.toStringAsFixed(1)} MiB';
    }
    return '$inputName exceeds the $limit size limit';
  }
}

Future<Uint8List> collectBytesWithLimit(
  Stream<List<int>> stream, {
  required int maxBytes,
  required String inputName,
  void Function()? onLimitExceeded,
}) async {
  final builder = BytesBuilder(copy: false);
  var total = 0;
  await for (final chunk in stream) {
    total += chunk.length;
    if (total > maxBytes) {
      onLimitExceeded?.call();
      throw InputTooLargeException(inputName, maxBytes);
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}
