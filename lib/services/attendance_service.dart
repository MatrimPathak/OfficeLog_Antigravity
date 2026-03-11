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

      return snapshot.docs.map((doc) {
        return AttendanceLog.fromMap(doc.data() as Map<String, dynamic>);
      }).toList();
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

        return snapshot.docs.map((doc) {
          return AttendanceLog.fromMap(doc.data() as Map<String, dynamic>);
        }).toList();
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
          return snapshot.docs.map((doc) {
            return AttendanceLog.fromMap(doc.data() as Map<String, dynamic>);
          }).toList();
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
          return snapshot.docs.map((doc) {
            return AttendanceLog.fromMap(doc.data() as Map<String, dynamic>);
          }).toList();
        });
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
