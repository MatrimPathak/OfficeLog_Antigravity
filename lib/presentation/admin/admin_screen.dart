import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import 'widgets/add_holiday_dialog.dart';
import 'widgets/add_office_location_dialog.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(
        context,
      ).scaffoldBackgroundColor, // Dark Navy Background
      appBar: AppBar(
        backgroundColor: Theme.of(
          context,
        ).scaffoldBackgroundColor, // Dark Navy Background
        title: const Text('Admin Panel'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.onSurface,
          unselectedLabelColor: Theme.of(
            context,
          ).colorScheme.onSurface.withOpacity(0.6),
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(text: 'Holidays'),
            Tab(text: 'Locations'),
            Tab(text: 'Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [HolidaysTab(), LocationsTab(), GlobalSettingsTab()],
      ),
    );
  }
}

class HolidaysTab extends ConsumerWidget {
  const HolidaysTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holidaysAsync = ref.watch(adminServiceProvider).getHolidaysStream();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: holidaysAsync,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final holidays = List<Map<String, dynamic>>.from(snapshot.data ?? []);
        holidays.sort((a, b) {
          final dateA = (a['date'] as dynamic).toDate() as DateTime;
          final dateB = (b['date'] as dynamic).toDate() as DateTime;
          return dateA.compareTo(dateB); // Accending order
        });

        return Stack(
          children: [
            ListView.builder(
              itemCount: holidays.length,
              itemBuilder: (context, index) {
                final holiday = holidays[index];
                final date = (holiday['date'] as dynamic).toDate();

                final List<String>? officeLocs =
                    (holiday['officeLocations'] as List<dynamic>?)
                        ?.cast<String>();
                final String officeLocString =
                    officeLocs != null && officeLocs.isNotEmpty
                    ? officeLocs.join(', ')
                    : holiday['officeLocation'] ?? 'All Offices';

                final bool isRecurring = holiday['isRecurring'] ?? false;

                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color, // Lighter card bg
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: ListTile(
                    onTap: () => _showAddHolidayDialog(context, ref, holiday),
                    isThreeLine: true,
                    title: Text(
                      holiday['name'],
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat.yMMMd().format(date),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        Text(
                          isRecurring
                              ? '$officeLocString • Recurring'
                              : officeLocString,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete,
                        color: AppTheme.dangerColor,
                      ),
                      onPressed: () {
                        ref
                            .read(adminServiceProvider)
                            .deleteHoliday(holiday['id']);
                      },
                    ),
                  ),
                );
              },
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton(
                onPressed: () => _showAddHolidayDialog(context, ref, null),
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAddHolidayDialog(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? holiday,
  ) async {
    showDialog(
      context: context,
      builder: (context) => AddHolidayDialog(ref: ref, holiday: holiday),
    );
  }
}

class LocationsTab extends ConsumerWidget {
  const LocationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(officeLocationsProvider);

    return locationsAsync.when(
      data: (locations) {
        return Stack(
          children: [
            ListView.builder(
              itemCount: locations.length,
              itemBuilder: (context, index) {
                final loc = locations[index];
                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color, // Lighter card bg
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: ListTile(
                    title: Text(
                      loc.name,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      '${loc.address}\nLat: ${loc.latitude}, Lng: ${loc.longitude}',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete,
                        color: AppTheme.dangerColor,
                      ),
                      onPressed: () {
                        ref
                            .read(adminServiceProvider)
                            .deleteOfficeLocation(loc.id);
                      },
                    ),
                  ),
                );
              },
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton(
                onPressed: () => _showAddLocationDialog(context, ref),
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error: $e')),
    );
  }

  void _showAddLocationDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AddOfficeLocationDialog(ref: ref),
    );
  }
}

class GlobalSettingsTab extends ConsumerWidget {
  const GlobalSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(globalConfigProvider);

    return configAsync.when(
      data: (config) {
        final calculateAsWorking = config['calculateHolidayAsWorking'] ?? false;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: SwitchListTile(
                title: Text(
                  'Calculate holiday as working',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  'When enabled, holidays will be treated as regular working days in statistics calculation.',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                value: calculateAsWorking,
                onChanged: (value) {
                  ref.read(adminServiceProvider).updateGlobalConfig({
                    'calculateHolidayAsWorking': value,
                  });
                },
                activeThumbColor: AppTheme.primaryColor,
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error: $e')),
    );
  }
}
