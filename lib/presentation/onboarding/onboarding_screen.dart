import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../services/background_service.dart';
import '../../data/models/office_location.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  OfficeLocation? _selectedLocation;
  bool _isLoading = false;

  Future<void> _saveLocation() async {
    if (_selectedLocation == null) return;

    setState(() => _isLoading = true);
    try {
      // Request Location Permission
      LocationPermission locationPermission =
          await Geolocator.checkPermission();
      if (locationPermission == LocationPermission.denied) {
        locationPermission = await Geolocator.requestPermission();
      }

      if (locationPermission == LocationPermission.denied ||
          locationPermission == LocationPermission.deniedForever) {
        // Handle denied permission (optional: show dialog)
      } else {
        if (locationPermission == LocationPermission.whileInUse) {
          final alwaysStatus = await Permission.locationAlways.request();
          if (alwaysStatus.isGranted) {
            debugPrint('Location Always granted');
          }
        }
        await Permission.ignoreBatteryOptimizations.request();
      }

      final user = ref.read(currentUserProvider);
      if (user != null) {
        await ref
            .read(authServiceProvider)
            .updateOfficeLocation(
              user.uid,
              _selectedLocation!.name,
              _selectedLocation!.latitude,
              _selectedLocation!.longitude,
            );

        // --- AUTONOMOUS REGISTRATION ---
        // As soon as the user finishes onboarding, aggressively attempt to schedule the background heartbeat.
        await BackgroundService.checkAndRegisterTask();
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showErrorSnackBar(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(officeLocationsProvider);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).scaffoldBackgroundColor, // Dark Navy Background
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                // User Details Section
                if (ref.watch(currentUserProvider) != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundImage:
                                ref.watch(currentUserProvider)!.photoURL != null
                                ? NetworkImage(
                                    ref.watch(currentUserProvider)!.photoURL!,
                                  )
                                : null,
                            backgroundColor: Theme.of(context).primaryColor,
                            child:
                                ref.watch(currentUserProvider)!.photoURL == null
                                ? Text(
                                    ref
                                            .watch(currentUserProvider)!
                                            .displayName
                                            ?.substring(0, 1)
                                            .toUpperCase() ??
                                        'U',
                                    style: const TextStyle(color: Colors.white),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ref.watch(currentUserProvider)!.displayName ??
                                      'User',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  ref.watch(currentUserProvider)!.email ?? '',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
                Text(
                  'Select Office',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose your primary office location to continue.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.grey[400]),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: locationsAsync.when(
                    data: (locations) {
                      return ListView.separated(
                        itemCount: locations.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final loc = locations[index];
                          final isSelected = _selectedLocation == loc;
                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: isSelected
                                    ? AppTheme.primaryColor
                                    : Theme.of(context).dividerColor,
                                width: 2,
                              ),
                            ),
                            child: InkWell(
                              onTap: () {
                                setState(() => _selectedLocation = loc);
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(
                                                0xFF2E88F6,
                                              ).withOpacity(0.2)
                                            : Colors.grey[800],
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.business,
                                        color: isSelected
                                            ? AppTheme.primaryColor
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            loc.name,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                            ),
                                          ),
                                          // Optional: Add address if available in model
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle,
                                        color: AppTheme.primaryColor,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    error: (e, s) => Center(
                      child: Text(
                        'Error loading locations',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Action Button
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: (_isLoading || _selectedLocation == null)
                        ? LinearGradient(
                            colors: [
                              AppTheme.primaryColor.withOpacity(0.5),
                              AppTheme.primaryColor.withOpacity(0.3),
                            ],
                          )
                        : LinearGradient(
                            colors: [
                              AppTheme.primaryColor,
                              AppTheme.logGradientStart,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: (_isLoading || _selectedLocation == null)
                        ? null
                        : [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).primaryColor.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: (_isLoading || _selectedLocation == null)
                          ? null
                          : _saveLocation,
                      borderRadius: BorderRadius.circular(16),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                'Continue',
                                style: TextStyle(
                                  color:
                                      (_isLoading || _selectedLocation == null)
                                      ? Colors.white.withOpacity(0.5)
                                      : Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
