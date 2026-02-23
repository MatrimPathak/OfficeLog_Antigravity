import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/providers.dart';
import '../admin/admin_screen.dart';
import '../../services/admin_service.dart';
import 'widgets/delete_account_dialog.dart';
import 'widgets/feedback_dialog.dart';
import '../../services/background_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

final isDeletingAccountProvider =
    NotifierProvider<IsDeletingAccountNotifier, bool>(
      IsDeletingAccountNotifier.new,
    );

class IsDeletingAccountNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text('Settings'),
        centerTitle: true,
        scrolledUnderElevation: 0, // Fixes color change on scroll
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Profile Section
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Theme.of(context).primaryColor,
                    backgroundImage: user?.photoURL != null
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: user?.photoURL == null
                        ? const Text(
                            'U',
                            style: TextStyle(
                              fontSize: 40,
                              color: Colors
                                  .white, // White on primary bg is intentional
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user?.displayName ?? 'John Doe',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // PREFERENCES
            _buildSectionHeader('PREFERENCES'),
            _buildSettingsGroup(
              context,
              children: [
                _buildSettingsTile(
                  context,
                  icon: Icons.dark_mode,
                  iconColor: AppTheme.purpleAccent,
                  title: 'Dark Mode',
                  trailing: Switch.adaptive(
                    value:
                        themeMode == ThemeMode.dark ||
                        (themeMode == ThemeMode.system &&
                            MediaQuery.of(context).platformBrightness ==
                                Brightness.dark),
                    onChanged: (val) {
                      ref
                          .read(themeModeProvider.notifier)
                          .update(val ? ThemeMode.dark : ThemeMode.light);
                    },
                    activeThumbColor: AppTheme.purpleAccent,
                  ),
                ),
                _buildDivider(context),

                _buildSettingsTile(
                  context,
                  icon: Icons.notifications,
                  iconColor: AppTheme.dangerColor,
                  title: 'Daily Reminder',
                  value: ref.watch(notificationEnabledProvider)
                      ? ref.watch(notificationTimeProvider).format(context)
                      : 'Off',
                  trailing: Switch.adaptive(
                    value: ref.watch(notificationEnabledProvider),
                    onChanged: (val) async {
                      await ref
                          .read(notificationEnabledProvider.notifier)
                          .toggle(val);
                    },
                    activeThumbColor: AppTheme.dangerColor,
                  ),
                  onTap: () async {
                    final TimeOfDay? time = await showTimePicker(
                      context: context,
                      initialTime: ref.read(notificationTimeProvider),
                    );
                    if (time != null) {
                      await ref
                          .read(notificationTimeProvider.notifier)
                          .update(time);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // AUTO CHECK-IN
            _buildSectionHeader('AUTO CHECK-IN'),
            _buildSettingsGroup(
              context,
              children: [
                _buildSettingsTile(
                  context,
                  icon: Icons.location_on,
                  iconColor: AppTheme.warningColor,
                  title: 'Auto Check-in',
                  value: ref
                      .watch(locationPermissionProvider)
                      .when(
                        data: (status) {
                          if (status == LocationPermission.always) {
                            return 'Enabled';
                          }
                          if (status == LocationPermission.whileInUse) {
                            return 'Needs "Always"';
                          }
                          return 'Disabled';
                        },
                        loading: () => 'Checking...',
                        error: (_, __) => 'Error',
                      ),
                  onTap: () async {
                    await _checkLocationPermission(context);
                    ref.invalidate(locationPermissionProvider);
                  },
                ),
                _buildDivider(context),
                _buildSettingsTile(
                  context,
                  icon: Icons.battery_alert,
                  iconColor: Colors.orangeAccent,
                  title: 'Battery Optimization',
                  value: ref
                      .watch(batteryOptimizationProvider)
                      .when(
                        data: (isIgnored) => isIgnored ? 'Ignored' : 'Active',
                        loading: () => 'Checking...',
                        error: (_, __) => 'Error',
                      ),
                  onTap: () async {
                    final status = await Permission.ignoreBatteryOptimizations
                        .request();
                    if (context.mounted) {
                      if (status.isGranted) {
                        AppTheme.showSuccessSnackBar(
                          context,
                          'Battery optimization ignored. Background tasks will run reliably.',
                        );
                      } else if (status.isDenied) {
                        AppTheme.showWarningSnackBar(
                          context,
                          'Battery optimization is still active. Background tasks may be delayed.',
                        );
                      } else if (status.isPermanentlyDenied) {
                        AppTheme.showErrorSnackBar(
                          context,
                          'Permission permanently denied. Please enable "Allow background activity" in app settings.',
                        );
                      } else {
                        AppTheme.showWarningSnackBar(
                          context,
                          'Status: ${status.name}',
                        );
                      }
                      ref.invalidate(batteryOptimizationProvider);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // SUPPORT
            _buildSectionHeader('SUPPORT'),
            _buildSettingsGroup(
              context,
              children: [
                _buildSettingsTile(
                  context,
                  icon: Icons.feedback,
                  iconColor: Colors.blueAccent,
                  title: 'Send Feedback',
                  onTap: () => _showFeedbackDialog(context),
                ),
              ],
            ),

            if (ref.watch(isAdminProvider)) ...[
              const SizedBox(height: 24),
              _buildSectionHeader('ADMIN'),
              _buildSettingsGroup(
                context,
                children: [
                  _buildSettingsTile(
                    context,
                    icon: Icons.admin_panel_settings,
                    iconColor: Colors.teal,
                    title: 'Admin Panel',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminScreen()),
                      );
                    },
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color, // Lighter card bg
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: TextButton.icon(
                onPressed: () {
                  ref.read(authServiceProvider).signOut();
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
                icon: const Icon(Icons.logout, color: AppTheme.dangerColor),
                label: const Text(
                  'Sign Out',
                  style: TextStyle(
                    color: AppTheme.dangerColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: TextButton.icon(
                onPressed: ref.watch(isDeletingAccountProvider)
                    ? null
                    : () => _showDeleteAccountDialog(context, ref),
                icon: ref.watch(isDeletingAccountProvider)
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.dangerColor,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.delete_forever,
                        color: AppTheme.dangerColor,
                      ),
                label: Text(
                  ref.watch(isDeletingAccountProvider)
                      ? 'Deleting...'
                      : 'Delete Account',
                  style: const TextStyle(
                    color: AppTheme.dangerColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ref
                .watch(packageInfoProvider)
                .when(
                  data: (info) {
                    final version = info.version;
                    final build = info.buildNumber;
                    return Text(
                      'VERSION $version (BUILD $build)',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                  loading: () => const Text(
                    'VERSION ... (BUILD ...)',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  error: (_, __) => const SizedBox(),
                ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
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
    String? value,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 15,
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

  Future<void> _checkLocationPermission(BuildContext context) async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!context.mounted) return;

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      AppTheme.showErrorSnackBar(context, 'Location permission is denied.');
      return;
    }

    if (permission == LocationPermission.whileInUse) {
      showDialog(
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
    } else if (permission == LocationPermission.always) {
      await BackgroundService.registerPeriodicTask();
      if (context.mounted) {
        AppTheme.showSuccessSnackBar(
          context,
          'Auto Check-in Enabled! (Background task scheduled)',
        );
      }
    }
  }

  void _showFeedbackDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => const FeedbackDialog());
  }

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const DeleteAccountDialog(),
    );

    if (confirmed == true) {
      if (!context.mounted) return;

      ref.read(isDeletingAccountProvider.notifier).set(true);

      try {
        await ref.read(authServiceProvider).deleteUserAccount();
        if (context.mounted) {
          ref.read(isDeletingAccountProvider.notifier).set(false);
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      } catch (e) {
        if (context.mounted) {
          ref.read(isDeletingAccountProvider.notifier).set(false);

          if (e is FirebaseAuthException && e.code == 'requires-recent-login') {
            AppTheme.showErrorSnackBar(
              context,
              'Security Check: You need to log out and log back in to delete your account.',
            );
          } else {
            AppTheme.showErrorSnackBar(
              context,
              'Failed to delete account. Please try again later.',
            );
          }
        }
      }
    }
  }
}
