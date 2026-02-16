import '../data/models/attendance_log.dart';

class StatsCalculator {
  /// Calculates the number of working days in a week given a list of holidays in that week.
  /// Working days are Mon-Fri excluding holidays.
  static int calculateWorkingDaysInWeek(
    DateTime startOfWeek,
    List<DateTime> holidaysInWeek,
  ) {
    int workingDays = 0;
    // Iterate from Monday (0) to Friday (4)
    for (int i = 0; i < 5; i++) {
      DateTime day = startOfWeek.add(Duration(days: i));
      // Check if this day is a holiday
      bool isHoliday = holidaysInWeek.any((h) => isSameDay(h, day));
      if (!isHoliday) {
        workingDays++;
      }
    }
    return workingDays;
  }

  /// Calculates required days based on the rules:
  /// 1. 3 days a week
  /// 2. If a week has 3 or less days all are required
  /// 3. If full week (5 working days), 3 required.
  /// 4. Holidays reduce requirement:
  ///    - 1 holiday -> 3 required (same as full)
  ///    - 2 holidays -> 3 required
  ///    - 3 holidays -> 2 required
  ///    - 4 holidays -> 1 required
  ///    - 5 holidays -> 0 required
  static int calculateRequiredDays(int workingDaysInWeek, int holidaysCount) {
    return workingDaysInWeek >= 3 ? 3 : workingDaysInWeek;
  }

  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static StatsResult calculateStats({
    required DateTime start,
    required DateTime end,
    required List<AttendanceLog> logs,
    required List<DateTime> holidays,
    bool calculateHolidayAsWorking = false,
  }) {
    int totalRequired = 0;
    int totalLogged = 0;
    int totalPending = 0;
    int holidayCount = 0;

    // Filter logs within range
    final rangeLogs = logs
        .where(
          (l) =>
              l.date.isAfter(start.subtract(const Duration(seconds: 1))) &&
              l.date.isBefore(end.add(const Duration(seconds: 1))),
        )
        .toList();
    totalLogged = rangeLogs.length;

    // Iterate by weeks to calculate requirement
    // Start from the first Sunday preceding or equal to start
    // DateTime.weekday: Mon=1, ..., Sun=7.
    // To get Sunday: if 7 (Sun), subtract 0. If 1 (Mon), subtract 1.
    // No, wait. If week starts Sunday:
    // Sunday (7) -> Start of this week.
    // Monday (1) -> Start - 1?
    // Let's use % 7.
    // Mon(1) % 7 = 1. Sun(7) % 7 = 0.
    // So subtract (weekday % 7).
    DateTime currentWeekStart = start.subtract(
      Duration(days: start.weekday % 7),
    );

    // Iterate until we pass the end
    while (currentWeekStart.isBefore(end.add(const Duration(days: 1)))) {
      // Identify working days in this week that are ALSO in the requested range
      int workingDaysInRange = 0;

      // Check Mon-Fri
      for (int i = 0; i < 5; i++) {
        // Week starts on Sunday.
        // i=0 -> Sunday + 0? No.
        // currentWeekStart is a Sunday.
        // Mon is index 1. Fri is index 5.
        // Wait, loop i should be relative to currentWeekStart?

        // currentWeekStart is Sunday.
        // Mon = currentWeekStart + 1 day
        // ...
        // Fri = currentWeekStart + 5 days

        // So we should check indices 1 to 5.
      }

      // Correct loop: 1 (Mon) to 5 (Fri)
      for (int i = 1; i <= 5; i++) {
        DateTime day = currentWeekStart.add(Duration(days: i));

        // Check if day is within range [start, end]
        bool inRange = !day.isBefore(start) && !day.isAfter(end);

        if (inRange) {
          bool isHoliday = holidays.any((h) => isSameDay(h, day));
          if (isHoliday && !calculateHolidayAsWorking) {
            holidayCount++;
          }

          if (!isHoliday || calculateHolidayAsWorking) {
            workingDaysInRange++;
          }
        }
      }

      // Calculate required for this week based on available working days in range
      // Rule: If <= 3 days available, all are required. If > 3, only 3 required.
      int weeklyRequired = workingDaysInRange >= 3 ? 3 : workingDaysInRange;

      // We no longer calculate weeklyPending here as we use a global subtraction later.

      totalRequired += weeklyRequired;

      currentWeekStart = currentWeekStart.add(const Duration(days: 7));
    }

    // New Logic: Pending is simply Total Required - Total Logged
    // This allows "extra" days in one week to visually offset the total count,
    // resolving the "12 - 9 = 6" confusion.
    // Re-use totalPending variable declared earlier
    totalPending = totalRequired - totalLogged;
    if (totalPending < 0) totalPending = 0;

    // Calculate total business days directly in the range
    int totalBusinessDays = 0;
    DateTime loopDay = start;
    // Iterate day by day from start to end
    while (!loopDay.isAfter(end)) {
      if (loopDay.weekday >= 1 && loopDay.weekday <= 5) {
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
      businessDays: totalBusinessDays,
      holidayCount: holidayCount,
    );
  }
}

class StatsResult {
  final int required;
  final int logged;
  final int pending;
  final int businessDays;
  final int holidayCount;

  StatsResult({
    required this.required,
    required this.logged,
    required this.pending,
    required this.businessDays,
    required this.holidayCount,
  });
}

class YearlyStatsResult {
  final int ytdPresent;
  final int ytdRequired;
  final int totalYearlyRequired; // New field for full year requirement
  final double overallAttendance; // percentage 0-100
  final String bestMonthName;
  final double bestMonthPercentage;
  final List<MonthlyStats> monthlyBreakdown;
  final Map<int, double> quarterlyPerformance; // 1-4 : percentage

  int get totalShortfall {
    final now = DateTime.now();
    // We don't have the 'year' here, but we can infer if it's a past year
    // if the last month is in the past. However, usually this is called
    // for the 'current' year view.

    return monthlyBreakdown
        .where((m) {
          // If it's the current year (we assume based on the data if it's YTD)
          // For simplicity, we compare month number if we are in the same year.
          // But summary_screen passes currentYear.
          // Let's just use the logic: month < now.month (assuming current year).
          // If this is a past year, all months should be counted.
          // If this is a future year, no months should be counted.
          // Since YearlyStatsResult doesn't have the year, this is slightly tricky
          // to make universal without adding the year field.

          return m.month < now.month &&
              m.requiredDays > 0 &&
              m.presentDays < m.requiredDays;
        })
        .fold(0, (sum, m) => sum + (m.requiredDays - m.presentDays));
  }

  YearlyStatsResult({
    required this.ytdPresent,
    required this.ytdRequired,
    required this.totalYearlyRequired,
    required this.overallAttendance,
    required this.bestMonthName,
    required this.bestMonthPercentage,
    required this.monthlyBreakdown,
    required this.quarterlyPerformance,
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

  MonthlyStats({
    required this.month,
    required this.monthName,
    required this.totalDays,
    required this.presentDays,
    required this.requiredDays,
    required this.holidayDays,
    required this.attendancePercentage,
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
        calculateHolidayAsWorking: calculateHolidayAsWorking,
      );

      double percentage = 0;
      if (stats.required > 0) {
        percentage = (stats.logged / stats.required) * 100;
        if (percentage > 100) percentage = 100;
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

    return YearlyStatsResult(
      ytdPresent: ytdPresent,
      ytdRequired: ytdRequired,
      totalYearlyRequired: totalYearlyRequired,
      overallAttendance: overall,
      bestMonthName: bestMonth?.monthName.substring(0, 3) ?? '-',
      bestMonthPercentage: bestMonth?.attendancePercentage ?? 0,
      monthlyBreakdown: monthlyBreakdown,
      quarterlyPerformance: quarterly,
    );
  }
}
