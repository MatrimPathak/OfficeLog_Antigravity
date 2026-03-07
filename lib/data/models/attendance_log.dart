import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceSession {
  final DateTime inTime;
  final DateTime? outTime;

  AttendanceSession({required this.inTime, this.outTime});

  Map<String, dynamic> toMap() {
    return {'inTime': inTime, 'outTime': outTime};
  }

  factory AttendanceSession.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return DateTime.now(); // Fallback
    }

    return AttendanceSession(
      inTime: parseDate(map['inTime']),
      outTime: map['outTime'] != null ? parseDate(map['outTime']) : null,
    );
  }

  Duration get duration {
    if (outTime == null) return Duration.zero;
    return outTime!.difference(inTime);
  }
}

class AttendanceLog {
  final String id;
  final String userId;
  final DateTime date;
  final DateTime timestamp;
  final bool isSynced;
  final String method; // 'manual', 'auto'

  @Deprecated('Use sessions instead for exact tracking')
  final DateTime? inTime;
  @Deprecated('Use sessions instead for exact tracking')
  final DateTime? outTime;

  final List<AttendanceSession> sessions;

  AttendanceLog({
    required this.id,
    required this.userId,
    required this.date,
    required this.timestamp,
    this.isSynced = false,
    required this.method,
    this.inTime,
    this.outTime,
    this.sessions = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'date': date, // Store as DateTime (compatible with Hive & Firestore)
      'timestamp': timestamp,
      'isSynced': isSynced,
      'method': method,
      'inTime': inTime ?? timestamp, // fallback for backward compatibility
      'outTime': outTime,
      'sessions': sessions.map((s) => s.toMap()).toList(),
    };
  }

  factory AttendanceLog.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return DateTime.now(); // Fallback
    }

    final parsedInTime = map['inTime'] != null
        ? parseDate(map['inTime'])
        : parseDate(map['timestamp']);
    final parsedOutTime = map['outTime'] != null
        ? parseDate(map['outTime'])
        : null;

    // Lazy Migration Logic
    List<AttendanceSession> parsedSessions = [];
    if (map['sessions'] != null && map['sessions'] is List) {
      parsedSessions = (map['sessions'] as List).map((s) {
        // Handle maps natively if they come from Hive (Map<dynamic,dynamic>) or Firestore
        if (s is Map) {
          return AttendanceSession.fromMap(Map<String, dynamic>.from(s));
        }
        return AttendanceSession(inTime: parsedInTime);
      }).toList();
    } else {
      // Missing 'sessions' key indicates old data format, migrate lazily to one session block
      parsedSessions.add(
        AttendanceSession(inTime: parsedInTime, outTime: parsedOutTime),
      );
    }

    return AttendanceLog(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      date: parseDate(map['date']),
      timestamp: parseDate(map['timestamp']),
      isSynced: map['isSynced'] ?? false,
      method: map['method'] ?? 'manual',
      inTime: parsedInTime,
      outTime: parsedOutTime,
      sessions: parsedSessions,
    );
  }
}
