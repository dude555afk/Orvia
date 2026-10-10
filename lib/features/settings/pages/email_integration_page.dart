import 'package:flutter/material.dart';
import '../../../core/services/email/email_awareness_service.dart';
import '../../../core/services/email/email_integration_service.dart';

/// All email passwords live in secure storage. No login secrets pass through
/// model messages or the main Orvia settings database.
class EmailIntegrationPage extends StatefulWidget {
  const EmailIntegrationPage({super.key});

  @override
  State<EmailIntegrationPage> createState() => _EmailIntegrationPageState();
}

class _EmailIntegrationPageState extends State<EmailIntegrationPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _imap = TextEditingController();
  final _smtp = TextEditingController();
  final _imapPort = TextEditingController(text: '993');
  final _smtpPort = TextEditingController(text: '465');
  bool _smtpStartTls = false;
  bool _busy = false;
  bool _advanced = false;
  String? _error;
  List<String> _connected = [];
  bool _awarenessOn = true;
  bool _mailAlerts = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    for (final c in [_email, _password, _imap, _smtp, _imapPort, _smtpPort]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final all = await EmailIntegrationService.instance.accounts();
      final awareness = EmailAwarenessService.instance;
      await awareness.refreshAccounts();
      if (mounted) {
        setState(() {
          _connected = all.map((a) => a.address).toList();
          _awarenessOn = awareness.enabled;
          _mailAlerts = awareness.alertsEnabled;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to open secure email storage.');
      }
    }
  }

  void _usePreset() {
    final preset = EmailAccount.preset(_email.text);
    if (preset == null) {
      setState(() {
        _advanced = true;
        _error = 'No known preset. Enter IMAP and SMTP settings.';
      });
      return;
    }
    setState(() {
      _imap.text = preset.imap;
      _imapPort.text = '993';
      _smtp.text = preset.smtp;
      _smtpPort.text = preset.smtpPort.toString();
      _smtpStartTls = preset.startTls;
      _error = null;
    });
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = EmailAccount(
        address: _email.text.trim(),
        password: _password.text,
        imapHost: _imap.text.trim(),
        imapPort: int.parse(_imapPort.text.trim()),
        smtpHost: _smtp.text.trim(),
        smtpPort: int.parse(_smtpPort.text.trim()),
        smtpStartTls: _smtpStartTls,
      );
      await EmailIntegrationService.instance.connect(config);
      _password.clear();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Email connected. Orvia can discover its native email tools while awareness is on.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not connect. Check the server details and use an app password if your provider requires one.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect email?'),
        content: Text(
          'Remove the saved credentials for $account from this device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await EmailIntegrationService.instance.remove(account);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Email integration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Connected accounts',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (_connected.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No email accounts connected yet.'),
            ),
          for (final account in _connected)
            ListTile(
              leading: const Icon(Icons.mark_email_read_outlined),
              title: Text(account),
              trailing: IconButton(
                icon: const Icon(Icons.link_off_outlined),
                tooltip: 'Disconnect',
                onPressed: _busy ? null : () => _remove(account),
              ),
            ),
          SwitchListTile(
            title: const Text('Email awareness'),
            subtitle: const Text(
              'Let Orvia assistants discover connected email and check mail '
              'using native tools. Email contents can reach your selected AI '
              'provider when a tool is called. Sending always needs approval.',
            ),
            value: _awarenessOn,
            onChanged: _busy
                ? null
                : (value) async {
                    try {
                      await EmailAwarenessService.instance.setEnabled(value);
                      await _refresh();
                    } catch (_) {
                      if (mounted) {
                        setState(() => _error = 'Could not update email awareness.');
                      }
                    }
                  },
          ),
          SwitchListTile(
            title: const Text('New mail notifications'),
            subtitle: const Text(
              'Check unread mail every five minutes while Orvia is open. '
              'Only show a private notification count, never email subjects.',
            ),
            value: _mailAlerts,
            onChanged: _busy || !_awarenessOn || _connected.isEmpty
                ? null
                : (value) async {
                    try {
                      final granted = await EmailAwarenessService.instance
                          .setAlertsEnabled(value);
                      if (!granted && mounted) {
                        setState(() => _error = 'Notification permission required.');
                      }
                      await _refresh();
                    } catch (_) {
                      if (mounted) {
                        setState(() => _error = 'Could not update mail alerts.');
                      }
                    }
                  },
          ),
          const Divider(height: 32),
          const Text(
            'Connect an email account',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Uses IMAP and SMTP with encrypted connections. Some providers '
            'require a separate app password, and some only accept OAuth. '
            'Google sign-in is not available in this version.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email address',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _usePreset,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('Detect provider settings'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Mail app password',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            value: _advanced,
            title: const Text('Server settings'),
            subtitle: const Text('Advanced: custom IMAP/SMTP servers'),
            onChanged: (v) => setState(() => _advanced = v),
          ),
          if (_advanced) ...[
            TextField(
              controller: _imap,
              decoration: const InputDecoration(
                labelText: 'IMAP server (TLS)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _imapPort,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'IMAP port (normally 993)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _smtp,
              decoration: const InputDecoration(
                labelText: 'SMTP server',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _smtpPort,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'SMTP port',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              title: const Text('SMTP STARTTLS'),
              subtitle: const Text(
                'Use for port 587. Port 465 uses TLS immediately.',
              ),
              value: _smtpStartTls,
              onChanged: (value) => setState(() => _smtpStartTls = value),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _connect,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: const Text('Connect'),
          ),
          const SizedBox(height: 16),
          const Text(
            'When email awareness is enabled, connected accounts are available '
            'to your assistants without configuring MCP or individual local tools. '
            'Automatic mail checks run only while Orvia is open. '
            'Outgoing messages always need your confirmation.',
          ),
        ],
      ),
    );
  }
}
