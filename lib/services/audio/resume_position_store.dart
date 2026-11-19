import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers how far into a long session someone got, so closing the player
/// (or losing the app) part-way through a 30-minute sit does not mean
/// starting again from the beginning.
///
/// One entry per audio file, so a different voice or length of the same
/// track never inherits a position that does not fit it.
class ResumePositionStore {
  ResumePositionStore(this._prefs, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  static const _keyPrefix = 'resume_position_';

  /// Shorter sessions are simply replayed.
  static const minDuration = Duration(minutes: 5);

  /// Too close to either end to be worth resuming: the opening can be heard
  /// again, and a session abandoned in its last moments is as good as done.
  static const edge = Duration(seconds: 30);

  /// After this long, picking up mid-sentence is no longer helpful.
  static const maxAge = Duration(days: 7);

  static String _key(String fileId) => '$_keyPrefix$fileId';

  /// Whether [positionMs] into a session of [durationMs] is worth keeping.
  static bool isResumable({required int positionMs, required int durationMs}) =>
      durationMs >= minDuration.inMilliseconds &&
      positionMs >= edge.inMilliseconds &&
      durationMs - positionMs >= edge.inMilliseconds;

  /// Saves the position, or forgets the file when the position is not worth
  /// resuming (see [isResumable]).
  Future<void> save(
    String fileId, {
    required int positionMs,
    required int durationMs,
  }) async {
    if (!isResumable(positionMs: positionMs, durationMs: durationMs)) {
      await clear(fileId);
      return;
    }
    await _prefs.setString(
      _key(fileId),
      jsonEncode({
        'positionMs': positionMs,
        'durationMs': durationMs,
        'savedAtMs': _now().millisecondsSinceEpoch,
      }),
    );
  }

  /// The position to resume [fileId] from, or null. [durationMs] is the
  /// length of the file about to play: a saved position that no longer fits
  /// it (the recording was replaced) is dropped.
  int? positionFor(String fileId, {required int durationMs}) {
    final raw = _prefs.getString(_key(fileId));
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final positionMs = data['positionMs'] as int;
      final savedAt = DateTime.fromMillisecondsSinceEpoch(
        data['savedAtMs'] as int,
      );
      if (_now().difference(savedAt) > maxAge) return null;
      if (!isResumable(positionMs: positionMs, durationMs: durationMs)) {
        return null;
      }
      return positionMs;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear(String fileId) async {
    if (_prefs.containsKey(_key(fileId))) await _prefs.remove(_key(fileId));
  }
}
