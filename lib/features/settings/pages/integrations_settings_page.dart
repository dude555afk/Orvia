import 'package:flutter/material.dart';

import '../../mcp/pages/mcp_page.dart';
import 'email_integration_page.dart';

/// Central place for account and service integrations.
///
/// Connected accounts and extension configuration live here.
class IntegrationsSettingsPage extends StatelessWidget {
  const IntegrationsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Integrations')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Email'),
            subtitle: const Text('Connect IMAP/SMTP accounts and manage email tools'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EmailIntegrationPage()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: const Text('MCP integrations'),
            subtitle: const Text(
              'Configure available external tools and services',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const McpPage())),
          ),
        ],
      ),
    );
  }
}
