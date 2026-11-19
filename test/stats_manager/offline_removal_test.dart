import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/utils/stats_manager.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../stats_manager_test.mocks.dart';

/// A delete or edit made while the upload fails must survive the next sync.
/// The merge is a union of local and server sessions, so the server copy,
/// which still holds the old entry, used to bring it straight back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 5, 10, 12);
  final keep = LocalAudioCompleted(
    id: 'keep',
    timestamp: DateTime(2026, 5, 9, 8).millisecondsSinceEpoch,
  );
  final gone = LocalAudioCompleted(
    id: 'gone',
    timestamp: DateTime(2026, 5, 10, 8).millisecondsSinceEpoch,
  );

  late StatsManager manager;
  late MockStatsService service;
  late LocalAllStats serverCopy;
  var online = false;

  LocalAllStats history(List<LocalAudioCompleted> sessions) =>
      LocalAllStats.empty().copyWith(
        audioCompleted: sessions,
        totalTracksCompleted: sessions.length,
        totalTimeListened: 600000 * sessions.length,
        updated: now.millisecondsSinceEpoch,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    online = false;
    serverCopy = history([keep, gone]);
    service = MockStatsService();
    manager = StatsManager();
    await manager.initializeForTesting(statsService: service);
    manager.setCurrentDateForTesting(now);
    manager.setStatsForTesting(history([keep, gone]));

    when(service.fetchAllStats()).thenAnswer((_) async => serverCopy);
    when(service.postStats(any, force: anyNamed('force'))).thenAnswer((
      invocation,
    ) async {
      if (!online) throw Exception('offline');
      serverCopy = invocation.positionalArguments.first as LocalAllStats;
    });
  });

  tearDown(() => manager.resetForTesting());

  List<String> ids() =>
      manager.currentStats!.audioCompleted!.map((s) => s.id).toList();

  test('a session deleted offline stays deleted after the next sync', () async {
    await manager.removeAudioCompleted(gone);
    expect(ids(), ['keep']);

    online = true;
    await manager.sync(force: true);

    expect(ids(), ['keep']);
    expect(manager.currentStats!.totalTracksCompleted, 1);
    expect(serverCopy.audioCompleted!.map((s) => s.id), ['keep']);
  });

  test('the pending delete survives an app restart', () async {
    await manager.removeAudioCompleted(gone);

    // New process: in-memory state is gone, the saved history remains.
    manager.resetForTesting();
    manager = StatsManager();
    await manager.initializeForTesting(statsService: service);
    manager.setCurrentDateForTesting(now);
    manager.setStatsForTesting(history([keep]));

    online = true;
    await manager.sync(force: true);

    expect(ids(), ['keep']);
  });

  test('a session moved offline does not leave its old entry behind', () async {
    final moved = gone.copyWith(
      timestamp: DateTime(2026, 5, 8, 8).millisecondsSinceEpoch,
    );
    expect(
      await manager.replaceAudioCompleted(original: gone, replacement: moved),
      isTrue,
    );

    online = true;
    await manager.sync(force: true);

    expect(manager.currentStats!.audioCompleted, hasLength(2));
    expect(
      manager.currentStats!.audioCompleted!.map((s) => s.timestamp),
      containsAll([keep.timestamp, moved.timestamp]),
    );
    expect(manager.currentStats!.totalTracksCompleted, 2);
  });

  test('once the server has the delete, a later copy of it is trusted', () async {
    online = true;
    await manager.removeAudioCompleted(gone);
    expect(serverCopy.audioCompleted!.map((s) => s.id), ['keep']);

    // Another device records the same track at the same moment again: with
    // the removal confirmed, nothing filters it out any more.
    serverCopy = history([keep, gone]);
    await manager.sync(force: true);

    expect(ids(), containsAll(['keep', 'gone']));
  });
}
