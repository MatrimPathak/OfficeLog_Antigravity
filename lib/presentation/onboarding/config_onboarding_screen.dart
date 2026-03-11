import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_theme.dart';
import '../providers/providers.dart';
import '../../services/background_service.dart';
import '../../services/auto_checkin_service.dart';
import '../../services/notification_service.dart';
import '../shared/widgets/app_time_picker.dart';

class ConfigOnboardingScreen extends ConsumerStatefulWidget {
  const ConfigOnboardingScreen({super.key});

  @override
  ConsumerState<ConfigOnboardingScreen> createState() =>
      _ConfigOnboardingScreenState();
}

class _ConfigOnboardingScreenState
    extends ConsumerState<ConfigOnboardingScreen> {
  bool _isLoading = false;

  Future<void> _checkLocationPermission() async {
    // 1. Basic Location Permission (While in Use)
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!mounted) return;

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      AppTheme.showErrorSnackBar(context, 'Location permission is denied.');
      return;
    }

    // 2. Background Location Permission (Always)
    if (permission == LocationPermission.whileInUse) {
      final alwaysStatus = await Permission.locationAlways.request();
      if (alwaysStatus.isDenied || alwaysStatus.isPermanentlyDenied) {
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Background Location Required'),
              content: const Text(
                'Auto Check-in requires "Allow all the time" location access to work when the app is closed. Please enable it in settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Geolocator.openAppSettings();
                  },
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    // 3. Battery Optimizations (Required for reliable background work on Android)
    await Permission.ignoreBatteryOptimizations.request();

    // 4. Notifications
    await Permission.notification.request();
    await NotificationService.requestPermissions();

    // 5. Finalize
    final finalPermission = await Geolocator.checkPermission();
    if (finalPermission == LocationPermission.always) {
      await BackgroundService.checkAndRegisterTask();
      if (mounted) {
        AppTheme.showSuccessSnackBar(
          context,
          'Auto Check-in Enabled! (Background task scheduled)',
        );
      }
    }
  }

  Future<void> _finishOnboarding() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      final settings = {
        'theme_mode': ref.read(themeModeProvider).index,
        'notifications_enabled': ref.read(notificationEnabledProvider),
        'notification_hour': ref.read(notificationTimeProvider).hour,
        'notification_minute': ref.read(notificationTimeProvider).minute,
        'auto_checkin_enabled': ref.read(autoCheckInEnabledProvider),
        'geofence_radius': ref.read(geofenceRadiusProvider),
      };

      await ref
          .read(authServiceProvider)
          .completeOnboarding(user.uid, settings);
      // Main app routing will automatically catch this and navigate to Home.
    } catch (e) {
      if (mounted) {
        AppTheme.showErrorSnackBar(context, 'Error finalizing setup: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? value,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 16,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Text(
              value,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (value != null || trailing == null) const SizedBox(width: 8),
          if (trailing != null)
            trailing
          else
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProfileAsync = ref.watch(userProfileProvider);
    final isAutoCheckIn = ref.watch(autoCheckInEnabledProvider);
    final isNotifications = ref.watch(notificationEnabledProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text('Final Configurations'),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: userProfileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (profile) {
          final officeLoc = profile?.officeLocation ?? 'Unknown Office';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Set up optional features to automate your experience. You can always change these later in Settings.',
                  style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.business, color: AppTheme.primaryColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Office: $officeLoc',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.notifications,
                        iconColor: AppTheme.dangerColor,
                        title: 'Daily Reminders',
                        value: isNotifications
                            ? ref
                                  .watch(notificationTimeProvider)
                                  .format(context)
                            : 'Off',
                        trailing: Switch.adaptive(
                          value: isNotifications,
                          activeThumbColor: AppTheme.dangerColor,
                          onChanged: (val) async {
                            await ref
                                .read(notificationEnabledProvider.notifier)
                                .toggle(val);
                            if (val && mounted) {
                              await Permission.notification.request();
                              await NotificationService.requestPermissions();
                              
                              if (!mounted) return;
                              final TimeOfDay? time = await AppTimePicker.show(
                                context: context,
                                initialTime: ref.read(notificationTimeProvider),
                                title: 'Notification Time',
                              );
                              if (time != null) {
                                await ref
                                    .read(notificationTimeProvider.notifier)
                                    .update(time);
                              }
                            }
                          },
                        ),
                        onTap: isNotifications
                            ? () async {
                                final TimeOfDay? time =
                                    await AppTimePicker.show(
                                      context: context,
                                      initialTime: ref.read(
                                        notificationTimeProvider,
                                      ),
                                      title: 'Notification Time',
                                    );
                                if (time != null) {
                                  await ref
                                      .read(notificationTimeProvider.notifier)
                                      .update(time);
                                }
                              }
                            : null,
                      ),
                      const Divider(height: 1),
                      _buildSettingsTile(
                        icon: Icons.location_on,
                        iconColor: AppTheme.warningColor,
                        title: 'Auto Check-in',
                        value: isAutoCheckIn ? null : 'Off',
                        trailing: Switch.adaptive(
                          value: isAutoCheckIn,
                          activeThumbColor: AppTheme.warningColor,
                          onChanged: (val) async {
                            if (val) {
                              await _checkLocationPermission();
                              final permission =
                                  await Geolocator.checkPermission();
                              if (permission == LocationPermission.always) {
                                await ref
                                    .read(autoCheckInEnabledProvider.notifier)
                                    .toggle(true);
                                if (mounted) {
                                  await ref
                                      .read(autoCheckInServiceProvider)
                                      .initGeofence();
                                }
                              }
                            } else {
                              await ref
                                  .read(autoCheckInEnabledProvider.notifier)
                                  .toggle(false);
                              await ref
                                  .read(autoCheckInServiceProvider)
                                  .stopGeofence();
                            }
                          },
                        ),
                      ),
                      const Divider(height: 1),
                      _buildSettingsTile(
                        icon: Icons.calculate_outlined,
                        iconColor: Colors.orangeAccent,
                        title: 'Treat Holidays as Working',
                        trailing: Switch.adaptive(
                          value: ref.watch(calculateHolidayAsWorkingProvider),
                          activeThumbColor: Colors.orangeAccent,
                          onChanged: (val) {
                            ref
                                .read(calculateHolidayAsWorkingProvider.notifier)
                                .toggle(val);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : _finishOnboarding,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _finishOnboarding,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Finish',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
