import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/utils/stats_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// These run in whatever zone the machine is in. To exercise the
/// daylight-saving paths run with e.g. `TZ=America/New_York flutter test`.
void main() {
  group('calendar day helpers', () {
    test('addCalendarDays always lands on local midnight', () {
      // Spans both US and EU clock changes in either direction.
      var day = DateTime(2025, 2, 20);
      for (var i = 0; i < 300; i++) {
        final next = addCalendarDays(day, 1);
        expect(next.hour, 0, reason: 'after $day');
        expect(calendarDaysBetween(day, next), 1);
        day = next;
      }
      expect(day, DateTime(2025, 12, 17));
    });

    test('calendarDaysBetween counts dates, not hours', () {
      expect(
        calendarDaysBetween(DateTime(2025, 3, 1), DateTime(2025, 4, 1)),
        31,
      );
      expect(
        calendarDaysBetween(DateTime(2025, 10, 20), DateTime(2025, 11, 10)),
        21,
      );
    });
  });

  test('a session today still moves the score after the clocks go forward', () {
    SharedPreferences.setMockInitialValues({});
    final manager = StatsManager();
    final today = DateTime(2025, 8, 10, 9);
    manager.setCurrentDateForTesting(today);

    // Daily practice from January to the end of April, then nothing: the
    // day-by-day walk crosses the spring clock change before reaching today.
    final sessions = <LocalAudioCompleted>[];
    var day = DateTime(2025, 1, 1, 8);
    var id = 0;
    while (day.isBefore(DateTime(2025, 5, 1))) {
      sessions.add(
        LocalAudioCompleted(
          id: '${id++}',
          timestamp: day.millisecondsSinceEpoch,
        ),
      );
      day = DateTime(day.year, day.month, day.day + 1, 8);
    }

    LocalAllStats stats(List<LocalAudioCompleted> audio) => LocalAllStats(
      tracksChecked: [],
      audioCompleted: audio,
      streakCurrent: 0,
      streakLongest: 0,
      totalTracksCompleted: audio.length,
      totalTimeListened: 0,
      freezeUsageDates: [],
      updated: 0,
    );

    final without = manager.calculateConsistencyScore(stats(sessions));
    final withToday = manager.calculateConsistencyScore(
      stats([
        ...sessions,
        LocalAudioCompleted(
          id: 'today',
          timestamp: today.millisecondsSinceEpoch,
        ),
      ]),
    );

    expect(withToday, greaterThan(without));
  });
}
