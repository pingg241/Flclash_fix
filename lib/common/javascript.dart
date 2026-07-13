import 'dart:convert';

import 'package:fl_clash/common/resource_limits.dart';
import 'package:rust_api/rust_api.dart';

typedef ScriptEvaluator =
    Future<String> Function({
      required String script,
      required String configJson,
    });

Future<Map<String, dynamic>> handleEvaluate(
  String scriptContent,
  Map<String, dynamic> config, {
  ScriptEvaluator evaluator = evaluateScript,
}) async {
  if (utf8.encode(scriptContent).length > ExternalInputLimits.scriptBytes) {
    throw const InputTooLargeException(
      'Script',
      ExternalInputLimits.scriptBytes,
    );
  }
  final mutableConfig = Map<String, dynamic>.from(config);
  if (mutableConfig['proxy-providers'] == null) {
    mutableConfig['proxy-providers'] = <String, dynamic>{};
  }
  final configJson = jsonEncode(mutableConfig);
  if (utf8.encode(configJson).length >
      ExternalInputLimits.javascriptConfigBytes) {
    throw const InputTooLargeException(
      'Config',
      ExternalInputLimits.javascriptConfigBytes,
    );
  }
  final output = await evaluator(script: scriptContent, configJson: configJson);
  if (utf8.encode(output).length > ExternalInputLimits.javascriptResultBytes) {
    throw const InputTooLargeException(
      'Script result',
      ExternalInputLimits.javascriptResultBytes,
    );
  }
  final value = jsonDecode(output);
  if (value is! Map) {
    throw const FormatException('Script result must be a JSON object');
  }
  return Map<String, dynamic>.from(value);
}
