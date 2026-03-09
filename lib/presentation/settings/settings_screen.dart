import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../providers/providers.dart';
import '../admin/admin_screen.dart';
import '../../services/admin_service.dart';
import 'widgets/delete_account_dialog.dart';
import 'widgets/feedback_dialog.dart';
import 'widgets/permissions_dialog.dart';
import '../../services/background_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'personal_holidays_screen.dart';
import '../shared/widgets/app_time_picker.dart';
import '../../services/auto_checkin_service.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import 'edit_office_screen.dart';

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
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Theme.of(context).primaryColor,
                      backgroundImage: user?.photoURL != null
                          ? NetworkImage(user!.photoURL!)
                          : null,
                      child: user?.photoURL == null
                          ? Text(
                              user?.displayName
                                      ?.substring(0, 1)
                                      .toUpperCase() ??
                                  'U',
                              style: const TextStyle(
                                fontSize: 40,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    user?.displayName ?? 'User Name',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.email_outlined,
                        size: 14,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        user?.email ?? '',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Office Information Section
                  ref
                      .watch(userProfileProvider)
                      .when(
                        data: (profile) {
                          final officeName = profile?.officeLocation;
                          final officeAddress = profile?.officeAddress;

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).cardTheme.color!.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildInfoRow(
                                  context,
                                  icon: Icons.business_rounded,
                                  label: 'Office Name',
                                  value: officeName ?? 'Not Set',
                                  iconColor: Colors.blueAccent,
                                  trailing: IconButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => EditOfficeScreen(
                                            initialName: officeName,
                                            initialAddress: officeAddress,
                                            initialLat: profile?.officeLat,
                                            initialLng: profile?.officeLng,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                      color: Colors.blueAccent,
                                    ),
                                    tooltip: 'Edit Office',
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 44,
                                    top: 12,
                                    bottom: 12,
                                  ),
                                  child: Divider(
                                    height: 1,
                                    color: Theme.of(
                                      context,
                                    ).dividerColor.withValues(alpha: 0.1),
                                  ),
                                ),
                                _buildInfoRow(
                                  context,
                                  icon: Icons.location_on_rounded,
                                  label: 'Office Location',
                                  value: officeAddress ?? 'Not Set',
                                  iconColor: Colors.redAccent,
                                  trailing:
                                      (profile?.officeLat != null &&
                                          profile?.officeLng != null)
                                      ? IconButton(
                                          onPressed: () async {
                                            final url = Uri.parse(
                                              'https://www.google.com/maps/search/?api=1&query=${profile!.officeLat},${profile.officeLng}',
                                            );
                                            if (await launcher.canLaunchUrl(
                                              url,
                                            )) {
                                              await launcher.launchUrl(
                                                url,
                                                mode: launcher
                                                    .LaunchMode
                                                    .externalApplication,
                                              );
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.directions_rounded,
                                            color: Colors.blueAccent,
                                          ),
                                          tooltip: 'Open in Maps',
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(),
                        ),
                        error: (_, __) => const SizedBox(),
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
                  },
                ),
                _buildDivider(context),
                _buildSettingsTile(
                  context,
                  icon: Icons.event_available,
                  iconColor: Colors.tealAccent.shade700,
                  title: 'Personal Holidays',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PersonalHolidaysScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            _buildSectionHeader('AUTO CHECK-IN'),
            _buildSettingsGroup(
              context,
              children: [
                _buildSettingsTile(
                  context,
                  icon: Icons.location_on,
                  iconColor: AppTheme.warningColor,
                  title: 'Auto Check-in',
                  value: ref.watch(autoCheckInEnabledProvider) ? null : 'Off',
                  trailing: Switch.adaptive(
                    value: ref.watch(autoCheckInEnabledProvider),
                    onChanged: (val) async {
                      if (val) {
                        await _checkLocationPermission(context);
                        final permission = await Geolocator.checkPermission();
                        if (permission == LocationPermission.always) {
                          await ref
                              .read(autoCheckInEnabledProvider.notifier)
                              .toggle(true);
                          if (context.mounted) {
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
                    activeThumbColor: AppTheme.warningColor,
                  ),
                ),
                _buildDivider(context),
                _buildSettingsTile(
                  context,
                  icon: Icons.radar,
                  iconColor: AppTheme.warningColor,
                  title: 'Geofence Radius',
                  value: '${ref.watch(geofenceRadiusProvider)}m',
                  onTap: ref.watch(autoCheckInEnabledProvider)
                      ? () => _showRadiusDialog(context, ref)
                      : null,
                ),
                if (ref.watch(autoCheckInEnabledProvider)) ...[
                  _buildDivider(context),
                  _buildSettingsTile(
                    context,
                    icon: Icons.security,
                    iconColor: Colors.blueGrey,
                    title: 'Permissions',
                    value: ref
                        .watch(locationPermissionProvider)
                        .when(
                          data: (status) {
                            if (status == LocationPermission.always) {
                              return 'Ready';
                            }
                            if (status == LocationPermission.whileInUse) {
                              return 'Needs "Always"';
                            }
                            return 'Denied';
                          },
                          loading: () => '...',
                          error: (_, __) => 'Error',
                        ),
                    onTap: () async {
                      await showDialog(
                        context: context,
                        builder: (context) => const PermissionsDialog(),
                      );
                      ref.invalidate(locationPermissionProvider);
                      ref.invalidate(backgroundLocationPermissionProvider);
                      ref.invalidate(notificationPermissionProvider);
                      ref.invalidate(batteryOptimizationProvider);
                    },
                  ),
                ],
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
      await BackgroundService.checkAndRegisterTask();
      if (context.mounted) {
        AppTheme.showSuccessSnackBar(
          context,
          'Auto Check-in Enabled! (Background task scheduled)',
        );
      }
    }
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
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

  Future<void> _showRadiusDialog(BuildContext context, WidgetRef ref) async {
    final currentRadius = ref.read(geofenceRadiusProvider);
    final controller = TextEditingController(text: currentRadius.toString());

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Header Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: AppTheme.warningColor,
                  size: 32,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'Geofence Radius',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Description
              const Text(
                'Enter the radius in meters for the office geofence. This determines how close you need to be for auto check-in.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
                decoration: InputDecoration(
                  hintText: '100',
                  suffixText: 'm',
                  suffixStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.normal,
                    color: Colors.grey,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                autofocus: true,
              ),

              const SizedBox(height: 32),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.05),
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () async {
                          final newRadius = int.tryParse(controller.text);
                          if (newRadius != null && newRadius >= 10) {
                            await ref
                                .read(geofenceRadiusProvider.notifier)
                                .update(newRadius);
                            if (!context.mounted) return;

                            // Re-initialize geofence with new radius
                            await ref
                                .read(autoCheckInServiceProvider)
                                .initGeofence();

                            if (!context.mounted) return;
                            Navigator.pop(context);
                            AppTheme.showSuccessSnackBar(
                              context,
                              'Radius updated to ${newRadius}m',
                            );
                          } else {
                            AppTheme.showErrorSnackBar(
                              context,
                              'Please enter a valid radius (min 10m)',
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Save',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
