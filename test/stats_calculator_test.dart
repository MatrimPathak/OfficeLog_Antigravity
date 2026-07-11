import 'package:flutter_test/flutter_test.dart';
import 'package:office_log/data/models/attendance_log.dart';
import 'package:office_log/data/models/attendance_rules.dart';
import 'package:office_log/logic/stats_calculator.dart';

void main() {
  // Mon 2026-01-05 .. Sun 2026-01-11 is a clean Sun-Sat week.
  final monday = DateTime(2026, 1, 5);
  final sunday = DateTime(2026, 1, 11);

  List<DateTime> weekdayHolidays(int count) {
    return List.generate(count, (i) => monday.add(Duration(days: i)));
  }

  group('calculateStats — default config matches legacy Mon-Fri/3-per-week behavior', () {
    for (final entry in {0: 3, 1: 3, 2: 3, 3: 2, 4: 1, 5: 0}.entries) {
      test('${entry.key} holiday(s) in the week -> required ${entry.value}', () {
        final stats = StatsCalculator.calculateStats(
          start: monday,
          end: sunday,
          logs: const [],
          holidays: weekdayHolidays(entry.key),
          rules: AttendanceRulesConfig.defaultConfig,
        );
        expect(stats.required, entry.value);
        expect(stats.holidayCount, entry.key);
      });
    }
  });

  test('logged days offset pending/excess across the week', () {
    final logs = [
      AttendanceLog(
        id: '1',
        userId: 'u',
        date: monday,
        timestamp: monday,
        method: 'manual',
      ),
      AttendanceLog(
        id: '2',
        userId: 'u',
        date: monday.add(const Duration(days: 1)),
        timestamp: monday,
        method: 'manual',
      ),
    ];

    final stats = StatsCalculator.calculateStats(
      start: monday,
      end: sunday,
      logs: logs,
      holidays: const [],
      rules: AttendanceRulesConfig.defaultConfig,
    );

    expect(stats.logged, 2);
    expect(stats.required, 3);
    expect(stats.pending, 1);
    expect(stats.excess, 0);
  });

  test('fixed holiday reduction mode keeps the target regardless of holidays', () {
    final rules = AttendanceRulesConfig.defaultConfig.copyWith(
      holidayReductionMode: HolidayReductionMode.fixed,
    );
    final stats = StatsCalculator.calculateStats(
      start: monday,
      end: sunday,
      logs: const [],
      holidays: weekdayHolidays(3),
      rules: rules,
    );
    // scheduledWorkingDays is still 5 (Mon-Fri), so fixed mode requires min(3,5)=3
    expect(stats.required, 3);
  });

  test('custom reduction table overrides the resolved required days', () {
    final rules = AttendanceRulesConfig.defaultConfig.copyWith(
      holidayReductionMode: HolidayReductionMode.customTable,
      customReductionTable: {2: 1}, // 2 unavailable days -> only 1 required
    );
    final stats = StatsCalculator.calculateStats(
      start: monday,
      end: sunday,
      logs: const [],
      holidays: weekdayHolidays(2),
      rules: rules,
    );
    expect(stats.required, 1);
  });

  test('custom working weekdays (Sat included) change scheduled days', () {
    final rules = AttendanceRulesConfig.defaultConfig.copyWith(
      workingWeekdays: {1, 2, 3, 4, 5, 6}, // Mon-Sat
      requiredDaysPerWeek: 4,
    );
    final stats = StatsCalculator.calculateStats(
      start: monday,
      end: sunday,
      logs: const [],
      holidays: const [],
      rules: rules,
    );
    expect(stats.businessDays, 6);
    expect(stats.required, 4);
  });

  test('monthly period type treats the whole month as one bucket', () {
    final start = DateTime(2026, 2, 1);
    final end = DateTime(2026, 2, 28);
    final rules = AttendanceRulesConfig.defaultConfig.copyWith(
      periodType: AttendancePeriodType.monthly,
      requiredDaysPerMonth: 10,
    );
    final stats = StatsCalculator.calculateStats(
      start: start,
      end: end,
      logs: const [],
      holidays: const [],
      rules: rules,
    );
    expect(stats.required, 10);
  });

  group('requirementType: percentage', () {
    // Sun 2026-01-04 .. Sat 2026-01-10 is exactly one Sun-Sat week (5 scheduled
    // working days, Mon-Fri), so the period never splits mid-range.
    final sundayStart = DateTime(2026, 1, 4);
    final saturdayEnd = DateTime(2026, 1, 10);

    test('default 60% of a 5-day week matches the fixedDays default of 3', () {
      final rules = AttendanceRulesConfig.defaultConfig.copyWith(
        requirementType: RequirementType.percentage,
      );
      final stats = StatsCalculator.calculateStats(
        start: sundayStart,
        end: saturdayEnd,
        logs: const [],
        holidays: const [],
        rules: rules,
      );
      expect(stats.required, 3);
    });

    test('50% of a 5-day week rounds 2.5 up to 3', () {
      final rules = AttendanceRulesConfig.defaultConfig.copyWith(
        requirementType: RequirementType.percentage,
        requiredPercentage: 50,
      );
      final stats = StatsCalculator.calculateStats(
        start: sundayStart,
        end: saturdayEnd,
        logs: const [],
        holidays: const [],
        rules: rules,
      );
      expect(stats.required, 3);
    });

    test('percentage target still reduces via matchAvailableDays on holidays', () {
      final rules = AttendanceRulesConfig.defaultConfig.copyWith(
        requirementType: RequirementType.percentage,
        requiredPercentage: 50, // target = round(0.5 * 5) = 3
      );
      final stats = StatsCalculator.calculateStats(
        start: sundayStart,
        end: saturdayEnd,
        logs: const [],
        holidays: weekdayHolidays(4), // only 1 working day left available
        rules: rules,
      );
      expect(stats.required, 1);
    });
  });

  test('custom weekStartDay changes how the range is split into periods', () {
    // Wed-start weeks over Mon 2026-01-05..Sun 2026-01-11 split into
    // [Dec31..Jan6] (clipped to Jan5-6, 2 scheduled) and [Jan7..Jan13]
    // (clipped to Jan7-11, 3 scheduled: Wed/Thu/Fri) -> 2 + 3 = 5,
    // instead of the Sunday-start default's 3.
    final rules = AttendanceRulesConfig.defaultConfig.copyWith(weekStartDay: 3);
    final stats = StatsCalculator.calculateStats(
      start: monday,
      end: sunday,
      logs: const [],
      holidays: const [],
      rules: rules,
    );
    expect(stats.required, 5);
  });
}
