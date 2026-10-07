import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/services/app_exit_flush.dart';
import '../l10n/app_localizations.dart';

/// Desktop tray + window close behaviour controller.
///
/// - Manages system tray icon visibility and context menu
/// - Implements "minimize to tray on close" when enabled in settings
class DesktopTrayController with TrayListener, WindowListener {
  DesktopTrayController._();
  static final DesktopTrayController instance = DesktopTrayController._();

  bool _initialized = false;
  bool _isDesktop = false;
  bool _trayVisible = false;
  bool _showTraySetting = false;
  bool _minimizeToTrayOnClose = false;
  String _localeKey = '';
  bool _contextMenuOpen = false;

  /// Sync tray state from settings & current localization.
  /// Safe to call multiple times; initialization is performed lazily.
  Future<void> syncFromSettings(
    AppLocalizations l10n, {
    required bool showTray,
    required bool minimizeToTrayOnClose,
  }) async {
    if (kIsWeb) return;
    final isDesktop =
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (!isDesktop) return;
    _isDesktop = true;

    if (!_initialized) {
      try {
        await windowManager.ensureInitialized();
      } catch (_) {}
      try {
        trayManager.addListener(this);
      } catch (_) {}
      try {
        windowManager.addListener(this);
      } catch (_) {}
      _initialized = true;
    }

    // Persist latest settings (enforce basic invariant in controller as well).
    _showTraySetting = showTray;
    _minimizeToTrayOnClose = showTray && minimizeToTrayOnClose;

    // Whether to intercept window close.
    final shouldPreventClose = _showTraySetting && _minimizeToTrayOnClose;
    try {
      await windowManager.setPreventClose(shouldPreventClose);
    } catch (_) {}

    // Handle tray icon visibility + localized menu.
    final newLocaleKey = l10n.localeName;
    final localeChanged = newLocaleKey != _localeKey;
    _localeKey = newLocaleKey;

    if (_showTraySetting) {
      if (!_trayVisible || localeChanged) {
        await _ensureTrayIconAndMenu(l10n);
        _trayVisible = true;
      }
    } else {
      if (_trayVisible) {
        try {
          await trayManager.destroy();
        } catch (_) {}
        _trayVisible = false;
      }
    }
  }

  Future<void> _ensureTrayIconAndMenu(AppLocalizations l10n) async {
    if (!_isDesktop) return;

    // Use platform-specific tray icons (mirrors Gopeed's approach):
    // - Windows: multi-size ICO for crisp scaling
    // - macOS: template PNG so the system can adapt to light/dark menu bar
    // - Linux/others: regular PNG asset
    final platform = defaultTargetPlatform;
    try {
      if (platform == TargetPlatform.windows) {
        await trayManager.setIcon('assets/app_icon.ico');
      } else if (platform == TargetPlatform.macOS) {
        await trayManager.setIcon('assets/icon_mac.png', isTemplate: true);
      } else {
        await trayManager.setIcon('assets/icons/orvia.png');
      }
    } catch (_) {}

    // Some Linux environments do not support tooltip; keep the call
    // consistent with Gopeed and skip it there.
    if (platform != TargetPlatform.linux) {
      try {
        await trayManager.setToolTip('Orvia');
      } catch (_) {}
    }
    try {
      final menu = Menu(
        items: [
          MenuItem(
            label: l10n.desktopTrayMenuShowWindow,
            onClick: (_) async => _showWindow(),
          ),
          MenuItem.separator(),
          MenuItem(
            label: l10n.desktopTrayMenuExit,
            onClick: (_) async => _exitApp(),
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (_) {}
  }

  Future<void> _showWindow() async {
    if (!_isDesktop) return;
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  Future<void> _exitApp() async {
    if (!_isDesktop) return;
    try {
      // Drain pending writes before exiting. On macOS/Linux destroy()
      // routes through the engine's exit-request channel (which flushes
      // again — flush handlers are idempotent), but on Windows the
      // destroy() fallback posts WM_QUIT directly and bypasses WM_CLOSE,
      // so without this the fallback exit would skip the flush entirely.
      // The timeout keeps a stuck write queue from hanging tray exit.
      try {
        await AppExitFlush.flushAll().timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      } catch (_) {}
      // On Windows we may have `preventClose` enabled to support
      // "close to tray". Temporarily disable it and send a normal
      // close so the window can exit immediately without being
      // intercepted by the minimize‑to‑tray logic.
      if (defaultTargetPlatform == TargetPlatform.windows) {
        try {
          await windowManager.setPreventClose(false);
        } catch (_) {}
        try {
          await windowManager.close();
          return;
        } catch (_) {}
      }

      // Other desktop platforms (and Windows fallback): destroy the
      // window so the process exits cleanly.
      await windowManager.destroy();
    } catch (_) {}
  }

  // ===== TrayListener =====

  @override
  void onTrayIconMouseDown() {
    // Left‑click: bring main window to front.
    if (!_isDesktop) return;
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() async {
    // Right‑click: \u5F39\u51FA\u6258\u76D8\u83DC\u5355。
    // \u4F7F\u7528\u5185\u90E8\u6807\u8BB0\u9632\u6B62\u5728\u4E00\u6B21\u4EA4\u4E92\u5468\u671F\u5185\u91CD\u590D\u5F39\u51FA，
    // \u5426\u5219\u5728\u67D0\u4E9B Windows \u73AF\u5883\u4E0B\u4F1A\u770B\u5230\u7B2C\u4E8C\u4E2A\u504F\u79FB\u7684\u83DC\u5355。
    if (_contextMenuOpen) {
      return;
    }
    _contextMenuOpen = true;
    try {
      // Windows \u73AF\u5883\u4E0B\u5EFA\u8BAE\u5728\u5F39\u51FA\u83DC\u5355\u524D\u5C1D\u8BD5\u805A\u7126\u7A97\u53E3，
      // \u4EE5\u907F\u514D\u90E8\u5206\u73AF\u5883\u4E2D\u83DC\u5355\u4E0D\u4F1A\u5728\u70B9\u51FB\u5176\u4ED6\u5730\u65B9\u65F6\u81EA\u52A8\u5173\u95ED。
      if (defaultTargetPlatform == TargetPlatform.windows) {
        try {
          await windowManager.focus();
        } catch (_) {}
      }
      await trayManager.popUpContextMenu();
    } catch (_) {}
    // \u65E0\u8BBA\u662F\u70B9\u51FB\u83DC\u5355\u9879\u8FD8\u662F\u70B9\u51FB\u5176\u4ED6\u5730\u65B9\u5173\u95ED\u83DC\u5355，
    // popUpContextMenu \u90FD\u4F1A\u5728\u83DC\u5355\u5173\u95ED\u540E\u8FD4\u56DE，\u8FD9\u91CC\u7EDF\u4E00\u91CD\u7F6E\u6807\u8BB0。
    _contextMenuOpen = false;
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    // \u4EFB\u4E00\u83DC\u5355\u9879\u88AB\u70B9\u51FB\u89C6\u4E3A\u4E00\u6B21\u83DC\u5355\u4EA4\u4E92\u7ED3\u675F，
    // \u989D\u5916\u4FDD\u9669\u5730\u89E3\u9664\u9632\u6296\u6807\u8BB0（\u5373\u4F7F Future \u5C1A\u672A\u5B8C\u6210）。
    _contextMenuOpen = false;
  }

  // ===== WindowListener =====

  @override
  void onWindowClose() async {
    if (!_isDesktop) return;
    // Only intercept close when user enabled minimize-to-tray.
    final shouldIntercept = _showTraySetting && _minimizeToTrayOnClose;
    if (!shouldIntercept) return;
    try {
      final isPreventClose = await windowManager.isPreventClose();
      if (!isPreventClose) return;
      await windowManager.hide();
    } catch (_) {}
  }
}
