import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/donation/donation_snooze_provider.dart';
import 'package:medito/providers/donation/supporter_appeal_experiment.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  Future<ProviderContainer> container([
    Map<String, Object> initial = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  int? snoozedUntil() =>
      prefs.getInt(SharedPreferenceConstants.donationAskSnoozedUntilMs);

  test('asks are on by default', () async {
    final c = await container();
    final state = c.read(donationSnoozeProvider);
    expect(state.isMuted, isFalse);
    expect(state.isSnoozed, isFalse);
  });

  test('muting suppresses asks with no end date', () async {
    final c = await container();
    await c.read(donationSnoozeProvider.notifier).setMuted(true);

    final state = c.read(donationSnoozeProvider);
    expect(state.isMuted, isTrue);
    expect(state.isSnoozed, isTrue);
    expect(
      snoozedUntil(),
      DonationSnooze.mutedUntil.millisecondsSinceEpoch,
      reason: 'the server schedules campaign pushes from this date',
    );
    // The Home appeal reads prefs directly; it must agree, far in the future.
    expect(SupporterAppealExperiment(prefs).isSnoozed(DateTime(2090)), isTrue);
  });

  test('the mute survives a restart', () async {
    final c = await container({
      SharedPreferenceConstants.donationAsksMuted: true,
    });
    expect(c.read(donationSnoozeProvider).isSnoozed, isTrue);
  });

  test('a timed snooze or a donation does not shorten a mute', () async {
    final c = await container();
    final notifier = c.read(donationSnoozeProvider.notifier);
    await notifier.setMuted(true);

    await notifier.snoozeForDays(30);
    expect(snoozedUntil(), DonationSnooze.mutedUntil.millisecondsSinceEpoch);

    await c
        .read(donationSnoozeProvider.notifier)
        .recordDonationSuccess('onetime');
    expect(snoozedUntil(), DonationSnooze.mutedUntil.millisecondsSinceEpoch);
    expect(c.read(donationSnoozeProvider).isMuted, isTrue);
  });

  test('turning asks back on clears the snooze', () async {
    final c = await container();
    final notifier = c.read(donationSnoozeProvider.notifier);
    await notifier.setMuted(true);
    await c.read(donationSnoozeProvider.notifier).setMuted(false);

    final state = c.read(donationSnoozeProvider);
    expect(state.isMuted, isFalse);
    expect(state.isSnoozed, isFalse);
    expect(snoozedUntil(), isNull);
  });
}
