import 'dart:convert';

import 'package:fl_clash/common/javascript.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passes an isolated config copy to the script runtime', () async {
    final original = <String, dynamic>{'mixed-port': 7890};
    final result = await handleEvaluate(
      'function main(config) { return config; }',
      original,
      evaluator: ({required script, required configJson}) async {
        expect(script, contains('function main'));
        final config = jsonDecode(configJson) as Map<String, dynamic>;
        expect(config['proxy-providers'], isEmpty);
        config['mixed-port'] = 7891;
        return jsonEncode(config);
      },
    );

    expect(result['mixed-port'], 7891);
    expect(original, {'mixed-port': 7890});
  });

  test('propagates runtime failures without reporting success', () async {
    await expectLater(
      handleEvaluate(
        'function main(config) { throw new Error(); }',
        const {},
        evaluator: ({required script, required configJson}) async {
          throw 'JavaScript exception: broken';
        },
      ),
      throwsA('JavaScript exception: broken'),
    );
  });

  test('lets the runtime parse async main declarations', () async {
    var invoked = false;

    final result = await handleEvaluate(
      'async function main(config) { return config; }',
      const {},
      evaluator: ({required script, required configJson}) async {
        invoked = true;
        expect(script, startsWith('async function main'));
        return configJson;
      },
    );
    expect(invoked, true);
    expect(result['proxy-providers'], isEmpty);
  });

  test('propagates the runtime missing-main validation', () async {
    await expectLater(
      handleEvaluate(
        'const value = 1;',
        const {},
        evaluator: ({required script, required configJson}) async {
          throw 'Error: Script must define a main function';
        },
      ),
      throwsA('Error: Script must define a main function'),
    );
  });

  test('rejects non-object JSON results', () async {
    await expectLater(
      handleEvaluate(
        'const main = () => 1;',
        const {},
        evaluator: ({required script, required configJson}) async => '1',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
