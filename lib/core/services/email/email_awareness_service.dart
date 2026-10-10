import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../notification_service.dart';
import 'email_integration_service.dart';
import 'email_tool_definitions.dart';

/// App-lifetime, foreground-only native mail awareness. Connecting an account
/// opts into tool discovery; alerts remain separately opt-in. No MCP involved.
class EmailAwarenessService with WidgetsBindingObserver {
  EmailAwarenessService._();

  static final EmailAwarenessService instance = EmailAwarenessService._();
  static const _enabledKey = 'orvia_email_awareness_enabled_v1';
  static const _alertsKey = 'orvia_email_awareness_alerts_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  Timer? _timer;
  bool _initialized = false;
  bool _polling = false;
  bool _foreground = true;
  bool _enabled = true;
  bool _alerts = false;
  int _accountCount = 0;
  int _pendingCount = 0;

  bool get enabled => _enabled;

  void markDelivered() {
    _pendingCount = 0;
  }

  bool get alertsEnabled => _alerts;
  int get accountCount => _accountCount;
  int get pendingCount => _pendingCount;
  bool get active => !kIsWeb && _enabled && _accountCount > 0;

  /// A mailbox connection is required before assistants may use mail tools.
  /// Disconnecting every account immediately revokes automatic exposure.
  bool exposesTool(String toolName) =>
      active && EmailToolDefinitions.names.contains(toolName);

  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    _initialized = true;
    try {
      _enabled = (await _storage.read(key: _enabledKey)) != 'false';
      _alerts = (await _storage.read(key: _alertsKey)) == 'true';
      await refreshAccounts();
      WidgetsBinding.instance.addObserver(this);
      _timer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => unawaited(poll()),
      );
      if (active) unawaited(poll());
    } catch (_) {
      _initialized = false;
      rethrow;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    _initialized = false;
  }

  Future<void> refreshAccounts() async {
    if (kIsWeb) return;
    _accountCount = (await EmailIntegrationService.instance.accounts()).length;
    if (_accountCount == 0 || !_enabled) _pendingCount = 0;
  }

  Future<void> setEnabled(bool value) async {
    await _storage.write(key: _enabledKey, value: value.toString());
    _enabled = value;
    if (value) {
      await refreshAccounts();
      unawaited(poll());
    } else {
      _pendingCount = 0;
    }
  }

  Future<bool> setAlertsEnabled(bool value) async {
    if (value) {
      final granted =
          await NotificationService.ensureAndroidNotificationsPermission();
      if (!granted) return false;
    }
    await _storage.write(key: _alertsKey, value: value.toString());
    _alerts = value;
    return true;
  }

  /// Polls only while the Flutter app is active. Does not consume new-mail
  /// summaries: the assistant's next check_email call can still report them.
  Future<void> poll() async {
    if (!active || !_foreground || _polling) return;
    _polling = true;
    try {
      final result = await EmailIntegrationService.instance.check(
        consume: false,
      );
      _pendingCount = (result['count'] as int?) ?? 0;
      final newCount = (result['new_count'] as int?) ?? 0;
      if (newCount > 0 && _alerts) {
        await NotificationService.showIncomingEmailCount(newCount);
      }
    } catch (_) {
      // A transient mail error must never interrupt chat or app startup.
    } finally {
      _polling = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(
        refreshAccounts().then((_) => poll()).catchError((Object _) {}),
      );
    }
  }
}
