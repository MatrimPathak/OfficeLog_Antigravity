import 'dart:math';
import '../data/models/attendance_log.dart';
import '../data/models/attendance_rules.dart';

class StatsCalculator {
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Resolves how many days are required for a period given how many
  /// working days were scheduled vs actually available (i.e. not holidays).
  static int _resolveRequired({
    required int scheduledWorkingDays,
    required int availableWorkingDays,
    required AttendanceRulesConfig rules,
  }) {
    final target = rules.computeTargetForScheduledDays(scheduledWorkingDays);
    switch (rules.holidayReductionMode) {
      case HolidayReductionMode.fixed:
        return min(target, scheduledWorkingDays);
      case HolidayReductionMode.matchAvailableDays:
        return min(target, availableWorkingDays);
      case HolidayReductionMode.customTable:
        final unavailable = scheduledWorkingDays - availableWorkingDays;
        final override = rules.customReductionTable[unavailable];
        return override ?? min(target, availableWorkingDays);
    }
  }

  static StatsResult calculateStats({
    required DateTime start,
    required DateTime end,
    required List<AttendanceLog> logs,
    required List<DateTime> holidays,
    required AttendanceRulesConfig rules,
    bool calculateHolidayAsWorking = false,
  }) {
    int totalRequired = 0;
    int totalLogged = 0;
    int totalPending = 0;
    int holidayCount = 0;

    // Filter logs within range, stripping out the time component for accurate boundary checks
    final startDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);

    final rangeLogs = logs.where((l) {
      final logDate = DateTime(l.date.year, l.date.month, l.date.day);
      return !logDate.isBefore(startDate) && !logDate.isAfter(endDate);
    }).toList();
    totalLogged = rangeLogs.length;

    // Counts a [periodStart, periodEnd] window (inclusive), clipped to
    // [startDate, endDate], adding to totalRequired/holidayCount.
    void tallyPeriod(DateTime periodStart, DateTime periodEnd) {
      int scheduledWorkingDays = 0;
      int availableWorkingDays = 0;

      DateTime day = DateTime(periodStart.year, periodStart.month, periodStart.day);
      final normalizedPeriodEnd =
          DateTime(periodEnd.year, periodEnd.month, periodEnd.day);
      while (!day.isAfter(normalizedPeriodEnd)) {
        final inRange = !day.isBefore(startDate) && !day.isAfter(endDate);
        if (inRange && rules.workingWeekdays.contains(day.weekday)) {
          scheduledWorkingDays++;
          final isHoliday = holidays.any((h) => isSameDay(h, day));
          if (isHoliday && !calculateHolidayAsWorking) {
            holidayCount++;
          } else {
            availableWorkingDays++;
          }
        }
        day = day.add(const Duration(days: 1));
      }

      totalRequired += _resolveRequired(
        scheduledWorkingDays: scheduledWorkingDays,
        availableWorkingDays: availableWorkingDays,
        rules: rules,
      );
    }

    if (rules.periodType == AttendancePeriodType.monthly) {
      // Walk calendar months overlapping the range.
      DateTime monthCursor = DateTime(startDate.year, startDate.month, 1);
      while (!monthCursor.isAfter(endDate)) {
        final monthEnd = DateTime(monthCursor.year, monthCursor.month + 1, 0);
        tallyPeriod(monthCursor, monthEnd);
        monthCursor = DateTime(monthCursor.year, monthCursor.month + 1, 1);
      }
    } else {
      // Walk weeks overlapping the range, starting on rules.weekStartDay.
      // DateTime.weekday: Mon=1, ..., Sun=7. This finds the configured
      // start-of-week on or before `start` (weekStartDay=7 reproduces the
      // original Sunday-start behavior exactly).
      final offset = (start.weekday - rules.weekStartDay + 7) % 7;
      DateTime weekStart = start.subtract(Duration(days: offset));
      while (weekStart.isBefore(end.add(const Duration(days: 1)))) {
        final weekEnd = weekStart.add(const Duration(days: 6));
        tallyPeriod(weekStart, weekEnd);
        weekStart = weekStart.add(const Duration(days: 7));
      }
    }

    // Pending is simply Total Required - Total Logged. This allows "extra"
    // days in one period to visually offset the total count.
    totalPending = totalRequired - totalLogged;
    if (totalPending < 0) totalPending = 0;

    int totalExcess = totalLogged - totalRequired;
    if (totalExcess < 0) totalExcess = 0;

    int totalBusinessDays = 0;
    DateTime loopDay = startDate;

    while (!loopDay.isAfter(endDate)) {
      if (rules.workingWeekdays.contains(loopDay.weekday)) {
        bool isHoliday = holidays.any((h) => isSameDay(h, loopDay));
        if (!isHoliday || calculateHolidayAsWorking) {
          totalBusinessDays++;
        }
      }
      loopDay = loopDay.add(const Duration(days: 1));
    }

    return StatsResult(
      required: totalRequired,
      logged: totalLogged,
      pending: totalPending,
      excess: totalExcess,
      businessDays: totalBusinessDays,
      holidayCount: holidayCount,
    );
  }
}

class StatsResult {
  final int required;
  final int logged;
  final int pending;
  final int excess;
  final int businessDays;
  final int holidayCount;

  StatsResult({
    required this.required,
    required this.logged,
    required this.pending,
    required this.excess,
    required this.businessDays,
    required this.holidayCount,
  });
}

class YearlyStatsResult {
  final int year;
  final int ytdPresent;
  final int ytdRequired;
  final int totalYearlyRequired;
  final double overallAttendance; // percentage 0-100
  final String bestMonthName;
  final double bestMonthPercentage;
  final List<MonthlyStats> monthlyBreakdown;
  final Map<int, double> quarterlyPerformance; // 1-4 : percentage
  final double ytdTotalHours;
  final double ytdAvgHoursPerDay;

  int getNetBalanceUpTo(int targetMonth) {
    int requestedPresent = 0;
    int requestedRequired = 0;

    for (var m in monthlyBreakdown) {
      if (m.month <= targetMonth) {
        requestedPresent += m.presentDays;
        requestedRequired += m.requiredDays;
      }
    }

    return requestedPresent - requestedRequired;
  }

  YearlyStatsResult({
    required this.year,
    required this.ytdPresent,
    required this.ytdRequired,
    required this.totalYearlyRequired,
    required this.overallAttendance,
    required this.bestMonthName,
    required this.bestMonthPercentage,
    required this.monthlyBreakdown,
    required this.quarterlyPerformance,
    this.ytdTotalHours = 0.0,
    this.ytdAvgHoursPerDay = 0.0,
  });
}

class MonthlyStats {
  final int month; // 1-12
  final String monthName;
  final int totalDays;
  final int presentDays;
  final int requiredDays;
  final int holidayDays;
  final double attendancePercentage;
  final double totalHours;

  double get avgHoursPerDay =>
      presentDays > 0 ? totalHours / presentDays : 0.0;

  MonthlyStats({
    required this.month,
    required this.monthName,
    required this.totalDays,
    required this.presentDays,
    required this.requiredDays,
    required this.holidayDays,
    required this.attendancePercentage,
    this.totalHours = 0.0,
  });
}

extension DateTimeExtension on DateTime {
  String get monthName {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  String get monthAbbr {
    return monthName.substring(0, 3);
  }
}

// Add to StatsCalculator class
extension YearlyCalculator on StatsCalculator {
  static YearlyStatsResult calculateYearlyStats({
    required int year,
    required List<AttendanceLog> logs,
    required List<DateTime> holidays,
    required AttendanceRulesConfig rules,
    bool calculateHolidayAsWorking = false,
  }) {
    List<MonthlyStats> monthlyBreakdown = [];
    int ytdPresent = 0;
    int ytdRequired = 0;
    int totalYearlyRequired = 0;

    // We only calculate up to the current month to be realistic for YTD
    // But for the breakdown list, maybe we show all months?
    // Let's go month by month for the whole year.

    for (int month = 1; month <= 12; month++) {
      final start = DateTime(year, month, 1);
      final end = DateTime(year, month + 1, 0); // Last day of month

      // Calculate stats for this month
      final stats = StatsCalculator.calculateStats(
        start: start,
        end: end,
        logs: logs,
        holidays: holidays,
        rules: rules,
        calculateHolidayAsWorking: calculateHolidayAsWorking,
      );

      double percentage = 0;
      if (stats.businessDays > 0) {
        percentage = (stats.logged / stats.businessDays) * 100;
      }

      double totalHours = 0.0;
      final monthLogs = logs.where(
        (l) => l.date.month == month && l.date.year == year,
      );
      for (var l in monthLogs) {
        for (var session in l.sessions) {
          totalHours += session.duration.inMinutes / 60.0;
        }
      }

      monthlyBreakdown.add(
        MonthlyStats(
          month: month,
          monthName: start.monthName,
          totalDays: stats.businessDays,
          presentDays: stats.logged,
          requiredDays: stats.required,
          holidayDays: stats.holidayCount,
          attendancePercentage: percentage,
          totalHours: totalHours,
        ),
      );

      // Always add to total yearly required, regardless of whether month passed
      totalYearlyRequired += stats.required;

      // Update YTD only if month has passed or is current
      // Ideally we shouldn't count future months in "Total Required" YTD
      if (start.isBefore(DateTime.now())) {
        ytdPresent += stats.logged;
        ytdRequired += stats.required;
      }
    }

    // Best Month
    MonthlyStats? bestMonth;
    for (var m in monthlyBreakdown) {
      // Filter out months with 0 required (future or holidays only) to find actual best
      if (m.requiredDays > 0) {
        if (bestMonth == null ||
            m.attendancePercentage > bestMonth.attendancePercentage) {
          bestMonth = m;
        }
      }
    }

    // Overall Attendance (Based on Entire Year)
    double overall = 0;
    if (totalYearlyRequired > 0) {
      overall = (ytdPresent / totalYearlyRequired) * 100;
      if (overall > 100) overall = 100;
    }

    // Quarterly Performance
    Map<int, double> quarterly = {};
    for (int q = 1; q <= 4; q++) {
      int qStartMonth = (q - 1) * 3 + 1;
      int qEndMonth = qStartMonth + 2;

      int qPresent = 0;
      int qRequired = 0;

      for (int m = qStartMonth; m <= qEndMonth; m++) {
        // Find stats for this month
        final mStats = monthlyBreakdown.firstWhere(
          (element) => element.month == m,
        );

        // Month date not needed for logic anymore

        // Always add required days for the month to get total for the quarter
        qRequired += mStats.requiredDays;

        // Only add present days if month has passed/is current (logic handled by fact that logs exist)
        // Actually, mStats.presentDays comes from logs, so it's fine.
        qPresent += mStats.presentDays;
      }

      double qPct = 0;
      if (qRequired > 0) {
        qPct = (qPresent / qRequired) * 100;
        if (qPct > 100) qPct = 100;
      }
      quarterly[q] = qPct;
    }

    double ytdTotalHours = 0.0;
    for (var m in monthlyBreakdown) {
      if (DateTime(year, m.month, 1).isBefore(DateTime.now())) {
        ytdTotalHours += m.totalHours;
      }
    }
    final double ytdAvgHoursPerDay =
        ytdPresent > 0 ? ytdTotalHours / ytdPresent : 0.0;

    return YearlyStatsResult(
      year: year,
      ytdPresent: ytdPresent,
      ytdRequired: ytdRequired,
      totalYearlyRequired: totalYearlyRequired,
      overallAttendance: overall,
      bestMonthName: bestMonth?.monthName.substring(0, 3) ?? '-',
      bestMonthPercentage: bestMonth?.attendancePercentage ?? 0,
      monthlyBreakdown: monthlyBreakdown,
      quarterlyPerformance: quarterly,
      ytdTotalHours: ytdTotalHours,
      ytdAvgHoursPerDay: ytdAvgHoursPerDay,
    );
  }
}
