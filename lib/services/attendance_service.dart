import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../data/models/attendance_log.dart';

class AttendanceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String userId;

  AttendanceService(this.userId);

  static void initializeSettings() {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  CollectionReference get _attendanceCollection =>
      _firestore.collection('users').doc(userId).collection('attendance');

  Future<void> logAttendance(AttendanceLog log) async {
    // Save to local Hive first (for offline support)
    var box = await Hive.openBox<Map>('attendance_logs');
    await box.put(log.id, log.toMap());

    try {
      // Try syncing to Firestore with a timeout to avoid hanging background tasks
      await _attendanceCollection
          .doc(log.id)
          .set(log.toMap())
          .timeout(const Duration(seconds: 5));

      // Update local status to synced
      var updatedLog = AttendanceLog(
        id: log.id,
        userId: log.userId,
        date: log.date,
        timestamp: log.timestamp,
        isSynced: true,
        method: log.method,
        inTime: log.inTime,
        outTime: log.outTime,
        sessions: log.sessions,
      );
      await box.put(log.id, updatedLog.toMap());
    } catch (e) {
      // log error - suppressed as Hive is source of truth for UI while offline
    }
  }

  Future<void> updateAttendance(AttendanceLog log) async {
    // Update local Hive
    var box = await Hive.openBox<Map>('attendance_logs');
    await box.put(log.id, log.toMap());

    try {
      // Sync to Firestore using merge to avoid NOT_FOUND errors offline
      await _attendanceCollection
          .doc(log.id)
          .set(log.toMap(), SetOptions(merge: true))
          .timeout(const Duration(seconds: 5));

      var updatedLog = AttendanceLog(
        id: log.id,
        userId: log.userId,
        date: log.date,
        timestamp: log.timestamp,
        isSynced: true,
        method: log.method,
        inTime: log.inTime,
        outTime: log.outTime,
        sessions: log.sessions,
      );
      await box.put(log.id, updatedLog.toMap());
    } catch (e) {
      // Log error internally
    }
  }

  Future<void> deleteAttendance(String logId) async {
    // Delete from local Hive
    var box = await Hive.openBox<Map>('attendance_logs');
    await box.delete(logId);

    try {
      // Delete from Firestore
      await _attendanceCollection
          .doc(logId)
          .delete()
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      // log error
    }
  }

  /// Fetch attendance logs for a specific day using a one-time get().
  /// This is more robust for background tasks than snapshots().
  Future<List<AttendanceLog>> getAttendanceForDate(DateTime date) async {
    try {
      DateTime start = DateTime(date.year, date.month, date.day);
      DateTime end = DateTime(date.year, date.month, date.day, 23, 59, 59);

      // Try fetching from server with a strict timeout, falling back to cache
      final snapshot = await _attendanceCollection
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 5));

      final logs = snapshot.docs.map((doc) {
        return AttendanceLog.fromMap(doc.data() as Map<String, dynamic>);
      }).toList();

      return _deduplicateLogs(logs);
    } catch (e) {
      // Fallback to cache only if server fetch fails or times out
      try {
        final snapshot = await _attendanceCollection
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(
                DateTime(date.year, date.month, date.day),
              ),
            )
            .where(
              'date',
              isLessThanOrEqualTo: Timestamp.fromDate(
                DateTime(date.year, date.month, date.day, 23, 59, 59),
              ),
            )
            .get(const GetOptions(source: Source.cache));

        final logs = snapshot.docs.map((doc) {
          return AttendanceLog.fromMap(doc.data() as Map<String, dynamic>);
        }).toList();

        return _deduplicateLogs(logs);
      } catch (_) {
        return [];
      }
    }
  }

  Stream<List<AttendanceLog>> getAttendanceStream(DateTime month) {
    // Start of month
    DateTime start = DateTime(month.year, month.month, 1);
    // End of month
    DateTime end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    return _attendanceCollection
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots()
        .map((snapshot) {
          final logs = snapshot.docs.map((doc) {
            return AttendanceLog.fromMap(doc.data() as Map<String, dynamic>);
          }).toList();
          return _deduplicateLogs(logs);
        });
  }

  Stream<List<AttendanceLog>> getYearlyAttendanceStream(int year) {
    DateTime start = DateTime(year, 1, 1);
    DateTime end = DateTime(year, 12, 31, 23, 59, 59);

    return _attendanceCollection
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots()
        .map((snapshot) {
          final logs = snapshot.docs.map((doc) {
            return AttendanceLog.fromMap(doc.data() as Map<String, dynamic>);
          }).toList();
          return _deduplicateLogs(logs);
        });
  }

  /// Prioritizes logs with date-based IDs (YYYY-M-D) over legacy timestamp IDs.
  List<AttendanceLog> _deduplicateLogs(List<AttendanceLog> logs) {
    if (logs.isEmpty) return logs;

    final Map<String, AttendanceLog> dateMap = {};

    for (var log in logs) {
      final dateKey =
          "${log.date.year}-${log.date.month}-${log.date.day}";
      final existing = dateMap[dateKey];

      if (existing == null) {
        dateMap[dateKey] = log;
        continue;
      }

      // Check if current log has a date-based ID (contains a hyphen in the suffix)
      // ID format is: USERID_YYYY-M-D
      final isNewFormat = log.id.split('_').last.contains('-');
      final isExistingNewFormat = existing.id.split('_').last.contains('-');

      if (isNewFormat && !isExistingNewFormat) {
        // Priority: Date-based ID wins over timestamp ID
        dateMap[dateKey] = log;
      } else if (isNewFormat == isExistingNewFormat) {
        // If both are same format, keep the one with more sessions or just the latest one
        if (log.sessions.length > existing.sessions.length) {
          dateMap[dateKey] = log;
        }
      }
    }

    return dateMap.values.toList();
  }

  /// Returns a list of dates that have already been logged in the local Hive cache.
  /// Useful for immediate UI/Notification feedback before Firestore sync completes.
  Future<List<DateTime>> getCachedLoggedDates() async {
    try {
      final box = await Hive.openBox<Map>('attendance_logs');
      final logs = box.values
          .map((e) => AttendanceLog.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      
      // We deduplicate by day here as well
      final deduplicated = _deduplicateLogs(logs);
      return deduplicated.map((l) => l.date).toList();
    } catch (_) {
      return [];
    }
  }

  /// Recent logs from the local Hive cache only (no network round-trip) —
  /// used by the automatic detection engine's low-weight HistoricalEvidence
  /// tie-breaker (see docs/AUTO_ATTENDANCE_DESIGN.md section 4), which must
  /// stay cheap enough to run inside a short-lived background isolate.
  Future<List<AttendanceLog>> getRecentLogsFromCache({int days = 14}) async {
    try {
      final box = await Hive.openBox<Map>('attendance_logs');
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final logs = box.values
          .map((e) => AttendanceLog.fromMap(Map<String, dynamic>.from(e)))
          .where((l) => l.date.isAfter(cutoff))
          .toList();
      return _deduplicateLogs(logs);
    } catch (_) {
      return [];
    }
  }

  Future<List<int>> getActiveYears() async {
    final currentYear = DateTime.now().year;

    try {
      final snapshot = await _attendanceCollection
          .orderBy('date', descending: false)
          .limit(1)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 10));

      if (snapshot.docs.isNotEmpty) {
        final oldestLog = AttendanceLog.fromMap(
          snapshot.docs.first.data() as Map<String, dynamic>,
        );

        final oldestYear = oldestLog.date.year;

        // Ensure oldestYear is not completely wrong/future.
        if (oldestYear <= currentYear) {
          return List.generate(
            currentYear - oldestYear + 1,
            (index) => oldestYear + index,
          );
        }
      }
    } catch (_) {
      // Fallback below
    }

    return [currentYear];
  }

  Future<void> syncOfflineLogs() async {
    var box = await Hive.openBox<Map>('attendance_logs');
    var offlineLogs = box.values
        .map((e) => AttendanceLog.fromMap(Map<String, dynamic>.from(e)))
        .where((log) => !log.isSynced)
        .toList();

    for (var log in offlineLogs) {
      try {
        await _attendanceCollection
            .doc(log.id)
            .set(log.toMap())
            .timeout(const Duration(seconds: 15));

        // Mark as synced locally
        var updatedLog = AttendanceLog(
          id: log.id,
          userId: log.userId,
          date: log.date,
          timestamp: log.timestamp,
          isSynced: true,
          method: log.method,
          inTime: log.inTime,
          outTime: log.outTime,
        );

        await box.put(log.id, updatedLog.toMap());
      } catch (_) {
        // failed
      }
    }
  }
}
