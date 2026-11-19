import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/events/donation/donation_page_model.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/me/me_model.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/stripe/paywall_config_model.dart';
import 'package:medito/providers/background_sounds/background_sounds_notifier.dart';
import 'package:medito/providers/donation/donation_page_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/providers/stripe/payment_service_provider.dart';
import 'package:medito/src/audio_pigeon.g.dart';
import 'package:medito/views/home/previews/home_previews.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/previews/preview_support.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/firebase_analytics_test_helper.dart';
import '../../helpers/firebase_test_helper.dart';

const _twentyMinutes = 20 * 60 * 1000;

const _session = PlaybackRequest(
  trackId: 'long-sit',
  fileId: 'long-sit-file',
  title: 'Long sit',
  description: '',
  coverUrl: '',
  remoteUrl: 'https://example.test/long.mp3',
  duration: _twentyMinutes,
  hasBackgroundSound: false,
  guideName: 'Will',
);

PlaybackState _playingAt(int positionMs) => PlaybackState(
  isPlaying: true,
  isBuffering: false,
  isSeeking: false,
  isCompleted: false,
  position: positionMs,
  duration: _twentyMinutes,
  speed: Speed(speed: 1),
  volume: 100,
  track: Track(
    id: 'long-sit',
    title: '',
    fileId: '',
    description: '',
    imageUrl: '',
    artist: '',
  ),
);

class _FakePlayer extends PlayerProvider {
  _FakePlayer(this.seeks);

  /// Shared with the test: the provider may build more than one notifier.
  final List<int> seeks;

  @override
  PlaybackRequest? build() => _session;

  @override
  Future<void> play(PlaybackRequest request) async {}

  @override
  Future<void> seekToPosition(int position) async => seeks.add(position);

  @override
  Future<void> stop() async {}

  @override
  void setSpeed(double speed) {}
}

class _SilentBackgroundSounds extends BackgroundSoundsNotifier {
  @override
  void stopBackgroundSound() {}

  @override
  void playBackgroundSoundFromPref() {}
}

class _Stats extends StatsNotifier {
  @override
  Future<LocalAllStats> build() async => previewStats;
}

String _saved(int positionMs) => jsonEncode({
  'positionMs': positionMs,
  'durationMs': _twentyMinutes,
  'savedAtMs': DateTime.now().millisecondsSinceEpoch,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async => 0,
    );
    await FirebaseTestHelper.initializeFirebaseForTest();
    FirebaseAnalyticsTestHelper.setupFirebaseAnalyticsMocks();
  });

  Future<(List<int>, ProviderContainer)> open(
    WidgetTester tester,
    Map<String, Object> prefs,
  ) async {
    final seeks = <int>[];
    // A fresh ProviderScope per test: the overrides hold per-test instances.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      PreviewShell(
        prefs: {...prefsDark, ...prefs},
        overrides: [
          playerProvider.overrideWith(() => _FakePlayer(seeks)),
          // The app shares one global notifier; each test needs its own.
          audioStateProvider.overrideWith(AudioStateNotifier.new),
          backgroundSoundsNotifierProvider.overrideWith(
            _SilentBackgroundSounds.new,
          ),
          statsProvider.overrideWith(_Stats.new),
          endScreenPaywallConfigProvider.overrideWith(
            (ref) => Completer<PaywallConfigModel>().future,
          ),
          meProvider.overrideWith(
            (ref) async => const MeModel(id: 'test-user'),
          ),
          fetchDonationPageProvider.overrideWith(
            (ref) async => const DonationPageModel(buttons: [ButtonModel()]),
          ),
        ],
        child: const PlayerView(),
      ),
    );
    await tester.pump();
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlayerView)),
    );
    return (seeks, container);
  }

  testWidgets('a session left part-way resumes from the saved position', (
    tester,
  ) async {
    final (seeks, _) = await open(tester, {
      'resume_position_long-sit-file': _saved(400000),
    });

    expect(seeks, [400000]);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('with nothing saved the session starts at the beginning', (
    tester,
  ) async {
    final (seeks, _) = await open(tester, {});

    expect(seeks, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('progress is saved as the session plays', (tester) async {
    final (_, container) = await open(tester, {});
    final audio = container.read(audioStateProvider.notifier);
    final prefs = container.read(sharedPreferencesProvider);

    audio.updatePlaybackState(_playingAt(5000));
    await tester.pump();
    expect(
      prefs.getString('resume_position_long-sit-file'),
      isNull,
      reason: 'the opening half minute is not worth resuming',
    );

    audio.updatePlaybackState(_playingAt(95000));
    await tester.pump();
    final saved = jsonDecode(
      prefs.getString('resume_position_long-sit-file')!,
    ) as Map<String, dynamic>;
    expect(saved['positionMs'], 95000);
    await tester.pump(const Duration(seconds: 5));
  });
}
