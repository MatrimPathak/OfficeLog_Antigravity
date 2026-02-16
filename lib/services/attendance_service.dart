import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../data/models/attendance_log.dart';

class AttendanceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String userId;

  AttendanceService(this.userId);

  CollectionReference get _attendanceCollection =>
      _firestore.collection('users').doc(userId).collection('attendance');

  Future<void> logAttendance(AttendanceLog log) async {
    // Save to local Hive first (for offline support)
    var box = await Hive.openBox<Map>('attendance_logs');
    await box.put(log.id, log.toMap());

    try {
      // Try syncing to Firestore
      await _attendanceCollection.doc(log.id).set(log.toMap());

      // Update local status to synced
      var updatedLog = AttendanceLog(
        id: log.id,
        userId: log.userId,
        date: log.date,
        timestamp: log.timestamp,
        isSynced: true,
        method: log.method,
      );
      await box.put(log.id, updatedLog.toMap());
    } catch (e) {
      // log error
    }
  }

  Future<void> deleteAttendance(String logId) async {
    // Delete from local Hive
    var box = await Hive.openBox<Map>('attendance_logs');
    await box.delete(logId);

    try {
      // Delete from Firestore
      await _attendanceCollection.doc(logId).delete();
    } catch (e) {
      // log error or handle offline deletion queue if necessary
      // For now, assuming online or that Hive deletion is sufficient for UI update
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

  Future<void> syncOfflineLogs() async {
    var box = await Hive.openBox<Map>('attendance_logs');
    var offlineLogs = box.values
        .map((e) => AttendanceLog.fromMap(Map<String, dynamic>.from(e)))
        .where((log) => !log.isSynced)
        .toList();

    for (var log in offlineLogs) {
      try {
        await _attendanceCollection.doc(log.id).set(log.toMap());

        // Mark as synced locally
        var updatedLog = AttendanceLog(
          id: log.id,
          userId: log.userId,
          date: log.date,
          timestamp: log.timestamp,
          isSynced: true,
          method: log.method,
        );

        await box.put(log.id, updatedLog.toMap());
      } catch (_) {
        // failed
      }
    }
  }
}
