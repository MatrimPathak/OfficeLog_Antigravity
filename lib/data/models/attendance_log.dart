import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceLog {
  final String id;
  final String userId;
  final DateTime date;
  final DateTime timestamp;
  final bool isSynced;
  final String method; // 'manual', 'auto'

  AttendanceLog({
    required this.id,
    required this.userId,
    required this.date,
    required this.timestamp,
    this.isSynced = false,
    required this.method,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'date': date, // Store as DateTime (compatible with Hive & Firestore)
      'timestamp': timestamp,
      'isSynced': isSynced,
      'method': method,
    };
  }

  factory AttendanceLog.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return DateTime.now(); // Fallback
    }

    return AttendanceLog(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      date: parseDate(map['date']),
      timestamp: parseDate(map['timestamp']),
      isSynced: map['isSynced'] ?? false,
      method: map['method'] ?? 'manual',
    );
  }
}
