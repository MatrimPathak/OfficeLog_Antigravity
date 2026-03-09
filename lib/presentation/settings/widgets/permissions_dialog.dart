import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/providers.dart';
import '../../../core/theme/app_theme.dart';

class PermissionsDialog extends ConsumerWidget {
  const PermissionsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
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
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.security_rounded,
                color: AppTheme.primaryColor,
                size: 32,
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'Permissions Status',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Description
            const Text(
              'For Auto Check-in to work reliably, please ensure the following permissions are granted.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            // Permissions List
            const _PermissionsList(),

            const SizedBox(height: 32),

            // Close button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).dividerColor.withValues(alpha: 0.1),
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Close',
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

class _PermissionsList extends ConsumerWidget {
  const _PermissionsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationStatus = ref.watch(locationPermissionProvider);
    final bgLocationStatus = ref.watch(backgroundLocationPermissionProvider);
    final notificationStatus = ref.watch(notificationPermissionProvider);
    final batteryStatus = ref.watch(batteryOptimizationProvider);

    return Column(
      children: [
        _PermissionTile(
          icon: Icons.location_on_rounded,
          title: 'Location (While in Use)',
          status: locationStatus.when(
            data: (s) =>
                s != LocationPermission.denied &&
                s != LocationPermission.deniedForever,
            loading: () => true,
            error: (_, __) => false,
          ),
          onTap: () => openAppSettings(),
        ),
        _buildDivider(context),
        _PermissionTile(
          icon: Icons.map_rounded,
          title: 'Location (Always)',
          status: bgLocationStatus.when(
            data: (s) => s,
            loading: () => true,
            error: (_, __) => false,
          ),
          onTap: () => openAppSettings(),
        ),
        _buildDivider(context),
        _PermissionTile(
          icon: Icons.notifications_active_rounded,
          title: 'Notifications',
          status: notificationStatus.when(
            data: (s) => s,
            loading: () => true,
            error: (_, __) => false,
          ),
          onTap: () => openAppSettings(),
        ),
        if (Theme.of(context).platform == TargetPlatform.android) ...[
          _buildDivider(context),
          _PermissionTile(
            icon: Icons.battery_saver_rounded,
            title: 'Battery Optimization',
            status: batteryStatus.when(
              data: (s) => s,
              loading: () => true,
              error: (_, __) => false,
            ),
            onTap: () => openAppSettings(),
          ),
        ],
      ],
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Divider(
      height: 1,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool status;
  final VoidCallback onTap;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = status ? Colors.greenAccent : Colors.redAccent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (status)
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.greenAccent,
              size: 22,
            )
          else
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Allow',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
