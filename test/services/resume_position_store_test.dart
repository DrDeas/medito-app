import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/audio/resume_position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const twentyMinutes = 20 * 60 * 1000;
  var now = DateTime(2026, 6, 1, 9);
  late ResumePositionStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 6, 1, 9);
    store = ResumePositionStore(
      await SharedPreferences.getInstance(),
      now: () => now,
    );
  });

  test('a position part-way through a long session is kept', () async {
    await store.save('file', positionMs: 400000, durationMs: twentyMinutes);
    expect(store.positionFor('file', durationMs: twentyMinutes), 400000);
  });

  test('positions are per audio file', () async {
    await store.save('long', positionMs: 400000, durationMs: twentyMinutes);
    expect(store.positionFor('short', durationMs: twentyMinutes), isNull);
  });

  test('short sessions are not resumed', () async {
    const threeMinutes = 3 * 60 * 1000;
    await store.save('file', positionMs: 90000, durationMs: threeMinutes);
    expect(store.positionFor('file', durationMs: threeMinutes), isNull);
  });

  test('the first and last half minute are not resumed', () async {
    await store.save('file', positionMs: 20000, durationMs: twentyMinutes);
    expect(store.positionFor('file', durationMs: twentyMinutes), isNull);

    await store.save(
      'file',
      positionMs: twentyMinutes - 10000,
      durationMs: twentyMinutes,
    );
    expect(store.positionFor('file', durationMs: twentyMinutes), isNull);
  });

  test('saving an unresumable position forgets an earlier one', () async {
    await store.save('file', positionMs: 400000, durationMs: twentyMinutes);
    await store.save('file', positionMs: 1000, durationMs: twentyMinutes);
    expect(store.positionFor('file', durationMs: twentyMinutes), isNull);
  });

  test('a position older than a week is ignored', () async {
    await store.save('file', positionMs: 400000, durationMs: twentyMinutes);
    now = now.add(const Duration(days: 8));
    expect(store.positionFor('file', durationMs: twentyMinutes), isNull);
  });

  test('a position past the end of a replaced recording is ignored', () async {
    await store.save('file', positionMs: 900000, durationMs: twentyMinutes);
    expect(store.positionFor('file', durationMs: 10 * 60 * 1000), isNull);
  });

  test('clear forgets the position', () async {
    await store.save('file', positionMs: 400000, durationMs: twentyMinutes);
    await store.clear('file');
    expect(store.positionFor('file', durationMs: twentyMinutes), isNull);
  });

  test('corrupt data reads as nothing saved', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('resume_position_file', 'not json');
    expect(store.positionFor('file', durationMs: twentyMinutes), isNull);
  });
}
