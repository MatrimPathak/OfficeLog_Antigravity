import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/attendance_rules.dart';
import '../providers/providers.dart';

const List<String> _weekdayLabels = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

class AttendanceRulesScreen extends ConsumerWidget {
  const AttendanceRulesScreen({super.key});

  void _applyChange(
    WidgetRef ref,
    AttendanceRulesConfig Function(AttendanceRulesConfig current) fn,
  ) {
    final current = ref.read(attendanceRulesConfigProvider);
    ref.read(attendanceRulesConfigProvider.notifier).update(fn(current));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(attendanceRulesConfigProvider);
    final isWeekly = rules.periodType == AttendancePeriodType.weekly;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text('Attendance Rules'),
        centerTitle: true,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                _applyChange(ref, (_) => AttendanceRulesConfig.defaultConfig),
            child: const Text(
              'Reset',
              style: TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('CALCULATION PERIOD'),
            _buildSettingsGroup(
              context,
              children: [
                _buildSettingsTile(
                  context,
                  icon: Icons.calendar_view_month_rounded,
                  iconColor: AppTheme.primaryColor,
                  title: 'Period',
                  trailing: _buildPillToggle<AttendancePeriodType>(
                    context,
                    options: const {
                      AttendancePeriodType.weekly: 'Weekly',
                      AttendancePeriodType.monthly: 'Monthly',
                    },
                    selected: rules.periodType,
                    color: AppTheme.primaryColor,
                    onSelected: (value) =>
                        _applyChange(ref, (c) => c.copyWith(periodType: value)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _buildSectionHeader('WEEK START'),
            _buildSettingsGroup(
              context,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.view_week_rounded,
                          color: Colors.cyanAccent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(7, (i) {
                            final weekday = i + 1; // 1=Mon..7=Sun
                            final selected = rules.weekStartDay == weekday;
                            return _buildDayChip(
                              context,
                              label: _weekdayLabels[i],
                              selected: selected,
                              color: Colors.cyanAccent.shade700,
                              onTap: () => _applyChange(
                                ref,
                                (c) => c.copyWith(weekStartDay: weekday),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _buildSectionHeader('REQUIREMENT TYPE'),
            _buildSettingsGroup(
              context,
              children: [
                _buildSettingsTile(
                  context,
                  icon: Icons.rule_rounded,
                  iconColor: AppTheme.purpleAccent,
                  title: 'Measure by',
                  trailing: _buildPillToggle<RequirementType>(
                    context,
                    options: const {
                      RequirementType.fixedDays: 'Fixed Days',
                      RequirementType.percentage: 'Percentage',
                    },
                    selected: rules.requirementType,
                    color: AppTheme.purpleAccent,
                    onSelected: (value) => _applyChange(
                      ref,
                      (c) => c.copyWith(requirementType: value),
                    ),
                  ),
                ),
                _buildDivider(context),
                if (rules.requirementType == RequirementType.fixedDays)
                  _buildSettingsTile(
                    context,
                    icon: Icons.checklist_rounded,
                    iconColor: AppTheme.purpleAccent,
                    title: isWeekly
                        ? 'Days required each week'
                        : 'Days required each month',
                    trailing: _buildStepper(
                      context,
                      value: rules.requiredDays,
                      min: 0,
                      max: isWeekly ? 7 : 31,
                      step: 1,
                      color: AppTheme.purpleAccent,
                      onChanged: (v) => _applyChange(
                        ref,
                        (c) => isWeekly
                            ? c.copyWith(requiredDaysPerWeek: v)
                            : c.copyWith(requiredDaysPerMonth: v),
                      ),
                    ),
                  )
                else
                  _buildSettingsTile(
                    context,
                    icon: Icons.percent_rounded,
                    iconColor: AppTheme.purpleAccent,
                    title: 'Percentage of working days',
                    trailing: _buildStepper(
                      context,
                      value: rules.requiredPercentage,
                      min: 0,
                      max: 100,
                      step: 5,
                      suffix: '%',
                      color: AppTheme.purpleAccent,
                      onChanged: (v) => _applyChange(
                        ref,
                        (c) => c.copyWith(requiredPercentage: v),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            _buildSectionHeader('WORKING DAYS'),
            _buildSettingsGroup(
              context,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.shade700.withValues(
                            alpha: 0.2,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.event_available,
                          color: Colors.tealAccent.shade700,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(7, (i) {
                            final weekday = i + 1; // 1=Mon..7=Sun
                            final selected = rules.workingWeekdays.contains(
                              weekday,
                            );
                            return _buildDayChip(
                              context,
                              label: _weekdayLabels[i],
                              selected: selected,
                              color: Colors.tealAccent.shade700,
                              onTap: () {
                                final updated = Set<int>.from(
                                  rules.workingWeekdays,
                                );
                                if (selected) {
                                  if (updated.length <= 1) return;
                                  updated.remove(weekday);
                                } else {
                                  updated.add(weekday);
                                }
                                _applyChange(
                                  ref,
                                  (c) => c.copyWith(workingWeekdays: updated),
                                );
                              },
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _buildSectionHeader('WHEN A HOLIDAY FALLS ON A WORKING DAY'),
            _buildSettingsGroup(
              context,
              children: [
                _buildRadioRow(
                  context,
                  ref: ref,
                  value: HolidayReductionMode.matchAvailableDays,
                  groupValue: rules.holidayReductionMode,
                  title: 'Reduce to match availability',
                  subtitle:
                      'Required days drop to however many working days are actually left',
                ),
                _buildDivider(context),
                _buildRadioRow(
                  context,
                  ref: ref,
                  value: HolidayReductionMode.fixed,
                  groupValue: rules.holidayReductionMode,
                  title: 'Never reduce',
                  subtitle: 'Holidays don\'t lower the requirement',
                ),
                _buildDivider(context),
                _buildRadioRow(
                  context,
                  ref: ref,
                  value: HolidayReductionMode.customTable,
                  groupValue: rules.holidayReductionMode,
                  title: 'Custom',
                  subtitle:
                      'Set your own required-days override per number of unavailable days',
                ),
                if (rules.holidayReductionMode ==
                    HolidayReductionMode.customTable) ...[
                  _buildDivider(context),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _CustomReductionTableEditor(
                      rules: rules,
                      onApply: (fn) => _applyChange(ref, fn),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildSettingsGroup(
    BuildContext context, {
    required List<Widget> children,
  }) {
    return Card(child: Column(children: children));
  }

  Widget _buildDivider(BuildContext context) {
    return Divider(height: 1, color: Theme.of(context).dividerColor);
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 15,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildPillToggle<T>(
    BuildContext context, {
    required Map<T, String> options,
    required T selected,
    required Color color,
    required ValueChanged<T> onSelected,
  }) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.entries.map((entry) {
          final isSelected = entry.key == selected;
          return GestureDetector(
            onTap: () => onSelected(entry.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.18) : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  color: isSelected
                      ? color
                      : Theme.of(context).colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDayChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Theme.of(context).dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 14, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? color
                    : Theme.of(context).colorScheme.onSurface.withValues(
                        alpha: 0.6,
                      ),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioRow(
    BuildContext context, {
    required WidgetRef ref,
    required HolidayReductionMode value,
    required HolidayReductionMode groupValue,
    required String title,
    required String subtitle,
  }) {
    final selected = value == groupValue;
    return InkWell(
      onTap: () => _applyChange(ref, (c) => c.copyWith(holidayReductionMode: value)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Radio<HolidayReductionMode>(
              value: value,
              groupValue: groupValue,
              activeColor: Colors.orangeAccent,
              onChanged: (mode) => _applyChange(
                ref,
                (c) => c.copyWith(holidayReductionMode: mode),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.orangeAccent
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[500], fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepper(
    BuildContext context, {
    required int value,
    required int min,
    required int max,
    required Color color,
    required ValueChanged<int> onChanged,
    int step = 1,
    String suffix = '',
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            Icons.remove_circle_outline,
            color: value > min ? color : Colors.grey,
          ),
          onPressed: value > min
              ? () => onChanged((value - step).clamp(min, max))
              : null,
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$value$suffix',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.add_circle_outline,
            color: value < max ? color : Colors.grey,
          ),
          onPressed: value < max
              ? () => onChanged((value + step).clamp(min, max))
              : null,
        ),
      ],
    );
  }
}

class _CustomReductionTableEditor extends StatelessWidget {
  final AttendanceRulesConfig rules;
  final void Function(
    AttendanceRulesConfig Function(AttendanceRulesConfig current) fn,
  )
  onApply;

  const _CustomReductionTableEditor({
    required this.rules,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final maxUnavailable = rules.workingWeekdays.length;
    final target = rules.computeTargetForScheduledDays(
      rules.workingWeekdays.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'UNAVAILABLE DAYS -> REQUIRED DAYS',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        for (int unavailable = 0; unavailable <= maxUnavailable; unavailable++)
          _buildRow(context, unavailable, target),
      ],
    );
  }

  Widget _buildRow(BuildContext context, int unavailable, int target) {
    final table = rules.customReductionTable;
    final hasOverride = table.containsKey(unavailable);
    final available = rules.workingWeekdays.length - unavailable;
    final defaultValue = available < target ? available : target;
    final displayValue = table[unavailable] ?? defaultValue;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$unavailable unavailable',
              style: TextStyle(fontSize: 13.5, color: onSurface),
            ),
          ),
          if (hasOverride) ...[
            IconButton(
              icon: const Icon(
                Icons.remove_circle_outline,
                size: 20,
                color: Colors.blueAccent,
              ),
              onPressed: displayValue > 0
                  ? () {
                      final updated = Map<int, int>.from(table);
                      updated[unavailable] = displayValue - 1;
                      onApply((c) => c.copyWith(customReductionTable: updated));
                    }
                  : null,
            ),
            SizedBox(
              width: 24,
              child: Text(
                '$displayValue',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: onSurface),
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.add_circle_outline,
                size: 20,
                color: Colors.blueAccent,
              ),
              onPressed: () {
                final updated = Map<int, int>.from(table);
                updated[unavailable] = displayValue + 1;
                onApply((c) => c.copyWith(customReductionTable: updated));
              },
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.grey),
              tooltip: 'Use default',
              onPressed: () {
                final updated = Map<int, int>.from(table)..remove(unavailable);
                onApply((c) => c.copyWith(customReductionTable: updated));
              },
            ),
          ] else ...[
            Text(
              '$displayValue (default)',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                final updated = Map<int, int>.from(table);
                updated[unavailable] = defaultValue;
                onApply((c) => c.copyWith(customReductionTable: updated));
              },
              child: const Text(
                'Override',
                style: TextStyle(fontSize: 12, color: Colors.blueAccent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
