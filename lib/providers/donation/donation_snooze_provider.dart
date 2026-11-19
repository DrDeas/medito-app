import 'dart:async';

import 'package:medito/services/notifications/supporter_campaign_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/notifications/local_notifications.dart';
import 'supporter_appeal_experiment.dart';

import '../../constants/strings/shared_preference_constants.dart';
import '../shared_preference/shared_preference_provider.dart';

part 'donation_snooze_provider.g.dart';

class DonationSnoozeState {
  final bool isSnoozed;
  final String? lastDonationFrequency;
  final DateTime? lastDonationAt;
  final DateTime? snoozedUntil;

  /// The user switched donation asks off in Settings. Unlike a timed snooze
  /// this never lapses, and it hides the thank-you card as well.
  final bool isMuted;

  DonationSnoozeState({
    required this.isSnoozed,
    this.isMuted = false,
    this.lastDonationFrequency,
    this.lastDonationAt,
    this.snoozedUntil,
  });

  /// True when this install has ever completed a donation in-app. The
  /// thank-you card is shown for both donors and "Hide for now" snoozers;
  /// analytics use this to tell the two apart.
  bool get isDonor => lastDonationAt != null;

  /// 'donor' | 'hidden' — why the ask is suppressed. Only meaningful while
  /// [isSnoozed] is true.
  String get snoozeReason => isDonor ? 'donor' : 'hidden';
}

@riverpod
class DonationSnooze extends _$DonationSnooze {
  @override
  DonationSnoozeState build() {
    final prefs = ref.watch(sharedPreferencesProvider);

    final snoozedUntilMs = prefs.getInt(
      SharedPreferenceConstants.donationAskSnoozedUntilMs,
    );
    final lastDonationAtMs = prefs.getInt(
      SharedPreferenceConstants.lastSuccessfulDonationAtMs,
    );
    final lastDonationFrequency = prefs.getString(
      SharedPreferenceConstants.lastSuccessfulDonationFrequency,
    );

    final now = DateTime.now();
    final isMuted =
        prefs.getBool(SharedPreferenceConstants.donationAsksMuted) ?? false;
    final isSnoozed =
        isMuted ||
        (snoozedUntilMs != null && now.millisecondsSinceEpoch < snoozedUntilMs);

    return DonationSnoozeState(
      isSnoozed: isSnoozed,
      isMuted: isMuted,
      lastDonationFrequency: lastDonationFrequency,
      lastDonationAt: lastDonationAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastDonationAtMs)
          : null,
      snoozedUntil: snoozedUntilMs != null
          ? DateTime.fromMillisecondsSinceEpoch(snoozedUntilMs)
          : null,
    );
  }

  /// Far enough ahead to read as "never" everywhere the snooze date is
  /// consulted, including the server's campaign scheduling.
  static final mutedUntil = DateTime.utc(2100);

  /// Turns every donation ask off (or back on). Muting rides on the existing
  /// snooze, so the end-of-session card, the Home appeal and the campaign
  /// pushes the server schedules from `snooze_until` all stop together.
  Future<void> setMuted(bool muted) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(SharedPreferenceConstants.donationAsksMuted, muted);
    if (muted) {
      await prefs.setInt(
        SharedPreferenceConstants.donationAskSnoozedUntilMs,
        mutedUntil.millisecondsSinceEpoch,
      );
      unawaited(
        LocalNotifications.cancelSafely(
          SupporterAppealExperiment.notificationId,
        ),
      );
    } else {
      await prefs.remove(SharedPreferenceConstants.donationAskSnoozedUntilMs);
    }
    if (ref.mounted) ref.invalidateSelf();
    unawaited(SupporterCampaignApi.updatePreferences(prefs));
  }

  /// A timed snooze must not shorten a mute: the date is what the server
  /// schedules campaign pushes from.
  DateTime _keepingMute(SharedPreferences prefs, DateTime until) =>
      (prefs.getBool(SharedPreferenceConstants.donationAsksMuted) ?? false)
      ? mutedUntil
      : until;

  Future<void> snoozeForDays(int days) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final now = DateTime.now();
    final snoozedUntil = _keepingMute(prefs, now.add(Duration(days: days)));

    await prefs.setInt(
      SharedPreferenceConstants.donationAskSnoozedUntilMs,
      snoozedUntil.millisecondsSinceEpoch,
    );

    // Auto-disposed with no listeners during the awaits above? The next read
    // rebuilds from prefs anyway, and riverpod >=3.5 throws on a dead ref.
    if (ref.mounted) ref.invalidateSelf();
    unawaited(SupporterCampaignApi.updatePreferences(prefs));
  }

  Future<void> recordDonationSuccess(String frequency) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final now = DateTime.now();

    final snoozeDays = frequency == 'onetime'
        ? 60
        : frequency == 'yearly'
        ? 365
        : 30; // monthly
    final snoozedUntil = _keepingMute(
      prefs,
      now.add(Duration(days: snoozeDays)),
    );

    await prefs.setInt(
      SharedPreferenceConstants.lastSuccessfulDonationAtMs,
      now.millisecondsSinceEpoch,
    );
    await prefs.setString(
      SharedPreferenceConstants.lastSuccessfulDonationFrequency,
      frequency,
    );
    await prefs.setInt(
      SharedPreferenceConstants.donationAskSnoozedUntilMs,
      snoozedUntil.millisecondsSinceEpoch,
    );

    // Auto-disposed with no listeners during the awaits above? The next read
    // rebuilds from prefs anyway, and riverpod >=3.5 throws on a dead ref.
    if (ref.mounted) ref.invalidateSelf();
    unawaited(SupporterCampaignApi.updatePreferences(prefs));
    await LocalNotifications.cancelSafely(
      SupporterAppealExperiment.notificationId,
    );
  }
}
