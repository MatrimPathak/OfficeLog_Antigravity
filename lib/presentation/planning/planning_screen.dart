import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/attendance_log.dart';
import '../../logic/stats_calculator.dart';
import '../providers/providers.dart';
import '../../services/admin_service.dart';
import 'widgets/clear_planned_days_dialog.dart';

class PlanningScreen extends ConsumerStatefulWidget {
  const PlanningScreen({super.key});

  @override
  ConsumerState<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends ConsumerState<PlanningScreen> {
  DateTime _focusedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final plannedDatesAsync = ref.watch(plannedDatesProvider);
    final plannedDates = plannedDatesAsync.value ?? <DateTime>[];
    final yearlyLogsAsync = ref.watch(yearlyAttendanceProvider(now.year));
    final holidaysAsync = ref.watch(holidaysStreamProvider);
    final calculateAsWorking = ref.watch(calculateHolidayAsWorkingProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Planning Mode',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        centerTitle: false,
        actions: [
          if (plannedDates.isNotEmpty)
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => const ClearPlannedDaysDialog(),
                );
                if (confirm == true) {
                  await ref.read(plannedDaysServiceProvider)?.clear();
                }
              },
              child: const Text(
                'Clear',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
        ],
      ),
      body: yearlyLogsAsync.when(
        data: (logsData) {
          final logs = logsData.cast<AttendanceLog>();
          final holidays = holidaysAsync.value ?? <DateTime>[];

          final yearlyStats = YearlyCalculator.calculateYearlyStats(
            year: now.year,
            logs: logs,
            holidays: holidays,
            calculateHolidayAsWorking: calculateAsWorking,
          );

          final validPlannedDatesList = plannedDates
              .where(
                (d) =>
                    d.year == now.year &&
                    d.isAfter(today) &&
                    d.weekday != DateTime.saturday &&
                    d.weekday != DateTime.sunday &&
                    !holidays.any(
                      (h) =>
                          h.year == d.year &&
                          h.month == d.month &&
                          h.day == d.day,
                    ),
              )
              .toList();
          final validPlannedDays = validPlannedDatesList.length;

          final confirmedDays = yearlyStats.ytdPresent;
          final projectedTotal = confirmedDays + validPlannedDays;
          final totalRequired = yearlyStats.totalYearlyRequired;
          final netBalance = projectedTotal - totalRequired;
          final leaveBuffer = netBalance > 0 ? netBalance : 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProjectionCard(
                  context,
                  confirmedDays: confirmedDays,
                  plannedDays: validPlannedDays,
                  projectedTotal: projectedTotal,
                  totalRequired: totalRequired,
                  netBalance: netBalance,
                  leaveBuffer: leaveBuffer,
                ),
                const SizedBox(height: 16),
                _buildCurrentMonthCard(
                  context,
                  yearlyStats,
                  validPlannedDatesList,
                ),
                const SizedBox(height: 16),
                _buildLegend(context),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: TableCalendar(
                      firstDay: DateTime(now.year, 1, 1),
                      lastDay: DateTime(now.year, 12, 31),
                      focusedDay: _focusedDay,
                      calendarFormat: CalendarFormat.month,
                      availableCalendarFormats: const {
                        CalendarFormat.month: 'Month',
                      },
                      startingDayOfWeek: StartingDayOfWeek.sunday,
                      headerStyle: HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        leftChevronIcon: Icon(
                          Icons.chevron_left,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        rightChevronIcon: Icon(
                          Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      calendarStyle: CalendarStyle(
                        outsideDaysVisible: false,
                        defaultTextStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        weekendTextStyle: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                        todayDecoration: BoxDecoration(
                          color: Colors.transparent,
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blueAccent),
                        ),
                        todayTextStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        selectedDecoration: const BoxDecoration(
                          color: Colors.transparent,
                        ),
                      ),
                      onPageChanged: (day) {
                        setState(() => _focusedDay = day);
                      },
                      onDaySelected: (selectedDay, focusedDay) {
                        final normalized = DateTime(
                          selectedDay.year,
                          selectedDay.month,
                          selectedDay.day,
                        );
                        if (!normalized.isAfter(today)) return;
                        if (selectedDay.weekday == DateTime.saturday ||
                            selectedDay.weekday == DateTime.sunday) {
                          return;
                        }
                        final isHoliday = holidays.any(
                          (h) =>
                              h.year == selectedDay.year &&
                              h.month == selectedDay.month &&
                              h.day == selectedDay.day,
                        );
                        if (isHoliday) return;
                        ref.read(plannedDaysServiceProvider)?.toggle(selectedDay);
                        setState(() => _focusedDay = focusedDay);
                      },
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, day, events) {
                          final isWeekend =
                              day.weekday == DateTime.saturday ||
                              day.weekday == DateTime.sunday;
                          if (isWeekend) return null;

                          final isHoliday = holidays.any(
                            (h) =>
                                h.year == day.year &&
                                h.month == day.month &&
                                h.day == day.day,
                          );
                          final isAttended = logs.any(
                            (l) =>
                                l.date.year == day.year &&
                                l.date.month == day.month &&
                                l.date.day == day.day,
                          );
                          final isPast = DateTime(
                            day.year,
                            day.month,
                            day.day,
                          ).isBefore(today);
                          final isToday =
                              day.year == today.year &&
                              day.month == today.month &&
                              day.day == today.day;
                          final isPlanned = plannedDates.any(
                            (d) =>
                                d.year == day.year &&
                                d.month == day.month &&
                                d.day == day.day,
                          );
                          final isMissedPast =
                              (isPast || isToday) &&
                              !isHoliday &&
                              !isAttended &&
                              !isWeekend;

                          Color? dotColor;
                          if (isHoliday) {
                            dotColor = Colors.orangeAccent;
                          } else if (isAttended) {
                            dotColor = Colors.greenAccent;
                          } else if (isPlanned) {
                            dotColor = Colors.blueAccent;
                          } else if (isMissedPast) {
                            dotColor = Colors.redAccent.withValues(alpha: 0.7);
                          }

                          if (dotColor == null) return null;

                          return Positioned(
                            bottom: 6,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: dotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          );
                        },
                        defaultBuilder: (context, day, focusedDay) {
                          final isPlanned = plannedDates.any(
                            (d) =>
                                d.year == day.year &&
                                d.month == day.month &&
                                d.day == day.day,
                          );
                          if (!isPlanned) return null;
                          return Container(
                            margin: const EdgeInsets.all(5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${day.day}',
                              style: const TextStyle(color: Colors.blueAccent),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Tap a future weekday to add or remove it from your plan.',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildProjectionCard(
    BuildContext context, {
    required int confirmedDays,
    required int plannedDays,
    required int projectedTotal,
    required int totalRequired,
    required int netBalance,
    required int leaveBuffer,
  }) {
    final isOnTrack = netBalance >= 0;
    final netColor = isOnTrack ? Colors.greenAccent : AppTheme.dangerColor;
    final netIcon = isOnTrack
        ? Icons.check_circle_outline
        : Icons.warning_amber_rounded;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PROJECTION',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (plannedDays > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$plannedDays planned',
                      style: const TextStyle(
                        color: Colors.blueAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _buildProjectionRow(
              context,
              'Confirmed (attended)',
              '$confirmedDays days',
              Colors.greenAccent,
            ),
            const SizedBox(height: 8),
            _buildProjectionRow(
              context,
              'Planned (future)',
              '$plannedDays days',
              Colors.blueAccent,
            ),
            const SizedBox(height: 8),
            Divider(color: Theme.of(context).dividerColor),
            const SizedBox(height: 8),
            _buildProjectionRow(
              context,
              'Projected total',
              '$projectedTotal days',
              Theme.of(context).colorScheme.onSurface,
              bold: true,
            ),
            const SizedBox(height: 8),
            _buildProjectionRow(
              context,
              'Year required',
              '$totalRequired days',
              Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: netColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: netColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(netIcon, color: netColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isOnTrack
                          ? 'On track · ${netBalance == 0 ? 'meets requirement exactly' : '$leaveBuffer day${leaveBuffer == 1 ? '' : 's'} buffer — you can skip $leaveBuffer more'}'
                          : 'Shortfall · need ${netBalance.abs()} more day${netBalance.abs() == 1 ? '' : 's'} to meet requirement',
                      style: TextStyle(
                        color: netColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentMonthCard(
    BuildContext context,
    YearlyStatsResult yearlyStats,
    List<DateTime> validPlannedDates,
  ) {
    MonthlyStats? monthStats;
    try {
      monthStats = yearlyStats.monthlyBreakdown.firstWhere(
        (m) => m.month == _focusedDay.month,
      );
    } catch (_) {}

    if (monthStats == null) return const SizedBox.shrink();

    // Cumulative shortfall from Jan through the viewed month: required days
    // minus (attended days + planned days) across that whole span. Planning
    // a day anywhere up to the viewed month pays down this number.
    int requiredToDate = 0;
    int presentToDate = 0;
    for (final m in yearlyStats.monthlyBreakdown) {
      if (m.month <= _focusedDay.month) {
        requiredToDate += m.requiredDays;
        presentToDate += m.presentDays;
      }
    }
    final plannedToDate = validPlannedDates
        .where((d) => d.month <= _focusedDay.month)
        .length;

    final ytdDeficit = requiredToDate - (presentToDate + plannedToDate);
    final isDeficit = ytdDeficit > 0;
    final deficitColor = isDeficit ? AppTheme.dangerColor : Colors.greenAccent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'THIS MONTH (${monthStats.monthName.toUpperCase()})',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 10,
                letterSpacing: 1.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendance',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${monthStats.presentDays}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          TextSpan(
                            text: ' / ${monthStats.requiredDays} required',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Shortfall (YTD)',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isDeficit
                          ? '$ytdDeficit day${ytdDeficit == 1 ? '' : 's'}'
                          : 'None',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: deficitColor,
                      ),
                    ),
                    if (plannedToDate > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$plannedToDate planned applied',
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectionRow(
    BuildContext context,
    String label,
    String value,
    Color valueColor, {
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildLegend(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _legendItem(Colors.greenAccent, 'Attended'),
        _legendItem(Colors.blueAccent, 'Planned'),
        _legendItem(Colors.orangeAccent, 'Holiday'),
        _legendItem(Colors.redAccent.withValues(alpha: 0.7), 'Missed'),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ],
    );
  }
}
