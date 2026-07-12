import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:flutter_js/flutter_js.dart';

final _mainFunctionPattern = RegExp(
  r'(?:function\s+main\s*\(|(?:const|let|var)\s+main\s*=|main\s*=\s*(?:async\s*)?(?:function|\())',
);

Future<Map<String, dynamic>> handleEvaluate(
  String scriptContent,
  Map<String, dynamic> config,
) async {
  if (!_mainFunctionPattern.hasMatch(scriptContent)) {
    throw 'Script must define a main function';
  }
  if (config['proxy-providers'] == null) {
    config['proxy-providers'] = {};
  }
  final configJs = json.encode(config);
  final runtime = getJavascriptRuntime();
  final res = await runtime
      .evaluateAsync('''
      $scriptContent
      main($configJs)
    ''')
      .timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw 'Script evaluation timed out';
        },
      );
  if (res.isError) {
    throw res.stringResult;
  }
  final value = switch (res.rawResult is ffi.Pointer) {
    true => runtime.convertValue<Map<String, dynamic>>(res),
    false => Map<String, dynamic>.from(res.rawResult),
  };
  return value ?? config;
}
