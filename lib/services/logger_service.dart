import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:developer' as developer;

enum LogLevel { info, warning, error }

enum LogType { general, background, network, auth, system }

class LogEntry {
  final DateTime timestamp;
  final String message;
  final LogType type;
  final LogLevel level;

  LogEntry({
    required this.timestamp,
    required this.message,
    required this.type,
    required this.level,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'message': message,
    'type': type.name,
    'level': level.name,
  };

  factory LogEntry.fromJson(Map<dynamic, dynamic> json) => LogEntry(
    timestamp: DateTime.parse(json['timestamp'] as String),
    message: json['message'] as String,
    type: LogType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => LogType.general,
    ),
    level: LogLevel.values.firstWhere(
      (e) => e.name == json['level'],
      orElse: () => LogLevel.info,
    ),
  );
}

class LoggerService {
  static const String _boxName = 'app_logs';
  static const int _maxLogs = 500;

  // Singleton instance for non-Riverpod access
  static final LoggerService instance = LoggerService._internal();

  LoggerService._internal();

  Future<void> _writeLog(LogEntry entry) async {
    try {
      final box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
      await box.add(entry.toJson());

      // Trim if too many
      if (box.length > _maxLogs) {
        final toDelete = box.length - _maxLogs;
        for (var i = 0; i < toDelete; i++) {
          await box.deleteAt(0);
        }
      }

      // Also echo to console for debugging during local dev
      if (entry.level == LogLevel.error) {
        developer.log(
          '[${entry.type.name.toUpperCase()}] ERROR: ${entry.message}',
        );
      } else {
        developer.log('[${entry.type.name.toUpperCase()}] ${entry.message}');
      }
    } catch (e) {
      developer.log('Failed to write app_log: $e');
    }
  }

  void info(String message, {LogType type = LogType.general}) {
    _writeLog(
      LogEntry(
        timestamp: DateTime.now(),
        message: message,
        type: type,
        level: LogLevel.info,
      ),
    );
  }

  void warning(String message, {LogType type = LogType.general}) {
    _writeLog(
      LogEntry(
        timestamp: DateTime.now(),
        message: message,
        type: type,
        level: LogLevel.warning,
      ),
    );
  }

  void error(String message, {LogType type = LogType.general}) {
    _writeLog(
      LogEntry(
        timestamp: DateTime.now(),
        message: message,
        type: type,
        level: LogLevel.error,
      ),
    );
  }

  // Helper for background check-in events
  void background(String message) {
    _writeLog(
      LogEntry(
        timestamp: DateTime.now(),
        message: message,
        type: LogType.background,
        level:
            message.contains('ERROR') ||
                message.contains('Error') ||
                message.contains('Failed')
            ? LogLevel.error
            : LogLevel.info,
      ),
    );
  }

  Future<void> clearLogs() async {
    try {
      final box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
      await box.clear();
    } catch (e) {
      developer.log('Failed to clear logs: $e');
    }
  }

  Box<Map<dynamic, dynamic>>? getBox() {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<Map<dynamic, dynamic>>(_boxName);
    }
    return null;
  }
}

final loggerServiceProvider = Provider<LoggerService>(
  (ref) => LoggerService.instance,
);
