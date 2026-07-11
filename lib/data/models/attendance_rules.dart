enum AttendancePeriodType { weekly, monthly }

enum HolidayReductionMode { matchAvailableDays, fixed, customTable }

enum RequirementType { fixedDays, percentage }

/// Configurable rules for how attendance requirements are calculated.
///
/// [customReductionTable] is keyed by "unavailable working days" in the
/// period (scheduledWorkingDays - availableWorkingDays), not raw holiday
/// count, so it also accounts for partial periods (e.g. a range that starts
/// mid-week) rather than only holidays.
class AttendanceRulesConfig {
  final AttendancePeriodType periodType;
  final int weekStartDay; // DateTime.weekday value, 1=Mon..7=Sun
  final Set<int> workingWeekdays; // DateTime.weekday values, 1=Mon..7=Sun
  final RequirementType requirementType;
  final int requiredDaysPerWeek;
  final int requiredDaysPerMonth;
  final int requiredPercentage; // 0-100, used when requirementType == percentage
  final HolidayReductionMode holidayReductionMode;
  final Map<int, int> customReductionTable;

  const AttendanceRulesConfig({
    required this.periodType,
    required this.weekStartDay,
    required this.workingWeekdays,
    required this.requirementType,
    required this.requiredDaysPerWeek,
    required this.requiredDaysPerMonth,
    required this.requiredPercentage,
    required this.holidayReductionMode,
    required this.customReductionTable,
  });

  int get requiredDays => periodType == AttendancePeriodType.weekly
      ? requiredDaysPerWeek
      : requiredDaysPerMonth;

  /// Resolves the required-days target for a period that scheduled
  /// [scheduledWorkingDays] working days, before any holiday reduction is
  /// applied. Shared by the calculator and the settings UI's live preview so
  /// the percentage math only lives in one place.
  int computeTargetForScheduledDays(int scheduledWorkingDays) {
    if (requirementType == RequirementType.percentage) {
      return (requiredPercentage / 100 * scheduledWorkingDays).round();
    }
    return requiredDays;
  }

  static const AttendanceRulesConfig defaultConfig = AttendanceRulesConfig(
    periodType: AttendancePeriodType.weekly,
    weekStartDay: 7, // Sunday
    workingWeekdays: {1, 2, 3, 4, 5},
    requirementType: RequirementType.fixedDays,
    requiredDaysPerWeek: 3,
    requiredDaysPerMonth: 12,
    requiredPercentage: 60,
    holidayReductionMode: HolidayReductionMode.matchAvailableDays,
    customReductionTable: {},
  );

  AttendanceRulesConfig copyWith({
    AttendancePeriodType? periodType,
    int? weekStartDay,
    Set<int>? workingWeekdays,
    RequirementType? requirementType,
    int? requiredDaysPerWeek,
    int? requiredDaysPerMonth,
    int? requiredPercentage,
    HolidayReductionMode? holidayReductionMode,
    Map<int, int>? customReductionTable,
  }) {
    return AttendanceRulesConfig(
      periodType: periodType ?? this.periodType,
      weekStartDay: weekStartDay ?? this.weekStartDay,
      workingWeekdays: workingWeekdays ?? this.workingWeekdays,
      requirementType: requirementType ?? this.requirementType,
      requiredDaysPerWeek: requiredDaysPerWeek ?? this.requiredDaysPerWeek,
      requiredDaysPerMonth: requiredDaysPerMonth ?? this.requiredDaysPerMonth,
      requiredPercentage: requiredPercentage ?? this.requiredPercentage,
      holidayReductionMode: holidayReductionMode ?? this.holidayReductionMode,
      customReductionTable: customReductionTable ?? this.customReductionTable,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'periodType': periodType.name,
      'weekStartDay': weekStartDay,
      'workingWeekdays': workingWeekdays.toList(),
      'requirementType': requirementType.name,
      'requiredDaysPerWeek': requiredDaysPerWeek,
      'requiredDaysPerMonth': requiredDaysPerMonth,
      'requiredPercentage': requiredPercentage,
      'holidayReductionMode': holidayReductionMode.name,
      'customReductionTable': customReductionTable.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
    };
  }

  factory AttendanceRulesConfig.fromMap(Map<String, dynamic> map) {
    return AttendanceRulesConfig(
      periodType: AttendancePeriodType.values.firstWhere(
        (e) => e.name == map['periodType'],
        orElse: () => AttendancePeriodType.weekly,
      ),
      weekStartDay: map['weekStartDay'] ?? 7,
      workingWeekdays: map['workingWeekdays'] != null
          ? Set<int>.from((map['workingWeekdays'] as List).map((e) => e as int))
          : {1, 2, 3, 4, 5},
      requirementType: RequirementType.values.firstWhere(
        (e) => e.name == map['requirementType'],
        orElse: () => RequirementType.fixedDays,
      ),
      requiredDaysPerWeek: map['requiredDaysPerWeek'] ?? 3,
      requiredDaysPerMonth: map['requiredDaysPerMonth'] ?? 12,
      requiredPercentage: map['requiredPercentage'] ?? 60,
      holidayReductionMode: HolidayReductionMode.values.firstWhere(
        (e) => e.name == map['holidayReductionMode'],
        orElse: () => HolidayReductionMode.matchAvailableDays,
      ),
      customReductionTable: map['customReductionTable'] != null
          ? (map['customReductionTable'] as Map).map(
              (k, v) => MapEntry(int.parse(k as String), v as int),
            )
          : {},
    );
  }
}
