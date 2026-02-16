import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/providers.dart';
import '../admin/admin_screen.dart';
import 'widgets/delete_account_dialog.dart';
import 'widgets/feedback_dialog.dart';

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
                  // Commented out as requested
                  /*
                  Text(
                    'Senior Product Designer\nProduct Department • ID: 4829',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  */
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
                    activeColor: AppTheme.purpleAccent,
                  ),
                ),
                _buildDivider(context),
                _buildSettingsTile(
                  context,
                  icon: Icons.app_registration, // Icon for dynamic app icon
                  iconColor: Colors.deepPurple,
                  title: 'Dynamic App Icon',
                  trailing: Switch.adaptive(
                    value: ref.watch(dynamicIconEnabledProvider),
                    onChanged: (val) {
                      ref.read(dynamicIconEnabledProvider.notifier).toggle(val);
                    },
                    activeColor: Colors.deepPurple,
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
                    activeColor: AppTheme.dangerColor,
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
                  value: 'Configure',
                  onTap: () => _checkLocationPermission(context),
                ),
                _buildDivider(context),
                _buildSettingsTile(
                  context,
                  icon: Icons.battery_alert,
                  iconColor: Colors.orangeAccent,
                  title: 'Battery Optimization',
                  value: 'Ignore',
                  onTap: () async {
                    final status = await Permission.ignoreBatteryOptimizations
                        .request();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Status: ${status.name}')),
                      );
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

            if (user?.email == 'matrimpathak1999@gmail.com') ...[
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
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: TextButton.icon(
                onPressed: () => _showDeleteAccountDialog(context, ref),
                icon: const Icon(
                  Icons.delete_forever,
                  color: AppTheme.dangerColor,
                ),
                label: const Text(
                  'Delete Account',
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
            const SizedBox(height: 24),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.data?.version ?? '...';
                final build = snapshot.data?.buildNumber ?? '...';
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
          color: iconColor.withOpacity(0.2),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission is denied.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Great! You have "Allow all the time".')),
      );
    }
  }

  void _showFeedbackDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: const FeedbackDialog(),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const DeleteAccountDialog(),
    );

    if (confirmed == true) {
      if (!context.mounted) return;

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        await ref.read(authServiceProvider).deleteUserAccount();
        if (context.mounted) {
          Navigator.pop(context); // Remove loading indicator
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.pop(context); // Remove loading indicator
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }
}
