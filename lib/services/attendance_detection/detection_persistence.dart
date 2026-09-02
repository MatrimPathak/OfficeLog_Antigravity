import 'package:hive/hive.dart';

import 'detection_state_machine.dart';

/// Persists [DetectionEngineState] across OS-delivered wake-ups and process
/// restarts. Uses a dedicated Hive box, consistent with the existing
/// `attendance_logs`/`app_logs` boxes elsewhere in this codebase — see
/// docs/AUTO_ATTENDANCE_DESIGN.md section 7.
///
/// Keyed by userId so a shared device (or account switch) can't leak one
/// user's in-progress episode into another's evaluation.
class DetectionPersistence {
  static const String _boxName = 'attendance_detection_state';

  Future<DetectionEngineState> load(String userId) async {
    try {
      final box = await Hive.openBox<Map>(_boxName);
      final raw = box.get(userId);
      if (raw == null) return DetectionEngineState.initial;
      return DetectionEngineState.fromMap(Map<String, dynamic>.from(raw));
    } catch (_) {
      // Corrupt/unreadable persisted state must never crash detection —
      // fall back to a fresh episode.
      return DetectionEngineState.initial;
    }
  }

  Future<void> save(String userId, DetectionEngineState state) async {
    try {
      final box = await Hive.openBox<Map>(_boxName);
      await box.put(userId, state.toMap());
    } catch (_) {
      // Best-effort: losing one persisted update just means the next
      // observation starts from a slightly stale state, which the state
      // machine is designed to tolerate (see docs section 7).
    }
  }

  Future<void> clear(String userId) async {
    try {
      final box = await Hive.openBox<Map>(_boxName);
      await box.delete(userId);
    } catch (_) {}
  }
}
