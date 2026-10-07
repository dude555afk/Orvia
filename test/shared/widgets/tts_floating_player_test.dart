import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/services/tts/tts_playback_models.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/app_overlays.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart' as lucide;
import 'package:provider/provider.dart';

class _FakeTtsProvider extends ChangeNotifier implements TtsProvider {
  _FakeTtsProvider({TtsPlaybackState? state, this.canSaveNetworkAudio = false})
    : _state =
          state ??
          const TtsPlaybackState(
            status: TtsPlaybackStatus.paused,
            position: Duration(seconds: 20),
            duration: Duration(minutes: 2),
            speed: 1.2,
            currentChunkIndex: 1,
            totalChunks: 3,
          );

  int rewindCount = 0;
  int playPauseCount = 0;
  int forwardCount = 0;
  int speedCount = 0;
  int stopCount = 0;
  final TtsPlaybackState _state;

  @override
  final bool canSaveNetworkAudio;

  @override
  TtsPlaybackState get playbackState => _state;

  @override
  Future<void> seekBackward() async {
    rewindCount++;
  }

  @override
  Future<void> togglePause() async {
    playPauseCount++;
  }

  @override
  Future<void> seekForward() async {
    forwardCount++;
  }

  @override
  Future<void> cyclePlaybackSpeed() async {
    speedCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('AppOverlays gives the active TTS floating player an Overlay', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.25;
    tester.view.physicalSize = const Size(325, 750);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final tts = _FakeTtsProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<TtsProvider>.value(
        value: tts,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) {
            return AppOverlays(child: child ?? const SizedBox.shrink());
          },
          home: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Resume'), findsOneWidget);
    expect(find.byTooltip('Close player'), findsOneWidget);
    expect(find.byTooltip('Expand playback controls'), findsOneWidget);
    expect(find.byTooltip('Back 15 seconds'), findsNothing);
    expect(find.byTooltip('Forward 15 seconds'), findsNothing);
    expect(find.byTooltip('Playback speed'), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.byIcon(lucide.LucideIcons.grip), findsNothing);
    expect(
      find.byKey(const ValueKey('ttsCircularProgressButton')),
      findsOneWidget,
    );

    expect(find.bySemanticsLabel('TTS player'), findsOneWidget);
    final player = find.byKey(const ValueKey('ttsFloatingPlayerSurface'));
    showAppSnackBar(
      tester.element(player),
      message: 'Saved',
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final beforeDrag = tester.getTopLeft(player);
    await tester.drag(player, const Offset(-18, 24));
    await tester.pump();
    final afterDrag = tester.getTopLeft(player);

    expect(afterDrag.dx, beforeDrag.dx);
    expect(afterDrag.dy, greaterThan(beforeDrag.dy));

    await tester.tap(find.byTooltip('Expand playback controls'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Collapse playback controls'), findsOneWidget);
    expect(find.byTooltip('Back 15 seconds'), findsOneWidget);
    expect(find.byTooltip('Forward 15 seconds'), findsOneWidget);
    expect(find.byTooltip('Playback speed'), findsOneWidget);
    final expandedWidth = tester.getSize(player).width;

    await tester.tap(find.byTooltip('Back 15 seconds'));
    await tester.tap(find.byTooltip('Resume'));
    await tester.tap(find.byTooltip('Forward 15 seconds'));
    await tester.tap(find.byTooltip('Playback speed'));

    await tester.tap(find.byTooltip('Collapse playback controls'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.takeException(), isNull);
    final midCollapseWidth = tester.getSize(player).width;
    expect(midCollapseWidth, lessThan(expandedWidth));
    expect(midCollapseWidth, greaterThan(120));
    await tester.pump(const Duration(milliseconds: 170));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final collapsedWidth = tester.getSize(player).width;
    expect(collapsedWidth, lessThan(midCollapseWidth));

    expect(find.byTooltip('Expand playback controls'), findsOneWidget);
    expect(find.byTooltip('Back 15 seconds'), findsNothing);
    expect(find.byTooltip('Forward 15 seconds'), findsNothing);
    expect(find.byTooltip('Playback speed'), findsNothing);

    await tester.tap(find.byTooltip('Close player'));

    expect(tts.rewindCount, 1);
    expect(tts.playPauseCount, 1);
    expect(tts.forwardCount, 1);
    expect(tts.speedCount, 1);
    expect(tts.stopCount, 1);
  });

  testWidgets('ended TTS player stays visible and exposes replay', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.25;
    tester.view.physicalSize = const Size(325, 750);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final tts = _FakeTtsProvider(
      canSaveNetworkAudio: true,
      state: const TtsPlaybackState(
        status: TtsPlaybackStatus.ended,
        position: Duration(minutes: 2),
        duration: Duration(minutes: 2),
        speed: 1.0,
        currentChunkIndex: 3,
        totalChunks: 3,
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<TtsProvider>.value(
        value: tts,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) {
            return AppOverlays(child: child ?? const SizedBox.shrink());
          },
          home: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('TTS player'), findsOneWidget);
    expect(find.byTooltip('Replay'), findsOneWidget);

    await tester.tap(find.byTooltip('Expand playback controls'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Save audio'), findsOneWidget);

    await tester.tap(find.byTooltip('Replay'));

    expect(tts.playPauseCount, 1);
  });
}
