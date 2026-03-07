import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';

import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

import '../providers/providers.dart';
import '../../data/models/attendance_log.dart';
import '../../logic/stats_calculator.dart';

import '../settings/settings_screen.dart';
import '../summary/summary_screen.dart';

import '../../services/auto_checkin_service.dart';
import '../../services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/admin_service.dart';
import 'widgets/delete_attendance_dialog.dart';
import 'package:native_geofence/native_geofence.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Permission.notification.request();
      await NotificationService.requestPermissions();

      final autoService = ref.read(autoCheckInServiceProvider);
      await autoService.initGeofence();

      // Debug: Log registered geofences to console
      try {
        final registered = await NativeGeofenceManager.instance
            .getRegisteredGeofences();
        debugPrint(
          'DEBUG: Home initialized geofencing. Registered count: ${registered.length}',
        );
        for (var g in registered) {
          debugPrint(
            'DEBUG: Geofence Active: ${g.id} @ ${g.location.latitude}, ${g.location.longitude}',
          );
        }
      } catch (e) {
        debugPrint('DEBUG: Failed to query registered geofences: $e');
      }

      // Sync any pending offline logs from Hive to Firestore
      await ref.read(attendanceServiceProvider)?.syncOfflineLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final attendanceAsync = ref.watch(monthlyAttendanceProvider);
    final holidaysAsync = ref.watch(holidaysStreamProvider);
    final yearlyLogsAsync = ref.watch(
      yearlyAttendanceProvider(_focusedDay.year),
    );
    final user = ref.watch(currentUserProvider);
    final currentYear = _focusedDay.year;
    final globalConfig = ref.watch(globalConfigProvider).value ?? {};
    final calculateAsWorking =
        globalConfig['calculateHolidayAsWorking'] ?? false;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          flexibleSpace: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _buildHeader(user),
            ),
          ),
        ),
      ),
      body: attendanceAsync.when(
        data: (logs) {
          final attendanceLogs = logs.cast<AttendanceLog>();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(monthlyAttendanceProvider);
              ref.invalidate(holidaysStreamProvider);
              await ref.read(monthlyAttendanceProvider.future);
              await ref.read(holidaysStreamProvider.future);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDebugLocationInfo(),
                  const SizedBox(height: 16),
                  // Calendar section (Top)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          holidaysAsync.when(
                            data: (holidays) =>
                                _buildCalendar(attendanceLogs, holidays),
                            loading: () => _buildCalendar(attendanceLogs, []),
                            error: (_, __) =>
                                _buildCalendar(attendanceLogs, []),
                          ),
                          const SizedBox(height: 16),
                          Divider(color: Theme.of(context).dividerColor),
                          const SizedBox(height: 16),
                          // Legend
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
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
                  // Daily Details
                  _buildDailyDetailsCard(attendanceLogs),
                  if (attendanceLogs.any(
                    (log) => isSameDay(log.date, _selectedDay),
                  ))
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
                            ),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
      bottomNavigationBar: attendanceAsync.when(
        data: (logs) {
          final attendanceLogs = logs.cast<AttendanceLog>();
          return Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  offset: const Offset(0, -4),
                  blurRadius: 8,
                ),
              ],
            ),
            child: _buildLogButton(attendanceLogs, holidaysAsync, globalConfig),
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (e, s) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildHeader(dynamic user) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height:
                64, // Explicit height to match the settings button container
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'OfficeLog',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        'Welcome back, ${user?.displayName?.split(' ').first ?? 'User'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[400],
                          fontWeight: FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          height: 64,
          width: 64,
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
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
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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
                          color: Colors.greenAccent.withValues(alpha: 0.5),
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
                'Required',
                '${stats.required}',
                Colors.blueAccent,
                null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                stats.excess > 0 ? 'Excess' : 'Remaining',
                stats.excess > 0 ? '${stats.excess}' : '${stats.pending}',
                stats.excess > 0 ? Colors.greenAccent : Colors.orangeAccent,
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
        const SizedBox(height: 24),
        const Text(
          'MONTHLY TREND (HOURS)',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        _buildTrendChart(logs, displayDate),
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
              value == '1' ? 'Day' : 'Days',
              style: TextStyle(color: Colors.grey[600], fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendChart(List<AttendanceLog> logs, DateTime displayDate) {
    final endOfMonth = DateTime(displayDate.year, displayDate.month + 1, 0);
    final daysInMonth = endOfMonth.day;

    Map<int, double> dailyHours = {};
    for (int i = 1; i <= daysInMonth; i++) {
      dailyHours[i] = 0.0;
    }

    for (var log in logs) {
      if (log.date.year == displayDate.year &&
          log.date.month == displayDate.month) {
        if (log.inTime != null && log.outTime != null) {
          final duration = log.outTime!.difference(log.inTime!);
          dailyHours[log.date.day] = duration.inMinutes / 60.0;
        }
      }
    }

    double maxY = 10.0;
    for (var val in dailyHours.values) {
      if (val > maxY) maxY = val.ceilToDouble();
    }

    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: BarChart(
        BarChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 2,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                getTitlesWidget: (value, meta) {
                  if (value > 0 && value <= daysInMonth) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        value.toInt().toString(),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: dailyHours.entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value,
                  color: AppTheme.primaryColor,
                  width: 8,
                  borderRadius: BorderRadius.circular(2),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1A2230)
                        : Colors.grey.shade200,
                  ),
                ),
              ],
            );
          }).toList(),
          maxY: maxY,
        ),
      ),
    );
  }

  Widget _buildInfoCard(List<AttendanceLog> logs, List<DateTime> holidays) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    final isHoliday = holidays.any((h) => isSameDay(h, today));
    final isLogged = logs.any((log) => isSameDay(log.date, today));

    String title = 'Today is ${DateFormat('MMMM d').format(now)}';
    String message = 'Don\'t forget to log your attendance.';
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
      final sixPM = DateTime(now.year, now.month, now.day, 18, 0);
      if (now.isAfter(sixPM)) {
        title = 'Late Log Alert';
        message =
            'It\'s past 6:00 PM. Please log your attendance as soon as possible.';
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
    Map<String, dynamic> globalConfig,
  ) {
    final allowMockLocation = globalConfig['allowMockLocation'] ?? false;

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
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.54),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // Check for Weekend (Bypassed if allowMockLocation is true)
    if (!allowMockLocation &&
        (_selectedDay.weekday == DateTime.saturday ||
            _selectedDay.weekday == DateTime.sunday)) {
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
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.54),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // Check for Holiday (Bypassed if allowMockLocation is true)
    final holidays = holidaysAsync.value ?? [];
    final isHoliday = holidays.any((h) => isSameDay(h, _selectedDay));
    if (!allowMockLocation && isHoliday) {
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
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.54),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    final dayLogs = logs
        .where((log) => isSameDay(log.date, _selectedDay))
        .toList();
    final isDayLogged = dayLogs.isNotEmpty;
    final todayLog = isDayLogged ? dayLogs.first : null;
    final needsCheckout = isDayLogged && todayLog!.outTime == null;

    Widget? mainButton;
    if (!isDayLogged || needsCheckout) {
      mainButton = Expanded(
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDayLogged
                  ? [Colors.orangeAccent, Colors.orange]
                  : [AppTheme.logGradientStart, AppTheme.logGradientEnd],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color:
                    (isDayLogged
                            ? Colors.orangeAccent
                            : AppTheme.logGradientStart)
                        .withValues(alpha: 0.3),
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
                if (!isDayLogged) {
                  await _handleLogAttendance(logs, null, false);
                } else if (needsCheckout) {
                  await _handleCheckOut(todayLog);
                }
              },
              child: Center(
                child: Text(
                  isDayLogged ? 'Log Out' : 'Log Attendance',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget deleteButton = Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.deleteGradientStart, AppTheme.deleteGradientEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.deleteGradientStart.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _handleDeleteAttendance(logs),
          child: Center(
            child: mainButton == null
                ? const Text(
                    'Delete Attendance',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : const Icon(Icons.delete, color: Colors.white),
          ),
        ),
      ),
    );

    return Row(
      children: [
        if (mainButton != null) mainButton,
        if (isDayLogged) ...[
          if (mainButton != null) const SizedBox(width: 12),
          mainButton == null
              ? Expanded(child: deleteButton)
              : SizedBox(width: 56, child: deleteButton),
        ],
      ],
    );
  }

  Future<void> _handleDeleteAttendance(List<AttendanceLog> logs) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DeleteAttendanceDialog(date: _selectedDay),
    );

    if (confirmed == true) {
      try {
        final logToDelete = logs.firstWhere(
          (log) => isSameDay(log.date, _selectedDay),
        );
        await ref
            .read(attendanceServiceProvider)
            ?.deleteAttendance(logToDelete.id);
        await refreshSmartNotifications(ref);
        if (mounted) {
          AppTheme.showSuccessSnackBar(context, 'Attendance Deleted');
        }
      } catch (e) {
        if (mounted) AppTheme.showErrorSnackBar(context, 'Error: $e');
      }
    }
  }

  Future<void> _handleCheckOut(AttendanceLog todayLog) async {
    final initialTime = isSameDay(_selectedDay, DateTime.now())
        ? TimeOfDay.now()
        : const TimeOfDay(hour: 18, minute: 0);

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: 'Select Log Out Time',
    );

    if (pickedTime == null) return;

    try {
      final checkoutTime = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        pickedTime.hour,
        pickedTime.minute,
      );

      final sessions = List<AttendanceSession>.from(todayLog.sessions);
      if (sessions.isNotEmpty) {
        sessions[sessions.length - 1] = AttendanceSession(
          inTime: sessions.last.inTime,
          outTime: checkoutTime,
        );
      } else {
        sessions.add(
          AttendanceSession(
            inTime: todayLog.inTime ?? todayLog.timestamp,
            outTime: checkoutTime,
          ),
        );
      }

      final updatedLog = AttendanceLog(
        id: todayLog.id,
        userId: todayLog.userId,
        date: todayLog.date,
        timestamp: todayLog.timestamp,
        isSynced: todayLog.isSynced,
        method: todayLog.method,
        inTime: todayLog.inTime,
        outTime: checkoutTime,
        sessions: sessions,
      );

      await ref.read(attendanceServiceProvider)?.updateAttendance(updatedLog);
      await refreshSmartNotifications(ref);
      if (mounted) {
        AppTheme.showSuccessSnackBar(context, 'Log Out Time Updated!');
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showErrorSnackBar(context, 'Error: $e');
      }
    }
  }

  Future<void> _handleLogAttendance(
    List<AttendanceLog> logs,
    AttendanceLog? existingLog,
    bool isEditing,
  ) async {
    final initialTime = isSameDay(_selectedDay, DateTime.now())
        ? TimeOfDay.now()
        : const TimeOfDay(hour: 9, minute: 0);

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: isEditing && existingLog != null
          ? 'Edit Check-In Time'
          : 'Select Check-In Time',
    );

    if (pickedTime == null) return;

    final logTime = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    try {
      if (existingLog != null) {
        final sessions = List<AttendanceSession>.from(existingLog.sessions);
        if (sessions.isNotEmpty) {
          sessions[0] = AttendanceSession(
            inTime: logTime,
            outTime: sessions[0].outTime,
          );
        } else {
          sessions.add(
            AttendanceSession(inTime: logTime, outTime: existingLog.outTime),
          );
        }

        final updatedLog = AttendanceLog(
          id: existingLog.id,
          userId: existingLog.userId,
          date: existingLog.date,
          timestamp: existingLog.timestamp,
          isSynced: existingLog.isSynced,
          method: 'manual', // Overriding method to reflect user intervention
          inTime: logTime,
          outTime: existingLog.outTime,
          sessions: sessions,
        );
        await ref.read(attendanceServiceProvider)?.updateAttendance(updatedLog);
      } else {
        final now = DateTime.now();
        final log = AttendanceLog(
          id: '${ref.read(currentUserProvider)!.uid}_${_selectedDay.year}-${_selectedDay.month}-${_selectedDay.day}',
          userId: ref.read(currentUserProvider)!.uid,
          date: _selectedDay, // The log record date should match selected day
          timestamp: now, // The physical creation time
          method: 'manual',
          inTime: logTime, // The actual Check In Time user selected
          sessions: [AttendanceSession(inTime: logTime)],
        );
        await ref.read(attendanceServiceProvider)?.logAttendance(log);
      }

      await refreshSmartNotifications(ref);
      if (mounted) {
        AppTheme.showSuccessSnackBar(
          context,
          'Attendance ${existingLog != null ? 'Updated' : 'Logged'} for ${DateFormat('MMMM d').format(_selectedDay)}!',
        );
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showErrorSnackBar(context, 'Error: $e');
      }
    }
  }

  Widget _buildDailyDetailsCard(List<AttendanceLog> logs) {
    final dayLogs = logs
        .where((log) => isSameDay(log.date, _selectedDay))
        .toList();
    if (dayLogs.isEmpty) return const SizedBox.shrink();

    final log = dayLogs.first;
    final inTimeTxt = log.sessions.isNotEmpty
        ? DateFormat('hh:mm a').format(log.sessions.first.inTime)
        : (log.inTime != null
              ? DateFormat('hh:mm a').format(log.inTime!)
              : DateFormat('hh:mm a').format(log.timestamp));

    final outTimeTxt =
        log.sessions.isNotEmpty && log.sessions.last.outTime != null
        ? DateFormat('hh:mm a').format(log.sessions.last.outTime!)
        : (log.outTime != null
              ? DateFormat('hh:mm a').format(log.outTime!)
              : '--:--');

    String totalTimeTxt = '--';
    if (log.sessions.isNotEmpty) {
      double totalHrs = 0;
      bool hasActive = false;
      for (var s in log.sessions) {
        totalHrs += s.duration.inMinutes / 60.0;
        if (s.outTime == null && isSameDay(_selectedDay, DateTime.now())) {
          hasActive = true;
          totalHrs += DateTime.now().difference(s.inTime).inMinutes / 60.0;
        }
      }
      final hr = totalHrs.floor();
      final min = ((totalHrs - hr) * 60).round();
      if (hasActive) {
        totalTimeTxt = '${hr}h ${min}m (active)';
      } else {
        totalTimeTxt = '${hr}h ${min}m';
      }
    } else if (log.inTime != null && log.outTime != null) {
      final duration = log.outTime!.difference(log.inTime!);
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      totalTimeTxt = '${hours}h ${minutes}m';
    } else if (log.outTime == null && isSameDay(_selectedDay, DateTime.now())) {
      final startTime = log.inTime ?? log.timestamp;
      final duration = DateTime.now().difference(startTime);
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      totalTimeTxt = '${hours}h ${minutes}m (active)';
    } else if (log.outTime == null && log.inTime != null) {
      totalTimeTxt = 'Pending out-time';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'DAILY DETAILS (${DateFormat('MMM d').format(_selectedDay)})',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                InkWell(
                  onTap: () async {
                    final result = await showDialog<bool>(
                      context: context,
                      builder: (context) => EditDailyDetailsDialog(log: log),
                    );
                    if (result == true && mounted) {
                      AppTheme.showSuccessSnackBar(
                        context,
                        'Times updated successfully.',
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.0,
                      vertical: 2.0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit,
                          size: 14,
                          color: AppTheme.logGradientStart,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'EDIT',
                          style: TextStyle(
                            color: AppTheme.logGradientStart,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTimeColumn('Check-in', inTimeTxt, Colors.greenAccent),
                _buildTimeColumn('Check-out', outTimeTxt, Colors.orangeAccent),
                _buildTimeColumn('Total Time', totalTimeTxt, Colors.blueAccent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
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
            Builder(
              builder: (context) {
                final netBalance = stats.getNetBalanceUpTo(_focusedDay.month);

                if (netBalance == 0) return const SizedBox.shrink();

                final isExcess = netBalance > 0;
                final amount = netBalance.abs();
                final label = isExcess ? 'Excess Alert' : 'Shortfall Alert';
                final word = amount == 1 ? 'day' : 'days';
                final suffix = isExcess ? 'extra' : 'pending';
                final icon = isExcess
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded;
                final color = isExcess
                    ? Colors.greenAccent
                    : AppTheme.dangerColor;
                final bgColor = isExcess
                    ? color.withValues(alpha: 0.1)
                    : (Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.shortfallBgDark
                          : AppTheme.shortfallBgLight);

                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: isExcess
                          ? Border.all(color: color.withValues(alpha: 0.2))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: color, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '$label: $amount $word $suffix',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress > 1.0 ? 1.0 : progress,
                minHeight: 8,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1A2230)
                    : Colors.grey.shade200,
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

  Widget _buildDebugLocationInfo() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final allowMockLocation =
        prefs.getBool('allowMockLocation') ??
        ref.watch(globalConfigProvider).value?['allowMockLocation'] == true;

    if (!allowMockLocation) return const SizedBox.shrink();

    final userProfile = ref.watch(userProfileProvider).value;
    if (userProfile == null) return const SizedBox.shrink();

    final officeLat = userProfile.officeLat;
    final officeLng = userProfile.officeLng;

    return StreamBuilder<Position>(
      stream: Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      ),
      builder: (context, snapshot) {
        String distanceText = 'Calculating distance...';
        bool isMockedText = false;
        if (snapshot.hasData && officeLat != null && officeLng != null) {
          final pos = snapshot.data!;
          final distance = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            officeLat,
            officeLng,
          );
          distanceText = '${distance.toInt()}m away';
          isMockedText = pos.isMocked;
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '📍 OFFICE TARGET',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                  Row(
                    children: [
                      if (ref
                              .watch(globalConfigProvider)
                              .value?['allowMockLocation'] ==
                          true)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'DEBUG MODE',
                            style: TextStyle(fontSize: 8, color: Colors.green),
                          ),
                        ),
                      if (isMockedText)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'MOCKED',
                            style: TextStyle(fontSize: 8, color: Colors.orange),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$officeLat, $officeLng',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Divider(height: 12, color: Colors.redAccent),
              Text(
                'DISTANCE: $distanceText',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class EditDailyDetailsDialog extends ConsumerStatefulWidget {
  final AttendanceLog log;
  const EditDailyDetailsDialog({super.key, required this.log});

  @override
  ConsumerState<EditDailyDetailsDialog> createState() =>
      _EditDailyDetailsDialogState();
}

class _EditDailyDetailsDialogState
    extends ConsumerState<EditDailyDetailsDialog> {
  late List<AttendanceSession> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = List<AttendanceSession>.from(widget.log.sessions);
    if (_sessions.isEmpty) {
      _sessions.add(
        AttendanceSession(inTime: widget.log.inTime ?? widget.log.timestamp),
      );
    }
  }

  Future<void> _pickTime(int index, bool isInTime) async {
    final session = _sessions[index];
    final initialTime = isInTime
        ? TimeOfDay.fromDateTime(session.inTime)
        : (session.outTime != null
              ? TimeOfDay.fromDateTime(session.outTime!)
              : TimeOfDay.now());

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: isInTime ? 'Select Login Time' : 'Select Log Out Time',
    );

    if (pickedTime != null) {
      final baseDate = widget.log.date;
      final newDateTime = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      setState(() {
        if (isInTime) {
          _sessions[index] = AttendanceSession(
            inTime: newDateTime,
            outTime: session.outTime,
          );
        } else {
          _sessions[index] = AttendanceSession(
            inTime: session.inTime,
            outTime: newDateTime,
          );
        }
      });
    }
  }

  void _addSession() {
    setState(() {
      _sessions.add(
        AttendanceSession(
          inTime: DateTime(
            widget.log.date.year,
            widget.log.date.month,
            widget.log.date.day,
            DateTime.now().hour,
            DateTime.now().minute,
          ),
        ),
      );
    });
  }

  void _removeSession(int index) {
    setState(() {
      _sessions.removeAt(index);
    });
  }

  Future<void> _save() async {
    try {
      if (_sessions.isEmpty) {
        AppTheme.showErrorSnackBar(
          context,
          'You must have at least one session.',
        );
        return;
      }

      for (var i = 0; i < _sessions.length; i++) {
        final session = _sessions[i];
        if (session.outTime != null &&
            session.outTime!.isBefore(session.inTime)) {
          AppTheme.showErrorSnackBar(
            context,
            'Session ${i + 1}: Check-out time cannot be earlier than check-in time.',
          );
          return;
        }
      }

      // Sort sessions by inTime
      _sessions.sort((a, b) => a.inTime.compareTo(b.inTime));

      DateTime? overallInTime = _sessions.first.inTime;
      DateTime? overallOutTime = _sessions.last.outTime;

      final updatedLog = AttendanceLog(
        id: widget.log.id,
        userId: widget.log.userId,
        date: widget.log.date,
        timestamp: widget.log.timestamp,
        isSynced: widget.log.isSynced,
        method: 'manual', // Overriding method to reflect user intervention
        inTime: overallInTime,
        outTime: overallOutTime,
        sessions: _sessions,
      );
      await ref.read(attendanceServiceProvider)?.updateAttendance(updatedLog);
      await refreshSmartNotifications(ref);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showErrorSnackBar(context, 'Error: $e');
      }
    }
  }

  Widget _buildSessionTile(int index, AttendanceSession session) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Session ${index + 1}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (index > 0) // Cannot delete the very first session
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppTheme.dangerColor,
                    size: 20,
                  ),
                  onPressed: () => _removeSession(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTimePickerBox(
                  title: 'In Time',
                  time: session.inTime,
                  onTap: () => _pickTime(index, true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTimePickerBox(
                  title: 'Out Time',
                  time: session.outTime,
                  onTap: () => _pickTime(index, false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimePickerBox({
    required String title,
    required DateTime? time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  time != null ? DateFormat('hh:mm a').format(time) : '--:--',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(
                  Icons.edit,
                  size: 14,
                  color: AppTheme.logGradientStart.withValues(alpha: 0.7),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine height based on number of sessions, up to a max
    final double maxDialogHeight = MediaQuery.of(context).size.height * 0.7;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: BoxConstraints(maxHeight: maxDialogHeight),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.logGradientStart.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.edit_calendar,
                color: AppTheme.logGradientStart,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            // Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Edit Sessions',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addSession,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.logGradientStart,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Content List
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _sessions.length,
                itemBuilder: (context, index) {
                  return _buildSessionTile(index, _sessions[index]);
                },
              ),
            ),
            const SizedBox(height: 24),
            // Save Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.logGradientStart,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Save Changes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Cancel Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(context).dividerColor,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
