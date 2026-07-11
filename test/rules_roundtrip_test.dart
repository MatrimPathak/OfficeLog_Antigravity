import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_log/data/models/attendance_rules.dart';

void main() {
  test('AttendanceRulesConfig survives a jsonEncode/decode round trip', () {
    final config = AttendanceRulesConfig(
      periodType: AttendancePeriodType.monthly,
      weekStartDay: 1,
      workingWeekdays: {1, 2, 3, 4, 6},
      requirementType: RequirementType.percentage,
      requiredDaysPerWeek: 3,
      requiredDaysPerMonth: 15,
      requiredPercentage: 70,
      holidayReductionMode: HolidayReductionMode.customTable,
      customReductionTable: {0: 3, 2: 1, 5: 0},
    );

    final jsonStr = jsonEncode(config.toMap());
    final decoded = AttendanceRulesConfig.fromMap(
      jsonDecode(jsonStr) as Map<String, dynamic>,
    );

    expect(decoded.periodType, config.periodType);
    expect(decoded.weekStartDay, config.weekStartDay);
    expect(decoded.workingWeekdays, config.workingWeekdays);
    expect(decoded.requirementType, config.requirementType);
    expect(decoded.requiredDaysPerWeek, config.requiredDaysPerWeek);
    expect(decoded.requiredDaysPerMonth, config.requiredDaysPerMonth);
    expect(decoded.requiredPercentage, config.requiredPercentage);
    expect(decoded.holidayReductionMode, config.holidayReductionMode);
    expect(decoded.customReductionTable, config.customReductionTable);
  });
}
