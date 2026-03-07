import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import '../providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../services/notification_service.dart';
import '../../services/auto_checkin_service.dart';
import '../../data/models/office_location.dart';
import '../../services/google_places_service.dart';
import '../../data/models/place_suggestion.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  OfficeLocation? _selectedLocation;
  LatLng _selectedLatLng = const LatLng(12.9716, 77.5946); // Bengaluru default
  String _selectedAddress = '';
  Set<Marker> _markers = {};

  final GooglePlacesService _placesService = GooglePlacesService();
  List<PlaceSuggestion> _searchResults = [];
  Timer? _debounce;
  bool _isLoading = false;
  bool _isMapSearching = false;

  @override
  void initState() {
    super.initState();
    _updateMarker(_selectedLatLng, name: 'Custom Office');
  }

  void _updateMarker(LatLng position, {String? name}) async {
    setState(() {
      _selectedLatLng = position;
      _markers = {
        ..._markers.where((m) => m.markerId.value != 'selected_location'),
        Marker(
          markerId: const MarkerId('selected_location'),
          position: position,
          draggable: true,
          onDragEnd: (newPosition) {
            _updateMarker(newPosition);
          },
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(title: name ?? 'Selected Location'),
        ),
      };

      if (name != null) {
        _nameController.text = name;
      }
    });

    try {
      final address = await _placesService.getAddressFromLatLng(
        position.latitude,
        position.longitude,
      );
      if (address != null && mounted) {
        setState(() {
          _selectedAddress = address;
        });
      }
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
    }

    _updateSelectedLocation();
  }

  void _updateSelectedLocation() {
    _selectedLocation = OfficeLocation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.isEmpty ? 'My Office' : _nameController.text,
      address: _selectedAddress,
      latitude: _selectedLatLng.latitude,
      longitude: _selectedLatLng.longitude,
    );
    setState(() {});
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (query.length >= 2) {
        _searchAddress();
      } else {
        setState(() {
          _searchResults = [];
        });
      }
    });
  }

  Future<void> _searchAddress() async {
    if (_searchController.text.isEmpty) return;

    final query = _searchController.text;
    setState(() {
      _isMapSearching = true;
      _searchResults = [];
    });

    try {
      final suggestions = await _placesService.getAutocompleteSuggestions(
        query,
        location: _selectedLatLng,
      );

      if (mounted) {
        setState(() {
          _searchResults = suggestions;
        });
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Search error: $e');
      }
    } finally {
      if (mounted) setState(() => _isMapSearching = false);
    }
  }

  void _selectSearchResult(PlaceSuggestion suggestion) async {
    setState(() => _isLoading = true);
    try {
      final details = await _placesService.getPlaceDetails(suggestion.placeId);
      if (details != null && mounted) {
        final newLatLng = LatLng(details.lat, details.lng);

        setState(() {
          _selectedLatLng = newLatLng;
          _selectedAddress = details.formattedAddress;
          if (_nameController.text.isEmpty ||
              _nameController.text == 'My Office') {
            _nameController.text = details.name;
          }
          _searchResults = [];
        });

        _updateMarker(newLatLng, name: details.name);

        final controller = await _mapController.future;
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: newLatLng, zoom: 17.0),
          ),
        );

        if (mounted) FocusScope.of(context).unfocus();
      }
    } catch (e) {
      debugPrint('Error selecting place: $e');
      if (mounted) {
        AppTheme.showErrorSnackBar(context, 'Could not load place details');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
        await Permission.notification.request();
        await NotificationService.requestPermissions();
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
              address: _selectedLocation!.address,
            );

        await ref.read(autoCheckInServiceProvider).initGeofence();
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
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Full Screen Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _selectedLatLng,
              zoom: 12.0,
            ),
            onMapCreated: (controller) => _mapController.complete(controller),
            markers: _markers,
            onTap: (position) => _updateMarker(position),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            padding: const EdgeInsets.only(bottom: 250, top: 100),
          ),

          // Top Overlay: User Profile & Search
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Minimal User Card
                  if (ref.watch(currentUserProvider) != null)
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundImage:
                                  ref.watch(currentUserProvider)!.photoURL !=
                                      null
                                  ? NetworkImage(
                                      ref.watch(currentUserProvider)!.photoURL!,
                                    )
                                  : null,
                              backgroundColor: Theme.of(context).primaryColor,
                              child:
                                  ref.watch(currentUserProvider)!.photoURL ==
                                      null
                                  ? Text(
                                      ref
                                              .watch(currentUserProvider)!
                                              .displayName
                                              ?.substring(0, 1)
                                              .toUpperCase() ??
                                          'U',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Hello, ${ref.watch(currentUserProvider)!.displayName?.split(' ').first ?? 'User'}!',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  // Search Bar
                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: const InputDecoration(
                                hintText: 'Search for your office...',
                                border: InputBorder.none,
                                icon: Icon(Icons.search),
                              ),
                              onChanged: _onSearchChanged,
                              onSubmitted: (_) => _searchAddress(),
                            ),
                          ),
                          if (_isMapSearching)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Search Suggestions List
                  if (_isMapSearching ||
                      _searchResults.isNotEmpty ||
                      (_searchController.text.length >= 2 &&
                          !_isMapSearching &&
                          _searchResults.isEmpty))
                    Card(
                      elevation: 8,
                      margin: const EdgeInsets.only(top: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 250),
                        child: _isMapSearching
                            ? const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Searching locations...',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              )
                            : _searchResults.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text(
                                  'No locations found',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  final suggestion = _searchResults[index];

                                  return ListTile(
                                    leading: const Icon(
                                      Icons.location_on_outlined,
                                      color: AppTheme.primaryColor,
                                    ),
                                    title: Text(
                                      suggestion.description,
                                      style: const TextStyle(fontSize: 14),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () =>
                                        _selectSearchResult(suggestion),
                                  );
                                },
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom Details Sheet (Simulated)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 15,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set Your Office',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap anywhere on the map or drag the pin to set your office.',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => _updateSelectedLocation(),
                    decoration: InputDecoration(
                      labelText: 'Office Name',
                      hintText: 'e.g. Hyderabad Main',
                      prefixIcon: const Icon(Icons.business_outlined),
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[900]
                          : Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedAddress,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: _isLoading
                            ? null
                            : LinearGradient(
                                colors: [
                                  AppTheme.primaryColor,
                                  AppTheme.logGradientStart,
                                ],
                              ),
                        borderRadius: BorderRadius.circular(16),
                        color: _isLoading ? Colors.grey : null,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isLoading ? null : _saveLocation,
                          borderRadius: BorderRadius.circular(16),
                          child: Center(
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Text(
                                    'Confirm & Continue',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
