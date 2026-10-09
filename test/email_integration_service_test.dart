import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orvia/core/services/email/email_integration_service.dart';
import 'package:orvia/core/services/email/email_tool_definitions.dart';
import 'package:orvia/features/home/services/local_tools_service.dart';

void main() {
  test('email tool schemas never request passwords', () {
    for (final name in EmailToolDefinitions.names) {
      final definition = EmailToolDefinitions.forName(name);
      final function = definition['function'] as Map<String, dynamic>;
      final params = function['parameters'] as Map<String, dynamic>;
      final props = params['properties'] as Map<String, dynamic>;
      expect(props.containsKey('password'), isFalse);
      expect(LocalToolNames.all, contains(name));
    }
  });

  test('sending email tools require a user approval', () async {
    final service = EmailIntegrationService();
    for (final name in EmailToolDefinitions.sends) {
      final raw = await service.handleTool(name, {
        'to': 'friend@example.com',
        'subject': 'Hello',
        'body': 'test',
      });
      expect(jsonDecode(raw)['error'], 'approval_required');
      expect(LocalToolNames.requiresUserApproval, contains(name));
    }
  });

  test('email provider presets and credential validation', () {
    final gmail = EmailAccount.preset('person@gmail.com');
    expect(gmail?.imap, 'imap.gmail.com');
    expect(gmail?.smtpPort, 465);
    expect(EmailAccount.preset('person@other.test'), isNull);
    final invalid = EmailAccount(
      address: 'not-an-email',
      password: 'fake',
      imapHost: 'imap.example.com',
      smtpHost: 'smtp.example.com',
    );
    expect(invalid.validate, throwsFormatException);
  });
}
