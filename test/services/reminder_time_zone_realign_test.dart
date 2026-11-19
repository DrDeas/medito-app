import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/notification/reminder_provider.dart';
import 'package:medito/services/notifications/notification_timing.dart';
import 'package:medito/services/reminders/daily_reminders_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

class _Reminders extends Mock implements ReminderProvider {}

/// A payload as the series writes it, but planned in a zone [offsetMinutes]
/// from UTC, for the wall-clock time [wall] (read as fields, zone ignored).
String _payloadPlannedIn(int offsetMinutes, DateTime wall, {int day = 3}) {
  final instant = DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
  ).subtract(Duration(minutes: offsetMinutes));
  return '{"source":"local_reminder","notification_day":$day,'
      '"scheduled_at":${instant.millisecondsSinceEpoch ~/ 1000},'
      '"scheduled_utc_offset_min":$offsetMinutes}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();

  final now = DateTime(2026, 6, 1, 12);
  final sevenTomorrow = DateTime(2026, 6, 2, 7);
  // A zone the test machine is certainly not in at that moment.
  final elsewhere = sevenTomorrow.timeZoneOffset.inMinutes + 8 * 60;

  late _Reminders reminders;
  late SharedPreferences prefs;

  setUpAll(() => registerFallbackValue(<ScheduledReminder>[]));

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      SharedPreferenceConstants.dailyReminderEnabled: true,
    });
    prefs = await SharedPreferences.getInstance();
    reminders = _Reminders();
    when(() => reminders.scheduleReminderSeries(any()))
        .thenAnswer((_) async {});
  });

  DailyRemindersScheduler scheduler() => DailyRemindersScheduler(
    prefs: prefs,
    reminders: reminders,
    now: () => now,
  );

  void pending(List<PendingNotificationRequest> requests) =>
      when(() => reminders.getPendingNotifications())
          .thenAnswer((_) async => requests);

  test('plannedWallClockInCurrentZone recovers the clock time meant', () {
    final data = NotificationTiming.decode(
      _payloadPlannedIn(elsewhere, sevenTomorrow),
    );
    expect(plannedWallClockInCurrentZone(data), sevenTomorrow);
    expect(plannedWallClockInCurrentZone({}), isNull);
  });

  test('a reminder planned in another zone moves to 07:00 here', () async {
    pending([
      PendingNotificationRequest(
        reminderSeriesBaseId + 2,
        'Title',
        'Body',
        _payloadPlannedIn(elsewhere, sevenTomorrow),
      ),
    ]);

    expect(await scheduler().realignToCurrentTimeZone(), 1);

    final moved =
        verify(() => reminders.scheduleReminderSeries(captureAny()))
                .captured
                .single
            as List<ScheduledReminder>;
    expect(moved.single.id, reminderSeriesBaseId + 2);
    expect(moved.single.title, 'Title');
    expect(moved.single.body, 'Body');
    expect(
      moved.single.scheduledDate.millisecondsSinceEpoch,
      sevenTomorrow.millisecondsSinceEpoch,
    );
    final data = NotificationTiming.decode(moved.single.payload);
    expect(data['notification_day'], 3);
    expect(data['scheduled_local_hour'], 7);
  });

  test('nothing is rescheduled when the zone has not changed', () async {
    pending([
      PendingNotificationRequest(
        reminderSeriesBaseId,
        'Title',
        'Body',
        _payloadPlannedIn(
          sevenTomorrow.timeZoneOffset.inMinutes,
          sevenTomorrow,
        ),
      ),
    ]);

    expect(await scheduler().realignToCurrentTimeZone(), 0);
    verifyNever(() => reminders.scheduleReminderSeries(any()));
  });

  test('other notifications and past reminders are left alone', () async {
    pending([
      PendingNotificationRequest(
        42,
        'Campaign',
        'Body',
        _payloadPlannedIn(elsewhere, sevenTomorrow),
      ),
      PendingNotificationRequest(
        reminderSeriesBaseId + 1,
        'Title',
        'Body',
        _payloadPlannedIn(elsewhere, DateTime(2026, 6, 1, 7)),
      ),
    ]);

    expect(await scheduler().realignToCurrentTimeZone(), 0);
  });

  test('does nothing while reminders are off', () async {
    await prefs.setBool(SharedPreferenceConstants.dailyReminderEnabled, false);
    expect(await scheduler().realignToCurrentTimeZone(), 0);
    verifyNever(() => reminders.getPendingNotifications());
  });
}
