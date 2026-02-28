import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../logic/stats_calculator.dart';
import '../../data/models/attendance_log.dart';
import '../providers/providers.dart';
import '../../services/admin_service.dart';

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Determine current year. You might want to allow changing this.
    final currentYear = ref.watch(summaryYearProvider);
    final yearlyLogsAsync = ref.watch(yearlyAttendanceProvider(currentYear));
    final holidaysAsync = ref.watch(holidaysStreamProvider);
    final globalConfig = ref.watch(globalConfigProvider).value ?? {};
    final calculateAsWorking =
        globalConfig['calculateHolidayAsWorking'] ?? false;

    return Scaffold(
      backgroundColor: Theme.of(
        context,
      ).scaffoldBackgroundColor, // Dark Navy Background
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
          'Attendance Insights',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        centerTitle: false,
        actions: [
          PopupMenuButton<int>(
            initialValue: currentYear,
            offset: const Offset(0, 40),
            color: Theme.of(context).cardTheme.color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    currentYear.toString(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      fontFamily: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.fontFamily,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Theme.of(context).primaryColor,
                    size: 20,
                  ),
                ],
              ),
            ),
            onSelected: (int newValue) {
              ref.read(summaryYearProvider.notifier).update(newValue);
            },
            itemBuilder: (context) => [
              for (int year = 2025; year <= DateTime.now().year; year++)
                PopupMenuItem(
                  value: year,
                  child: Text(
                    year.toString(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: yearlyLogsAsync.when(
        data: (logsData) {
          final logs = logsData.cast<AttendanceLog>();

          return holidaysAsync.when(
            data: (holidays) {
              // Calculate Yearly Stats
              final stats = YearlyCalculator.calculateYearlyStats(
                year: currentYear,
                logs: logs,
                holidays: holidays,
                calculateHolidayAsWorking: calculateAsWorking,
              );

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(yearlyAttendanceProvider(currentYear));
                  ref.invalidate(holidaysStreamProvider);
                  await ref.read(yearlyAttendanceProvider(currentYear).future);
                  await ref.read(holidaysStreamProvider.future);
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (currentYear == DateTime.now().year) ...[
                        // Current Month Card
                        _buildCurrentMonthCard(context, stats, currentYear),
                        const SizedBox(height: 24),
                      ],

                      // Overall Highlights (YTD)
                      const Text(
                        'OVERALL HIGHLIGHTS (YTD)',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildHighlightsGrid(context, stats),
                      const SizedBox(height: 24),

                      // Quarterly Performance
                      const Text(
                        'QUARTERLY PERFORMANCE',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildQuarterlyPerformance(
                        context,
                        stats.quarterlyPerformance,
                      ),
                      const SizedBox(height: 24),

                      // Monthly Attendance Trend (Chart)
                      const Text(
                        'MONTHLY ATTENDANCE TREND',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildAttendanceChart(
                        context,
                        ref,
                        stats.monthlyBreakdown,
                      ),
                      const SizedBox(height: 24),

                      // Monthly Breakdown (List)
                      const Text(
                        'MONTHLY BREAKDOWN',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildMonthlyBreakdownList(
                        context,
                        ref,
                        stats.monthlyBreakdown,
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(
              child: Text(
                'Error: $err',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text(
            'Error loading logs: $err',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentMonthCard(
    BuildContext context,
    YearlyStatsResult stats,
    int currentYear,
  ) {
    // Find current month stats
    final now = DateTime.now();
    final currentMonthStats = stats.monthlyBreakdown.firstWhere(
      (m) => m.month == now.month,
      orElse: () => MonthlyStats(
        month: now.month,
        monthName: now.monthName,
        totalDays: 0,
        presentDays: 0,
        requiredDays: 0,
        holidayDays: 0,
        attendancePercentage: 0,
      ),
    );

    int leaves = currentMonthStats.totalDays - currentMonthStats.presentDays;
    if (leaves < 0) leaves = 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CURRENT MONTH',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${currentMonthStats.monthName} $currentYear',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1A2C42)
                        : AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${currentMonthStats.attendancePercentage.toStringAsFixed(0)}% Attendance',
                    style: const TextStyle(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatColumn(
                  context,
                  'Present',
                  '${currentMonthStats.presentDays} Days',
                  AppTheme.primaryColor,
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: Theme.of(context).dividerColor,
                ),
                _buildStatColumn(
                  context,
                  'Total Days',
                  '${currentMonthStats.totalDays} Days',
                  Theme.of(context).colorScheme.onSurface,
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: Theme.of(context).dividerColor,
                ),
                _buildStatColumn(
                  context,
                  'Required',
                  '${currentMonthStats.requiredDays} Days',
                  Theme.of(context).colorScheme.onSurface,
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: currentMonthStats.attendancePercentage / 100,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1A2230)
                    : Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.primaryColor,
                ),
                minHeight: 8,
              ),
            ),
            if (stats.gettotalShortfallUpTo(
                  currentYear < DateTime.now().year ? 12 : DateTime.now().month,
                ) >
                0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.dangerColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.dangerColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.dangerColor,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Yearly Shortfall: ${stats.gettotalShortfallUpTo(currentYear < DateTime.now().year ? 12 : DateTime.now().month)} ${stats.gettotalShortfallUpTo(currentYear < DateTime.now().year ? 12 : DateTime.now().month) == 1 ? "day" : "days"}',
                      style: const TextStyle(
                        color: AppTheme.dangerColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (stats.gettotalExcessUpTo(
                  currentYear < DateTime.now().year ? 12 : DateTime.now().month,
                ) >
                0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Colors.greenAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Yearly Excess: ${stats.gettotalExcessUpTo(currentYear < DateTime.now().year ? 12 : DateTime.now().month)} ${stats.gettotalExcessUpTo(currentYear < DateTime.now().year ? 12 : DateTime.now().month) == 1 ? "day" : "days"} extra',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(
    BuildContext context,
    String label,
    String value,
    Color valueColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildHighlightsGrid(BuildContext context, YearlyStatsResult stats) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6, // Wider cards
      children: [
        _buildHighlightCard(
          context,
          'YTD Present',
          '${stats.ytdPresent} days',
          AppTheme.primaryColor,
        ),
        _buildHighlightCard(
          context,
          'Best Month',
          '${stats.bestMonthName} ${stats.bestMonthPercentage.toStringAsFixed(0)}%',
          Theme.of(context).colorScheme.onSurface,
        ),
        _buildHighlightCard(
          context,
          'Total Required',
          '${stats.totalYearlyRequired} days',
          Theme.of(context).colorScheme.onSurface,
        ),
        _buildHighlightCard(
          context,
          'Overall Attendance',
          '${stats.overallAttendance.toStringAsFixed(0)}%',
          Theme.of(context).colorScheme.onSurface,
        ),
      ],
    );
  }

  Widget _buildHighlightCard(
    BuildContext context,
    String title,
    String value,
    Color valueColor, {
    Color? suffixColor,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (suffixColor != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    'Days',
                    style: TextStyle(color: suffixColor, fontSize: 12),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuarterlyPerformance(
    BuildContext context,
    Map<int, double> quarterlyData,
  ) {
    return Row(
      children: [
        for (int q = 1; q <= 4; q++)
          Expanded(
            child: Container(
              margin: EdgeInsets.only(right: q == 4 ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                children: [
                  Text(
                    'Q$q',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${quarterlyData[q]?.toStringAsFixed(0)}%',
                    style: TextStyle(
                      // Dim color if 0 (likely future)
                      color: (quarterlyData[q] ?? 0) > 0
                          ? AppTheme.primaryColor
                          : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAttendanceChart(
    BuildContext context,
    WidgetRef ref,
    List<MonthlyStats> data,
  ) {
    final currentYear = ref.watch(summaryYearProvider);
    final now = DateTime.now();

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
                reservedSize: 35,
                interval: 20,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toInt()}%',
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
                getTitlesWidget: (value, meta) {
                  if (value >= 0 && value < 12) {
                    final month = DateTime(2023, value.toInt() + 1, 1);
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        month.monthAbbr.toUpperCase(),
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
          barGroups: data.map((m) {
            // Determine if the month is in the future
            bool isFuture = DateTime(currentYear, m.month, 1).isAfter(now);

            Color barColor;
            if (isFuture) {
              barColor = Colors.grey.withValues(alpha: 0.5);
            } else if (m.requiredDays > 0 && m.presentDays >= m.requiredDays) {
              barColor = AppTheme.primaryColor; // Green/Blue success color
            } else if (m.requiredDays > 0) {
              barColor = Colors.orangeAccent;
            } else {
              barColor = Colors.grey.withValues(alpha: 0.5);
            }

            return BarChartGroupData(
              x: m.month - 1, // 0-based index
              barRods: [
                BarChartRodData(
                  toY: m.attendancePercentage,
                  color: barColor,
                  width: 12,
                  borderRadius: BorderRadius.circular(2),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: 100, // Max 100%
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1A2230)
                        : Colors.grey.shade200,
                  ),
                ),
              ],
            );
          }).toList(),
          maxY: data.isEmpty
              ? 100
              : (data
                            .map((e) => e.attendancePercentage)
                            .reduce((a, b) => a > b ? a : b) >
                        100
                    ? (data
                                      .map((e) => e.attendancePercentage)
                                      .reduce((a, b) => a > b ? a : b) /
                                  10)
                              .ceil() *
                          10.0
                    : 100),
        ),
      ),
    );
  }

  Widget _buildMonthlyBreakdownList(
    BuildContext context,
    WidgetRef ref,
    List<MonthlyStats> data,
  ) {
    // Show in chronological order
    final listData = data;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: const [
                Expanded(
                  flex: 4,
                  child: Text(
                    'MONTH',
                    style: TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'TOTAL',
                    style: TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'REQUIRED',
                    style: TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'PRESENT',
                    style: TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text(
                      'STATUS',
                      style: TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: Theme.of(context).dividerColor, height: 1),
          // Rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: listData.length,
            separatorBuilder: (_, __) =>
                Divider(color: Theme.of(context).dividerColor, height: 1),
            itemBuilder: (context, index) {
              final item = listData[index];

              // Determine status icon
              IconData statusIcon = Icons.circle_outlined;
              Color statusColor = Colors.grey;

              // Simple logic for checking future
              bool isFuture = DateTime(
                ref.read(summaryYearProvider),
                item.month,
                1,
              ).isAfter(DateTime.now());

              if (!isFuture && item.requiredDays > 0) {
                if (item.presentDays >= item.requiredDays) {
                  // Met Requirement
                  statusIcon = Icons.check_circle;
                  statusColor = AppTheme.primaryColor;
                } else {
                  statusIcon = Icons.info; // Warning
                  statusColor = Colors.orange;
                }
              } else {
                // Future or no required days
                statusIcon = Icons.access_time_filled;
                statusColor = Colors.grey.withValues(alpha: 0.5);
              }

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        item.monthName,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Text(
                          '${item.totalDays}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Text(
                          '${item.requiredDays}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Text(
                          isFuture ? '-' : '${item.presentDays}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Icon(statusIcon, color: statusColor, size: 20),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
