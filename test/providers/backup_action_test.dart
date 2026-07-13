import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> configMap(Config config) {
    return jsonDecode(jsonEncode(config.toJson())) as Map<String, Object?>;
  }

  test('rejects an unsupported config version before restore', () {
    final data = configMap(const Config(themeProps: defaultThemeProps));
    data['version'] = migration.currentVersion + 1;

    expect(
      () => validateBackupConfig(
        data,
        const Config(themeProps: defaultThemeProps),
      ),
      throwsFormatException,
    );
  });

  test('rejects malformed and plaintext credential configuration', () {
    final malformed = configMap(const Config(themeProps: defaultThemeProps))
      ..addAll({'version': migration.currentVersion, 'davProps': 'invalid'});
    final plaintext = configMap(const Config(themeProps: defaultThemeProps))
      ..addAll({
        'version': migration.currentVersion,
        'davProps': {
          'uri': 'https://dav.example.com',
          'user': 'alice',
          'password': 'plaintext',
        },
      });

    expect(
      () => validateBackupConfig(
        malformed,
        const Config(themeProps: defaultThemeProps),
      ),
      throwsFormatException,
    );
    expect(
      () => validateBackupConfig(
        plaintext,
        const Config(themeProps: defaultThemeProps),
      ),
      throwsFormatException,
    );
  });

  test('reuses only a matching local credential reference', () {
    final restoredMap = configMap(
      const Config(
        themeProps: defaultThemeProps,
        davProps: DAVProps(
          uri: 'https://dav.example.com',
          user: 'alice',
          password: '',
        ),
      ),
    )..['version'] = migration.currentVersion;
    const current = Config(
      themeProps: defaultThemeProps,
      davProps: DAVProps(
        uri: 'https://dav.example.com',
        user: 'alice',
        password: 'local-secret',
      ),
    );

    final restored = validateBackupConfig(restoredMap, current);

    expect(restored.davProps?.password, 'local-secret');
  });
}
