import 'dart:convert';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Rule.parse', () {
    test('round-trips MATCH without inventing a payload', () {
      final rule = Rule.parse('MATCH,DIRECT', id: 1);

      expect(rule.ruleAction, RuleAction.MATCH);
      expect(rule.content, isNull);
      expect(rule.ruleTarget, 'DIRECT');
      expect(rule.rawValue, 'MATCH,DIRECT');
    });

    test('round-trips nested logical rule payloads', () {
      const values = [
        'AND,((DOMAIN,example.com),(NETWORK,TCP)),DIRECT',
        'OR,((NETWORK,UDP),(NOT,((DST-PORT,53)))),REJECT',
        'NOT,((DOMAIN-SUFFIX,example.com)),Proxy',
        'SUB-RULE,(OR,((NETWORK,TCP),(NETWORK,UDP))),sub-rule-name1',
      ];

      for (final value in values) {
        expect(Rule.parse(value, id: 1).rawValue, value);
      }
    });

    test('only recognizes exact trailing parameter tokens', () {
      final targetNamedSrc = Rule.parse(
        'RULE-SET,src-provider,src,no-resolve',
        id: 1,
      );
      final parameters = Rule.parse(
        'RULE-SET,provider,DIRECT, src , no-resolve',
        id: 2,
      );
      final srcInValues = Rule.parse('DOMAIN,src.example.com,src', id: 3);

      expect(targetNamedSrc.ruleProvider, 'src-provider');
      expect(targetNamedSrc.ruleTarget, 'src');
      expect(targetNamedSrc.src, false);
      expect(targetNamedSrc.noResolve, true);
      expect(parameters.src, true);
      expect(parameters.noResolve, true);
      expect(parameters.rawValue, 'RULE-SET,provider,DIRECT,src,no-resolve');
      expect(srcInValues.content, 'src.example.com');
      expect(srcInValues.ruleTarget, 'src');
      expect(srcInValues.src, false);
    });

    test('preserves wildcard payloads and normalizes shorthand rules', () {
      final explicit = Rule.parse(
        'DOMAIN-WILDCARD,*.example.com,DIRECT',
        id: 1,
      );
      final shorthand = Rule.parse('*.example.com,DIRECT', id: 2);

      expect(explicit.ruleAction, RuleAction.DOMAIN_WILDCARD);
      expect(explicit.rawValue, 'DOMAIN-WILDCARD,*.example.com,DIRECT');
      expect(shorthand.ruleAction, RuleAction.DOMAIN);
      expect(shorthand.content, '*.example.com');
      expect(shorthand.ruleTarget, 'DIRECT');
      expect(shorthand.rawValue, 'DOMAIN,*.example.com,DIRECT');
    });

    test('round-trips every wildcard rule supported by Mihomo', () {
      const values = [
        'DOMAIN-WILDCARD,*.example.com,DIRECT',
        'PROCESS-NAME-WILDCARD,chrome*,DIRECT',
        r'PROCESS-PATH-WILDCARD,C:\\Program Files\\*\\app.exe,REJECT',
      ];

      for (final value in values) {
        expect(Rule.parse(value, id: 1).rawValue, value);
      }
    });

    test(
      'preserves unknown explicit rules instead of treating them as domains',
      () {
        const value = 'FUTURE-RULE,payload,DIRECT,option';

        final rule = Rule.parse(value, id: 1);

        expect(rule.ruleAction, RuleAction.UNKNOWN);
        expect(rule.content, value);
        expect(rule.rawValue, value);
      },
    );

    test('preserves wildcard and unknown rules through JSON', () {
      const values = [
        'DOMAIN-WILDCARD,*.example.com,DIRECT',
        'FUTURE-RULE,payload,DIRECT,option',
      ];

      for (final value in values) {
        final rule = Rule.parse(value, id: 1);
        final restored = Rule.fromJson(
          jsonDecode(jsonEncode(rule.toJson())) as Map<String, Object?>,
        );
        expect(restored.rawValue, value);
      }
    });

    test('does not throw for missing fields', () {
      for (final value in ['', 'MATCH', 'DOMAIN', 'AND']) {
        expect(() => Rule.parse(value, id: 1), returnsNormally);
      }

      expect(Rule.parse('MATCH', id: 1).ruleTarget, isNull);
      expect(Rule.parse('DOMAIN', id: 1).content, isNull);
      expect(Rule.parse('AND', id: 1).content, isNull);
    });
  });
}
