import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../services/logger_service.dart';

class AppLogsScreen extends StatefulWidget {
  const AppLogsScreen({super.key});

  @override
  State<AppLogsScreen> createState() => _AppLogsScreenState();
}

class _AppLogsScreenState extends State<AppLogsScreen> {
  LogType? _selectedFilter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Application Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Logs?'),
                  content: const Text(
                    'Are you sure you want to clear all application logs?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                await LoggerService.instance.clearLogs();
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Logs cleared')));
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          const Divider(height: 1),
          Expanded(child: _buildLogList()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildFilterChip(null, 'All'),
          _buildFilterChip(LogType.general, 'General'),
          _buildFilterChip(LogType.background, 'Background'),
          _buildFilterChip(LogType.system, 'System'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(LogType? type, String label) {
    final isSelected = _selectedFilter == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedFilter = selected ? type : null;
          });
        },
      ),
    );
  }

  Widget _buildLogList() {
    return FutureBuilder(
      future: Hive.openBox<Map<dynamic, dynamic>>('app_logs'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final box = snapshot.data as Box<Map<dynamic, dynamic>>;

        return ValueListenableBuilder(
          valueListenable: box.listenable(),
          builder: (context, Box<Map<dynamic, dynamic>> box, _) {
            if (box.isEmpty) {
              return const Center(child: Text('No application logs found.'));
            }

            final logs = box.values
                .map((json) => LogEntry.fromJson(json))
                .where(
                  (log) =>
                      _selectedFilter == null || log.type == _selectedFilter,
                )
                .toList()
                .reversed
                .toList();

            if (logs.isEmpty) {
              return const Center(
                child: Text('No logs match the selected filter.'),
              );
            }

            return ListView.separated(
              itemCount: logs.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final log = logs[index];
                final isError = log.level == LogLevel.error;
                final isWarning = log.level == LogLevel.warning;

                IconData icon;
                Color iconColor;

                if (isError) {
                  icon = Icons.error_outline;
                  iconColor = Colors.red;
                } else if (isWarning) {
                  icon = Icons.warning_amber_rounded;
                  iconColor = Colors.orange;
                } else {
                  switch (log.type) {
                    case LogType.background:
                      icon = Icons.cloud_sync_outlined;
                      iconColor = Colors.blueGrey;
                      break;
                    case LogType.system:
                      icon = Icons.settings_system_daydream;
                      iconColor = Colors.teal;
                      break;
                    default:
                      icon = Icons.info_outline;
                      iconColor = Colors.blue;
                  }
                }

                return ListTile(
                  leading: Icon(icon, color: iconColor),
                  title: Text(
                    log.message,
                    style: TextStyle(
                      fontSize: 12,
                      color: isError ? Colors.red[700] : null,
                      fontFamily: 'monospace',
                    ),
                  ),
                  subtitle: Text(
                    '${DateFormat('MMM d, h:mm a').format(log.timestamp)} • ${log.type.name.toUpperCase()}',
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
