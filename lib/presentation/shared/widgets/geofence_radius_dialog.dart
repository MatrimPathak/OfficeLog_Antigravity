import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../../services/auto_checkin_service.dart';

class GeofenceRadiusDialog extends ConsumerStatefulWidget {
  const GeofenceRadiusDialog({super.key});

  @override
  ConsumerState<GeofenceRadiusDialog> createState() =>
      _GeofenceRadiusDialogState();
}

class _GeofenceRadiusDialogState extends ConsumerState<GeofenceRadiusDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final currentRadius = ref.read(geofenceRadiusProvider);
    _controller = TextEditingController(text: currentRadius.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              controller: _controller,
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
                        final newRadius = int.tryParse(_controller.text);
                        if (newRadius != null && newRadius >= 10) {
                          await ref
                              .read(geofenceRadiusProvider.notifier)
                              .update(newRadius);
                          if (!context.mounted) return;

                          // Re-initialize geofence with new radius only if auto check-in is enabled
                          if (ref.read(autoCheckInEnabledProvider)) {
                            await ref
                                .read(autoCheckInServiceProvider)
                                .initGeofence();
                          }

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
    );
  }
}
