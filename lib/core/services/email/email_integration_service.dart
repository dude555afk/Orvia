import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Account passwords are stored in the platform secure store, not in chats or
/// ordinary app settings. SMTP and IMAP never authenticate without TLS.
class EmailAccount {
  const EmailAccount({
    required this.address,
    required this.password,
    required this.imapHost,
    required this.smtpHost,
    this.imapPort = 993,
    this.smtpPort = 465,
    this.smtpStartTls = false,
  });

  final String address;
  final String password;
  final String imapHost;
  final String smtpHost;
  final int imapPort;
  final int smtpPort;
  final bool smtpStartTls;

  Map<String, dynamic> toJson() => {
    'address': address,
    'password': password,
    'imapHost': imapHost,
    'imapPort': imapPort,
    'smtpHost': smtpHost,
    'smtpPort': smtpPort,
    'smtpStartTls': smtpStartTls,
  };

  factory EmailAccount.fromJson(Map<String, dynamic> json) => EmailAccount(
    address: json['address'] as String,
    password: json['password'] as String,
    imapHost: json['imapHost'] as String,
    imapPort: (json['imapPort'] as num?)?.toInt() ?? 993,
    smtpHost: json['smtpHost'] as String,
    smtpPort: (json['smtpPort'] as num?)?.toInt() ?? 465,
    smtpStartTls: json['smtpStartTls'] == true,
  );

  static ({String imap, String smtp, int smtpPort, bool startTls})? preset(
    String address,
  ) {
    switch (address.trim().toLowerCase().split('@').last) {
      case 'gmail.com':
      case 'googlemail.com':
        return (
          imap: 'imap.gmail.com',
          smtp: 'smtp.gmail.com',
          smtpPort: 465,
          startTls: false,
        );
      case 'outlook.com':
      case 'hotmail.com':
      case 'live.com':
        return (
          imap: 'outlook.office365.com',
          smtp: 'smtp.office365.com',
          smtpPort: 587,
          startTls: true,
        );
      case 'yahoo.com':
        return (
          imap: 'imap.mail.yahoo.com',
          smtp: 'smtp.mail.yahoo.com',
          smtpPort: 465,
          startTls: false,
        );
      case 'icloud.com':
      case 'me.com':
        return (
          imap: 'imap.mail.me.com',
          smtp: 'smtp.mail.me.com',
          smtpPort: 587,
          startTls: true,
        );
      default:
        return null;
    }
  }

  void validate() {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address) ||
        password.isEmpty) {
      throw const FormatException('Valid email and app password required.');
    }
    for (final host in [imapHost, smtpHost]) {
      if (!RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(host) ||
          host.startsWith('-') ||
          host.contains('..')) {
        throw const FormatException('Invalid mail server name.');
      }
    }
    if (imapPort < 1 || imapPort > 65535 || smtpPort < 1 || smtpPort > 65535) {
      throw const FormatException('Invalid mail server port.');
    }
  }
}

class EmailIntegrationService {
  EmailIntegrationService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static final EmailIntegrationService instance = EmailIntegrationService();
  static const _accountsKey = 'orvia_email_accounts_v1';
  final FlutterSecureStorage _storage;

  Future<List<EmailAccount>> accounts() async {
    final data = await _storage.read(key: _accountsKey);
    if (data == null || data.isEmpty) return [];
    return (jsonDecode(data) as List)
        .map(
          (value) =>
              EmailAccount.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
  }

  Future<void> connect(EmailAccount account) async {
    account.validate();
    await _withInbox(account, (imap) async {});
    final all = await accounts();
    all.removeWhere(
      (e) => e.address.toLowerCase() == account.address.toLowerCase(),
    );
    all.add(account);
    await _storage.write(
      key: _accountsKey,
      value: jsonEncode(all.map((a) => a.toJson()).toList()),
    );
  }

  Future<void> remove(String address) async {
    final all = await accounts();
    all.removeWhere((e) => e.address.toLowerCase() == address.toLowerCase());
    await _storage.write(
      key: _accountsKey,
      value: jsonEncode(all.map((e) => e.toJson()).toList()),
    );
    await _storage.delete(key: _cursorKey(address));
    await _storage.delete(key: _pendingKey(address));
  }

  Future<EmailAccount> _resolve(Object? address) async {
    final all = await accounts();
    if (all.isEmpty) {
      throw StateError('Connect email in Settings > Integrations > Email.');
    }
    final key = (address ?? '').toString().trim().toLowerCase();
    if (key.isEmpty && all.length == 1) return all.single;
    for (final account in all) {
      if (account.address.toLowerCase() == key) return account;
    }
    throw StateError('Select an email account in Integrations settings.');
  }

  String _cursorKey(String address) =>
      'orvia_email_last_seen_${address.trim().toLowerCase()}';

  Future<T> _withInbox<T>(
    EmailAccount account,
    Future<T> Function(ImapClient) action,
  ) async {
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(
        account.imapHost,
        account.imapPort,
        isSecure: true,
      );
      await client.login(account.address, account.password);
      await client.selectInbox();
      return await action(client);
    } finally {
      if (client.isConnected) await client.disconnect();
    }
  }

  Map<String, dynamic> _summary(MimeMessage m, String account) => {
    'account': account,
    'uid': m.uid,
    'from': m.fromEmail ?? '',
    'subject': m.decodeSubject() ?? '',
    'unread': !(m.flags?.contains(r'\Seen') ?? false),
  };

  String _pendingKey(String address) =>
      'orvia_email_pending_${address.trim().toLowerCase()}';

  Future<List<Map<String, dynamic>>> _readPending(String address) async {
    final raw = await _storage.read(key: _pendingKey(address));
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final values = jsonDecode(raw) as List<dynamic>;
      return values
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// Retains new messages until check_email actually delivers them to chat.
  /// Keys are account + IMAP UID, so repeated foreground polls cannot repeat
  /// notifications for messages already queued.
  static List<Map<String, dynamic>> mergePendingSummaries(
    List<Map<String, dynamic>> queued,
    List<Map<String, dynamic>> incoming,
  ) {
    final byMessage = <String, Map<String, dynamic>>{};
    for (final item in [...queued, ...incoming]) {
      final key = '${item['account']}/${item['uid']}';
      byMessage[key] = item;
    }
    final result = byMessage.values.toList();
    return result.length > 50 ? result.sublist(result.length - 50) : result;
  }

  /// Checks every connected inbox (or just one). Periodic polling uses
  /// consume=false; actual assistant delivery uses consume=true.
  Future<Map<String, dynamic>> check({
    Object? account,
    bool consume = true,
  }) async {
    final requested = (account ?? '').toString().trim();
    final targets = requested.isEmpty
        ? await accounts()
        : <EmailAccount>[await _resolve(requested)];
    if (targets.isEmpty) {
      throw StateError('Connect email in Settings > Integrations > Email.');
    }

    final messages = <Map<String, dynamic>>[];
    final errors = <String>[];
    var freshCount = 0;
    for (final cfg in targets) {
      try {
        final queued = await _readPending(cfg.address);
        final cursor = await _storage.read(key: _cursorKey(cfg.address));
        // First activation starts from the current mailbox high-water mark.
        // Old unread mail is searchable, but should not trigger "new" alerts.
        if (cursor == null) {
          final highWater = await _withInbox(cfg, (imap) async {
            final result = await imap.uidSearchMessages(
              searchCriteria: 'ALL',
            );
            final ids = result.matchingSequence?.toList() ?? <int>[];
            return ids.isEmpty ? 0 : ids.reduce((a, b) => a > b ? a : b);
          });
          await _storage.write(
            key: _cursorKey(cfg.address),
            value: highWater.toString(),
          );
          messages.addAll(queued);
          if (consume) await _storage.delete(key: _pendingKey(cfg.address));
          continue;
        }
        final last = int.tryParse(cursor) ?? 0;
        final news = await _withInbox(cfg, (imap) async {
          final result = await imap.uidSearchMessages(
            searchCriteria: 'UNSEEN',
          );
          final unseenUids = result.matchingSequence?.toList() ?? <int>[];
          final newUids = unseenUids.where((uid) => uid > last).toList()
            ..sort();
          if (newUids.isEmpty) return <MimeMessage>[];
          final selected = newUids.length > 20
              ? newUids.sublist(newUids.length - 20)
              : newUids;
          final fetched = await imap.uidFetchMessages(
            MessageSequence.fromIds(selected, isUid: true),
            '(UID FLAGS BODY.PEEK[])',
          );
          return fetched.messages;
        });
        news.sort((a, b) => (a.uid ?? 0).compareTo(b.uid ?? 0));
        final fresh = news.map((m) => _summary(m, cfg.address)).toList();
        freshCount += fresh.length;
        final pending = mergePendingSummaries(queued, fresh);
        messages.addAll(pending);
        if (news.isNotEmpty && news.last.uid != null) {
          await _storage.write(
            key: _cursorKey(cfg.address),
            value: news.last.uid!.toString(),
          );
        }
        if (consume) {
          await _storage.delete(key: _pendingKey(cfg.address));
        } else {
          await _storage.write(
            key: _pendingKey(cfg.address),
            value: jsonEncode(pending),
          );
        }
      } catch (_) {
        // Keep previously queued mail if this account is temporarily offline.
        errors.add('Could not check ${cfg.address}. Verify mail settings.');
        messages.addAll(await _readPending(cfg.address));
      }
    }
    return {
      'count': messages.length,
      'new_count': freshCount,
      'messages': messages,
      'accounts': targets.map((item) => item.address).toList(),
      if (errors.isNotEmpty) 'errors': errors,
      if (messages.isEmpty)
        'hint': 'No new unread mail. Use search_email to find older messages.',
    };
  }

  Future<Map<String, dynamic>> read({Object? account, required int uid}) async {
    if (uid < 1) throw const FormatException('Invalid message UID.');
    final cfg = await _resolve(account);
    final msg = await _withInbox(cfg, (imap) async {
      final r = await imap.uidFetchMessage(uid, '(UID FLAGS BODY.PEEK[])');
      if (r.messages.isEmpty) throw StateError('Message not found.');
      return r.messages.first;
    });
    final body = msg.decodeTextPlainPart() ?? '';
    return {
      ..._summary(msg, cfg.address),
      'body': body.length > 40000 ? body.substring(0, 40000) : body,
    };
  }

  Future<Map<String, dynamic>> search({
    Object? account,
    required String query,
  }) async {
    final cfg = await _resolve(account);
    if (query.trim().isEmpty ||
        query.length > 200 ||
        query.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('Search query must be 1-200 characters.');
    }
    final term = query.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final messages = await _withInbox(cfg, (imap) async {
      final search = await imap.uidSearchMessages(
        searchCriteria: 'OR OR FROM "$term" SUBJECT "$term" TEXT "$term"',
      );
      final ids = search.matchingSequence?.toList() ?? <int>[];
      if (ids.isEmpty) return <MimeMessage>[];
      final recent = ids.length > 25 ? ids.sublist(ids.length - 25) : ids;
      final fetched = await imap.uidFetchMessages(
        MessageSequence.fromIds(recent, isUid: true),
        '(UID FLAGS BODY.PEEK[])',
      );
      return fetched.messages;
    });
    return {
      'account': cfg.address,
      'count': messages.length,
      'messages': messages.map((m) => _summary(m, cfg.address)).toList(),
    };
  }

  /// Mirrors Kai's best-effort Sent mailbox handling. A failed archive must
  /// never turn a successfully delivered SMTP message into a resend.
  Future<String?> _saveSentCopy(
    EmailAccount account,
    MimeMessage message,
  ) async {
    // Gmail automatically saves messages sent through its SMTP server.
    if (account.smtpHost.toLowerCase() == 'smtp.gmail.com') {
      return '[Gmail]/Sent Mail';
    }
    final imap = ImapClient(isLogEnabled: false);
    try {
      await imap.connectToServer(
        account.imapHost,
        account.imapPort,
        isSecure: true,
      );
      await imap.login(account.address, account.password);
      final mailboxes = await imap.listMailboxes(recursive: true);
      final candidates = <String>{
        ...mailboxes.where((m) => m.isSent).map((m) => m.path),
        ...const ['Sent', 'Sent Messages', 'Sent Items', 'INBOX.Sent'],
      };
      for (final path in candidates) {
        try {
          await imap.appendMessage(message, targetMailboxPath: path);
          return path;
        } catch (_) {
          // Some servers reject paths that are not configured.
        }
      }
      try {
        await imap.createMailbox('Sent');
        await imap.appendMessage(message, targetMailboxPath: 'Sent');
        return 'Sent';
      } catch (_) {
        // The outgoing message was already delivered via SMTP.
      }
    } catch (_) {
      // Sent-folder archival is intentionally best effort.
    } finally {
      if (imap.isConnected) await imap.disconnect();
    }
    return null;
  }

  /// Only called after the user's per-message send confirmation.
  Future<Map<String, dynamic>> send({
    Object? account,
    required String to,
    required String subject,
    required String body,
    int? replyUid,
  }) async {
    final cfg = await _resolve(account);
    if (!RegExp(r'^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$').hasMatch(to.trim()) ||
        body.trim().isEmpty ||
        body.length > 100000 ||
        subject.length > 998 ||
        subject.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('Invalid recipient, subject, or body.');
    }
    MimeMessage? replyTo;
    if (replyUid != null) {
      if (replyUid < 1) throw const FormatException('Invalid reply UID.');
      replyTo = await _withInbox(cfg, (imap) async {
        final r = await imap.uidFetchMessage(replyUid, '(UID BODY.PEEK[])');
        if (r.messages.isEmpty) throw StateError('Original message not found.');
        return r.messages.first;
      });
      final expected =
          replyTo!.replyTo?.firstOrNull?.email ?? replyTo.fromEmail;
      if (expected == null ||
          expected.toLowerCase() != to.trim().toLowerCase()) {
        throw const FormatException(
          'Reply recipient must match original sender.',
        );
      }
    }
    final message = MessageBuilder.buildSimpleTextMessage(
      MailAddress('', cfg.address),
      [MailAddress('', to.trim())],
      body,
      subject: subject,
      replyToMessage: replyTo,
    );
    final smtp = SmtpClient(cfg.address.split('@').last, isLogEnabled: false);
    try {
      await smtp.connectToServer(
        cfg.smtpHost,
        cfg.smtpPort,
        isSecure: !cfg.smtpStartTls,
      );
      await smtp.ehlo();
      if (cfg.smtpStartTls) {
        final upgraded = await smtp.startTls();
        if (!upgraded.isOkStatus) {
          throw StateError('SMTP server refused STARTTLS encryption.');
        }
        await smtp.ehlo();
      }
      final mechanism = smtp.serverInfo.supportsAuth(AuthMechanism.plain)
          ? AuthMechanism.plain
          : smtp.serverInfo.supportsAuth(AuthMechanism.login)
          ? AuthMechanism.login
          : null;
      if (mechanism == null) {
        throw StateError('Mail server does not offer password authentication.');
      }
      await smtp.authenticate(cfg.address, cfg.password, mechanism);
      final response = await smtp.sendMessage(message);
      if (!response.isOkStatus) {
        throw StateError('Mail server rejected the message.');
      }
      final sentFolder = await _saveSentCopy(cfg, message);
      return {
        'status': 'sent',
        'account': cfg.address,
        'to': to,
        'subject': subject,
        if (sentFolder != null) 'saved_to_sent_folder': sentFolder,
        if (sentFolder == null)
          'warning': 'Message sent, but could not save a Sent-folder copy.',
      };
    } finally {
      if (smtp.isConnected) await smtp.disconnect();
    }
  }

  Future<String> handleTool(
    String tool,
    Map<String, dynamic> args, {
    bool sendApproved = false,
  }) async {
    try {
      final account = args['account'];
      Map<String, dynamic> result;
      switch (tool) {
        case 'setup_email':
          result = {
            'message':
                'Open Settings > Integrations > Email to connect an account securely. Never send passwords in chat.',
          };
          break;
        case 'check_email':
          result = await check(account: account);
          break;
        case 'search_email':
          result = await search(
            account: account,
            query: (args['query'] ?? '').toString(),
          );
          break;
        case 'read_email':
          result = await read(
            account: account,
            uid: int.parse((args['uid'] ?? '').toString()),
          );
          break;
        case 'compose_email':
        case 'reply_email':
          if (!sendApproved) {
            result = {
              'error': 'approval_required',
              'message': 'Confirm each outgoing email before sending.',
            };
          } else {
            result = await send(
              account: account,
              to: (args['to'] ?? '').toString(),
              subject: (args['subject'] ?? '').toString(),
              body: (args['body'] ?? '').toString(),
              replyUid: tool == 'reply_email'
                  ? int.parse((args['uid'] ?? '').toString())
                  : null,
            );
          }
          break;
        default:
          result = {'error': 'unknown_email_tool'};
          break;
      }
      return jsonEncode(result);
    } catch (_) {
      return jsonEncode({
        'error': 'email_operation_failed',
        'message':
            'Email action failed. Check server, permissions and account settings.',
      });
    }
  }
}
