import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

import '../providers/providers.dart';
import '../../data/models/attendance_log.dart';
import '../../logic/stats_calculator.dart';
import '../../core/services/app_icon_service.dart';
import '../settings/settings_screen.dart';
import '../summary/summary_screen.dart';

import '../../services/auto_checkin_service.dart';
import '../../services/notification_service.dart';

import '../../services/admin_service.dart';
import 'widgets/delete_attendance_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Trigger auto check-in check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(autoCheckInServiceProvider).checkAndLogAttendance();
    });
  }

  @override
  Widget build(BuildContext context) {
    final attendanceAsync = ref.watch(monthlyAttendanceProvider);
    final holidaysAsync = ref.watch(holidaysStreamProvider);
    final yearlyLogsAsync = ref.watch(yearlyAttendanceProvider);
    final user = ref.watch(currentUserProvider);
    final currentYear = ref.watch(currentYearProvider);
    final globalConfig = ref.watch(globalConfigProvider).value ?? {};
    final calculateAsWorking =
        globalConfig['calculateHolidayAsWorking'] ?? false;

    // Listen for attendance updates to refresh the app icon
    ref.listen(monthlyAttendanceProvider, (previous, next) {
      if (next.hasValue) {
        AppIconService.updateAppIcon(ref);
      }
    });

    // Also listen to the toggle to update immediately
    ref.listen(dynamicIconEnabledProvider, (previous, next) {
      AppIconService.updateAppIcon(ref);
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: attendanceAsync.when(
        data: (logs) {
          final attendanceLogs = logs.cast<AttendanceLog>();

          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(monthlyAttendanceProvider);
                    ref.invalidate(holidaysStreamProvider);
                    await ref.read(monthlyAttendanceProvider.future);
                    await ref.read(holidaysStreamProvider.future);
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(user),
                        const SizedBox(height: 24),
                        // Calendar section (Top)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                holidaysAsync.when(
                                  data: (holidays) =>
                                      _buildCalendar(attendanceLogs, holidays),
                                  loading: () =>
                                      _buildCalendar(attendanceLogs, []),
                                  error: (_, __) =>
                                      _buildCalendar(attendanceLogs, []),
                                ),
                                const SizedBox(height: 16),
                                Divider(color: Theme.of(context).dividerColor),
                                const SizedBox(height: 16),
                                // Legend
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildLegendItem(
                                      context,
                                      'WORK DAY',
                                      Colors.blueAccent,
                                    ),
                                    _buildLegendItem(
                                      context,
                                      'HOLIDAY',
                                      Colors.orangeAccent,
                                    ),
                                    _buildLegendItem(
                                      context,
                                      'ATTENDED',
                                      Colors.greenAccent,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Stats Section
                        _buildStatisticsGrid(
                          attendanceLogs,
                          holidaysAsync.value ?? [],
                          calculateAsWorking,
                          _focusedDay,
                        ),
                        const SizedBox(height: 24),

                        // Info Card
                        yearlyLogsAsync.when(
                          data: (yearlyLogs) {
                            final stats = YearlyCalculator.calculateYearlyStats(
                              year: currentYear,
                              logs: yearlyLogs.cast<AttendanceLog>(),
                              holidays: holidaysAsync.value ?? [],
                              calculateHolidayAsWorking: calculateAsWorking,
                            );
                            return Column(
                              children: [
                                _buildProgressCard(context, stats),
                                const SizedBox(height: 24),
                                if (isSameDay(_selectedDay, DateTime.now()))
                                  _buildInfoCard(
                                    attendanceLogs,
                                    holidaysAsync.value ?? [],
                                    stats.totalShortfall,
                                  ),
                              ],
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 80), // Pad for button if needed
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      offset: const Offset(0, -4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: _buildLogButton(attendanceLogs, holidaysAsync),
                ),
              ),
            ],
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildHeader(dynamic user) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              children: [
                if (user?.photoURL != null)
                  CircleAvatar(
                    backgroundImage: NetworkImage(user!.photoURL!),
                    radius: 20,
                  )
                else
                  CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor,
                    radius: 20,
                    child: Text(
                      user?.displayName?.substring(0, 1).toUpperCase() ?? 'U',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OfficeLog',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Welcome back, ${user?.displayName?.split(' ').first ?? 'User'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          height: 64, // Match height of user card approximately
          width: 64,
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color, // Lighter card bg
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            icon: Icon(
              Icons.settings,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(BuildContext context, String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCalendar(List<AttendanceLog> logs, List<DateTime> holidays) {
    return TableCalendar(
      key: ValueKey(
        _calendarFormat,
      ), // Force rebuild on format change (and generally)
      firstDay: DateTime.utc(2024, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: _focusedDay,
      calendarFormat: _calendarFormat,
      startingDayOfWeek: StartingDayOfWeek.sunday, // Set start day to Sunday
      daysOfWeekHeight: 32,
      availableCalendarFormats: const {CalendarFormat.month: 'Month'},
      availableGestures:
          AvailableGestures.horizontalSwipe, // Allow vertical scroll in parent
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
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
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
        ),
        // Decorations handled by builders to avoid tween errors
        markerDecoration: const BoxDecoration(color: Colors.transparent),
      ),
      selectedDayPredicate: (day) {
        return isSameDay(_selectedDay, day);
      },
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
      },
      onFormatChanged: (format) {
        setState(() {
          _calendarFormat = format;
        });
      },
      onPageChanged: (focusedDay) {
        // Calculate new selected day preserving day of month
        final newMonth = focusedDay.month;
        final newYear = focusedDay.year;
        final oldDay = _selectedDay.day;

        // standard days in month check
        int maxDays = DateTime(newYear, newMonth + 1, 0).day;
        int newDay = oldDay > maxDays ? maxDays : oldDay;

        final newSelectedDay = DateTime(newYear, newMonth, newDay);

        setState(() {
          _focusedDay = focusedDay;
          _selectedDay = newSelectedDay;
        });
        // Update the month provider so stats and logs follow the calendar
        ref.read(currentMonthProvider.notifier).update(focusedDay);
      },
      eventLoader: (day) {
        final dayLogs = logs.where((log) => isSameDay(log.date, day)).toList();
        final isHoliday = holidays.any((h) => isSameDay(h, day));
        if (isHoliday) {
          // Use a special string or object to represent holiday
          return [...dayLogs, 'HOLIDAY_EVENT'];
        }
        return dayLogs;
      },
      calendarBuilders: CalendarBuilders(
        selectedBuilder: (context, day, focusedDay) {
          return Container(
            margin: const EdgeInsets.all(6.0),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.transparent,
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.onSurface,
                width: 2.0,
              ),
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          );
        },
        todayBuilder: (context, day, focusedDay) {
          return Container(
            margin: const EdgeInsets.all(6.0),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.transparent,
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blueAccent),
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          );
        },
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return null;

          final hasAttendance = events.any((e) => e is AttendanceLog);
          final hasHoliday = events.contains('HOLIDAY_EVENT');

          return Positioned(
            bottom: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasHoliday)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: const BoxDecoration(
                      color: Colors.orangeAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                if (hasAttendance)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatisticsGrid(
    List<AttendanceLog> logs,
    List<DateTime> holidays,
    bool calculateHolidayAsWorking,
    DateTime displayDate,
  ) {
    // Current month range based on visible calendar month
    final startOfMonth = DateTime(displayDate.year, displayDate.month, 1);
    final endOfMonth = DateTime(displayDate.year, displayDate.month + 1, 0);

    final stats = StatsCalculator.calculateStats(
      start: startOfMonth,
      end: endOfMonth,
      logs: logs,
      holidays: holidays,
      calculateHolidayAsWorking: calculateHolidayAsWorking,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'STATISTICS',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SummaryScreen()),
                );
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'View Summary',
                style: TextStyle(
                  color: Colors.blueAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                context,
                'Working',
                '${stats.required}',
                Colors.blueAccent,
                null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                'Remaining',
                '${stats.pending}',
                Colors.orangeAccent,
                null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                'Present',
                '${stats.logged}',
                Colors.greenAccent,
                null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    Color valueColor,
    IconData? icon,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Days',
              style: TextStyle(color: Colors.grey[600], fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    List<AttendanceLog> logs,
    List<DateTime> holidays,
    int totalShortfall,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    final isHoliday = holidays.any((h) => isSameDay(h, today));
    final isLogged = logs.any((log) => isSameDay(log.date, today));

    String title = 'Today is ${DateFormat('MMMM d').format(now)}';
    String message = 'Don\'t forget to log your attendance before 10:00 AM.';
    IconData icon = Icons.info_outline;
    Color iconBgColor = Colors.blueAccent;

    if (isHoliday) {
      title = 'Public Holiday';
      message = 'Enjoy your holiday! No attendance logging required today.';
      icon = Icons.celebration;
      iconBgColor = Colors.orangeAccent;
    } else if (isWeekend) {
      title = 'It\'s the Weekend';
      message = 'Have a great weekend! See you on Monday.';
      icon = Icons.weekend;
      iconBgColor = Colors.purpleAccent;
    } else if (isLogged) {
      title = 'Attendance Logged';
      message = 'Great job! Your attendance for today is already recorded.';
      icon = Icons.check_circle_outline;
      iconBgColor = Colors.greenAccent;
    } else {
      final tenAM = DateTime(now.year, now.month, now.day, 10, 0);
      if (now.isAfter(tenAM)) {
        title = 'Late Log Alert';
        message =
            'It\'s past 10:00 AM. Please log your attendance as soon as possible.';
        icon = Icons.warning_amber_rounded;
        iconBgColor = Colors.redAccent;
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  if (totalShortfall > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppTheme.shortfallBgDark
                            : AppTheme.shortfallBgLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: AppTheme.dangerColor,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Shortfall Alert: $totalShortfall days pending',
                            style: const TextStyle(
                              color: AppTheme.dangerColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogButton(
    List<AttendanceLog> logs,
    AsyncValue<List<DateTime>> holidaysAsync,
  ) {
    // Check if the selected day is in the future
    final now = DateTime.now();
    // Compare dates only (ignoring time)
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    final isFuture = selected.isAfter(today);

    if (isFuture) {
      return Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Center(
          child: Text(
            'Cannot log future attendance',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // Check for Weekend
    // Saturday=6, Sunday=7
    if (_selectedDay.weekday == DateTime.saturday ||
        _selectedDay.weekday == DateTime.sunday) {
      return Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Center(
          child: Text(
            'Cannot log on Weekends',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // Check for Holiday
    final holidays = holidaysAsync.value ?? [];
    final isHoliday = holidays.any((h) => isSameDay(h, _selectedDay));
    if (isHoliday) {
      return Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Center(
          child: Text(
            'Cannot log on Holidays',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    final isDayLogged = logs.any((log) => isSameDay(log.date, _selectedDay));

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDayLogged
              ? [AppTheme.deleteGradientStart, AppTheme.deleteGradientEnd]
              : [AppTheme.logGradientStart, AppTheme.logGradientEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color:
                (isDayLogged
                        ? AppTheme.deleteGradientStart
                        : AppTheme.logGradientStart)
                    .withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            if (isDayLogged) {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) =>
                    DeleteAttendanceDialog(date: _selectedDay),
              );

              if (confirmed == true) {
                try {
                  final logToDelete = logs.firstWhere(
                    (log) => isSameDay(log.date, _selectedDay),
                  );
                  await ref
                      .read(attendanceServiceProvider)
                      ?.deleteAttendance(logToDelete.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Attendance Deleted')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              }
            } else {
              // Log Attendance
              final logTime = isSameDay(_selectedDay, DateTime.now())
                  ? DateTime.now()
                  : DateTime(
                      _selectedDay.year,
                      _selectedDay.month,
                      _selectedDay.day,
                      9,
                      0,
                    );

              final log = AttendanceLog(
                id: '${ref.read(currentUserProvider)!.uid}_${logTime.millisecondsSinceEpoch}',
                userId: ref.read(currentUserProvider)!.uid,
                date: logTime,
                timestamp: logTime,
                method: 'manual',
              );

              try {
                await ref.read(attendanceServiceProvider)?.logAttendance(log);
                // Cancel today's notification if we just logged for today
                if (isSameDay(logTime, DateTime.now())) {
                  NotificationService.cancelDailyNotification();
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Attendance Logged for ${DateFormat('MMMM d').format(_selectedDay)}!',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }
          },
          child: Center(
            child: Text(
              isDayLogged ? 'Delete Attendance' : 'Log Attendance',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressCard(BuildContext context, YearlyStatsResult stats) {
    // Determine the current month stats from the breakdown
    // yearlyLogsAsync gives us the full year, so stats.monthlyBreakdown has it.
    // We want the stats for the CURRENT visible month in the calendar?
    // Or strictly the actual current month?
    // User request: "Required progress which is the total number of required days to the number of days attended"
    // Usually progress is monthly.

    // Let's use the focused month from the calendar to find the right stats
    MonthlyStats? currentMonthStats;
    try {
      currentMonthStats = stats.monthlyBreakdown.firstWhere(
        (m) => m.month == _focusedDay.month,
      );
    } catch (_) {}

    if (currentMonthStats == null) return const SizedBox.shrink();

    final double progress = currentMonthStats.requiredDays > 0
        ? (currentMonthStats.presentDays / currentMonthStats.requiredDays)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PROGRESS (${currentMonthStats.monthName})',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
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
                      'Total Attendance',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${currentMonthStats.presentDays}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          TextSpan(
                            text: ' / ${currentMonthStats.totalDays}',
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
                      'Required Progress',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${currentMonthStats.presentDays}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          TextSpan(
                            text: ' / ${currentMonthStats.requiredDays}',
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
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress > 1.0 ? 1.0 : progress,
                minHeight: 8,
                backgroundColor: Theme.of(context).canvasColor,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1.0 ? Colors.greenAccent : Colors.blueAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
