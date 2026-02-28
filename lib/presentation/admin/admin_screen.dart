import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../data/models/holiday.dart';
import '../providers/providers.dart';
import 'widgets/add_holiday_dialog.dart';
import 'widgets/add_office_location_dialog.dart';
import '../settings/background_logs_screen.dart';

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
    _tabController = TabController(length: 5, vsync: this);
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
          ).colorScheme.onSurface.withValues(alpha: 0.6),
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(text: 'Users'),
            Tab(text: 'Holidays'),
            Tab(text: 'Locations'),
            Tab(text: 'Settings'),
            Tab(text: 'Feedback'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          UsersTab(),
          HolidaysTab(),
          LocationsTab(),
          GlobalSettingsTab(),
          FeedbackTab(),
        ],
      ),
    );
  }
}

class HolidaysTab extends ConsumerWidget {
  const HolidaysTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holidaysAsync = ref.watch(sortedHolidaysProvider);

    return holidaysAsync.when(
      data: (holidays) {
        return Stack(
          children: [
            ListView.builder(
              itemCount: holidays.length,
              itemBuilder: (context, index) {
                final holiday = holidays[index];
                final date = holiday.date;

                final List<String> officeLocs = holiday.officeLocations;
                final String officeLocString = officeLocs.isNotEmpty
                    ? officeLocs.join(', ')
                    : 'All Offices';

                final bool isRecurring = holiday.isRecurring;

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
                      holiday.name,
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
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        Text(
                          isRecurring
                              ? '$officeLocString • Recurring'
                              : officeLocString,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.8),
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
                            .deleteHoliday(holiday.id);
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
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, s) => Center(child: Text('Error: $e')),
    );
  }

  void _showAddHolidayDialog(
    BuildContext context,
    WidgetRef ref,
    Holiday? holiday,
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
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
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
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
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
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.history, color: Colors.blueGrey),
                title: Text(
                  'Background Logs',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  'View background auto check-in execution logs.',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BackgroundLogsScreen(),
                    ),
                  );
                },
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

class UsersTab extends ConsumerWidget {
  const UsersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersStreamProvider);
    final currentUserAsync = ref.watch(userProfileProvider);
    final currentUserId = currentUserAsync.value?.id;

    return usersAsync.when(
      data: (users) {
        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primaryColor,
                  backgroundImage: user.photoUrl != null
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  child: user.photoUrl == null
                      ? Text(
                          user.displayName?.isNotEmpty == true
                              ? user.displayName![0].toUpperCase()
                              : 'U',
                          style: const TextStyle(color: Colors.white),
                        )
                      : null,
                ),
                title: Text(
                  user.displayName ?? 'Unknown User',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  user.email,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                trailing: Switch(
                  value: user.isAdmin,
                  onChanged: user.id == currentUserId
                      ? null
                      : (val) {
                          ref
                              .read(adminServiceProvider)
                              .updateUserRole(user.id, val);
                        },
                  activeThumbColor: AppTheme.primaryColor,
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, s) => Center(child: Text('Error: $e')),
    );
  }
}

class FeedbackTab extends ConsumerWidget {
  const FeedbackTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedbackAsync = ref.watch(feedbackStreamProvider);

    return feedbackAsync.when(
      data: (feedbacks) {
        if (feedbacks.isEmpty) {
          return const Center(
            child: Text(
              'No feedback available.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        return ListView.builder(
          itemCount: feedbacks.length,
          itemBuilder: (context, index) {
            final fb = feedbacks[index];
            final userName = fb['userName'] ?? 'Anonymous';
            final email = fb['userEmail'] ?? 'Unknown Email';
            final rating = fb['rating'] ?? 0;
            final message = fb['message'] ?? '';
            final createdAt = fb['createdAt'] as Timestamp?;
            final dateStr = createdAt != null
                ? DateFormat.yMMMd().add_jm().format(createdAt.toDate())
                : 'Pending sync...';

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$userName ($email)',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          dateStr,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star,
                              color: AppTheme.primaryColor,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rating.toString(),
                              style: const TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          final fbId = fb['id'] as String?;
                          if (fbId != null) {
                            ref.read(adminServiceProvider).deleteFeedback(fbId);
                          }
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.delete_outline,
                            color: AppTheme.dangerColor,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, s) => Center(child: Text('Error loading feedback: $e')),
    );
  }
}
