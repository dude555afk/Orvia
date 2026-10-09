import 'package:flutter/material.dart';

import '../../mcp/pages/mcp_page.dart';

/// Central place for account and service integrations.
///
/// Native email connection isn't implemented yet. Keep it visibly unavailable
/// rather than presenting a Connect button that cannot authorize an account.
class IntegrationsSettingsPage extends StatelessWidget {
  const IntegrationsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Integrations')),
      body: ListView(
        children: [
          const ListTile(
            leading: Icon(Icons.mail_outline),
            title: Text('Email'),
            subtitle: Text(
              'Coming soon: connect email accounts, read, search, draft and reply. Sending will require your confirmation.',
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
