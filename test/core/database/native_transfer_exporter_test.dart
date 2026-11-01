import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/database/native_transfer_exporter.dart';

void main() {
  group('NativeTransferExporter', () {
    test('redacts nested credentials but preserves ordinary settings', () {
      final redactedFields = <String>[];
      final result = NativeTransferExporter.redactSecretsForTesting(
        <String, Object?>{
          'provider_api_key': 'provider-secret',
          'rawConfig':
              '{"apiKey":"nested-secret","baseUrl":"https://example.invalid"}',
          'apiBaseUrl': 'https://example.invalid/v1',
          'tokenCount': 12,
          'settings': <String, Object?>{
            'accessToken': 'access-secret',
            'refresh_token': 'refresh-secret',
            'theme': 'dark',
          },
          'tools': <Object?>[
            <String, Object?>{
              'authorization': 'Bearer private',
              'name': 'calendar',
            },
          ],
        },
        redactedFields: redactedFields,
      );

      expect(result, {
        'apiBaseUrl': 'https://example.invalid/v1',
        'rawConfig': '{"baseUrl":"https://example.invalid"}',
        'tokenCount': 12,
        'settings': {'theme': 'dark'},
        'tools': [
          {'name': 'calendar'},
        ],
      });
      expect(redactedFields, hasLength(5));
      expect(
        redactedFields,
        containsAll([
          'root.provider_api_key',
          'root.rawConfig.apiKey',
          'root.settings.accessToken',
          'root.settings.refresh_token',
          'root.tools[0].authorization',
        ]),
      );
    });


    test('removes local device paths inside nested JSON settings', () {
      final result = NativeTransferExporter.redactDevicePathsForTesting(
        <String, Object?>{
          'workspace': <String, Object?>{
            'name': 'Project',
            'rootPath': '/data/user/0/com.example/files/project',
          },
          'serializedMounts':
              '[{"name":"shared","mountPath":"/storage/emulated/0"}]',
          'apiBaseUrl': 'https://example.invalid/v1',
        },
      );

      expect(result, {
        'workspace': {'name': 'Project'},
        'serializedMounts': '[{"name":"shared"}]',
        'apiBaseUrl': 'https://example.invalid/v1',
      });
    });

    test('redacts credential containers recursively in lists', () {
      final redactedFields = <String>[];
      final result = NativeTransferExporter.redactSecretsForTesting(
        <String, Object?>{
          'accounts': <Object?>[
            <String, Object?>{
              'username': 'person@example.invalid',
              'credentials': <String, Object?>{
                'password': 'hidden',
                'client_secret': 'hidden-too',
              },
            },
          ],
        },
        redactedFields: redactedFields,
      );

      expect(result, {
        'accounts': [
          {'username': 'person@example.invalid'},
        ],
      });
      expect(redactedFields, hasLength(1));
      expect(redactedFields.single, 'root.accounts[0].credentials');
    });
  });
}
