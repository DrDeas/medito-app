import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/player/ios_audio_handler.dart'
    show clampSeekPosition;
import 'package:medito/views/player/widgets/player_buttons/play_pause_button_widget.dart';

Future<void> _mount(
  WidgetTester tester, {
  required bool isLoading,
  required bool isRebuffering,
  required VoidCallback onPlayPause,
}) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: PlayPauseButtonWidget(
              isPlaying: true,
              isLoading: isLoading,
              isRebuffering: isRebuffering,
              onPlayPause: onPlayPause,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('initial load shows a spinner that ignores taps', (tester) async {
    var taps = 0;
    await _mount(
      tester,
      isLoading: true,
      isRebuffering: false,
      onPlayPause: () => taps++,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(PlayPauseButtonWidget), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('a mid-session stall keeps the button usable', (tester) async {
    var taps = 0;
    await _mount(
      tester,
      isLoading: true,
      isRebuffering: true,
      onPlayPause: () => taps++,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(PlayPauseButtonWidget));
    expect(taps, 1);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
  });

  group('clampSeekPosition', () {
    const length = Duration(minutes: 10);

    test('never seeks before the start', () {
      expect(
        clampSeekPosition(const Duration(seconds: -7), length),
        Duration.zero,
      );
    });

    test('never seeks past the end', () {
      expect(clampSeekPosition(const Duration(minutes: 11), length), length);
    });

    test('leaves an in-range position alone', () {
      const target = Duration(minutes: 4);
      expect(clampSeekPosition(target, length), target);
      expect(clampSeekPosition(target, null), target);
    });
  });
}
