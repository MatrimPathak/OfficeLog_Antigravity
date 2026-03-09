import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import '../providers/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auto_checkin_service.dart';
import '../../data/models/office_location.dart';
import '../../services/google_places_service.dart';
import '../../data/models/place_suggestion.dart';

class EditOfficeScreen extends ConsumerStatefulWidget {
  final String? initialName;
  final String? initialAddress;
  final double? initialLat;
  final double? initialLng;

  const EditOfficeScreen({
    super.key,
    this.initialName,
    this.initialAddress,
    this.initialLat,
    this.initialLng,
  });

  @override
  ConsumerState<EditOfficeScreen> createState() => _EditOfficeScreenState();
}

class _EditOfficeScreenState extends ConsumerState<EditOfficeScreen> {
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  OfficeLocation? _selectedLocation;
  late LatLng _selectedLatLng;
  late String _selectedAddress;
  Set<Marker> _markers = {};

  final GooglePlacesService _placesService = GooglePlacesService();
  List<PlaceSuggestion> _searchResults = [];
  Timer? _debounce;
  bool _isLoading = false;
  bool _isMapSearching = false;

  @override
  void initState() {
    super.initState();
    _selectedLatLng = LatLng(
      widget.initialLat ?? 12.9716,
      widget.initialLng ?? 77.5946,
    );
    _selectedAddress = widget.initialAddress ?? '';
    _nameController.text = widget.initialName ?? 'My Office';

    _updateMarker(_selectedLatLng, name: _nameController.text);
  }

  void _updateMarker(LatLng position, {String? name}) async {
    setState(() {
      _selectedLatLng = position;
      _markers = {
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
          _nameController.text = details.name;
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

        if (mounted) {
          Navigator.pop(context);
          AppTheme.showSuccessSnackBar(context, 'Office updated successfully');
        }
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showErrorSnackBar(context, 'Error updating office: $e');
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
      appBar: AppBar(
        title: const Text(
          'Edit Office',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Full Screen Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _selectedLatLng,
              zoom: 15.0,
            ),
            onMapCreated: (controller) => _mapController.complete(controller),
            markers: _markers,
            onTap: (position) => _updateMarker(position),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            padding: const EdgeInsets.only(bottom: 250),
          ),

          // Top Overlay: Search
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
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
                                hintText: 'Search for new office...',
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

          // Bottom Details Sheet
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
                    'Office Details',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Update your office name and location.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => _updateSelectedLocation(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Office Name',
                      labelStyle: TextStyle(
                        color: Theme.of(context).primaryColor,
                      ),
                      hintText: 'e.g. Hyderabad Main',
                      prefixIcon: Icon(
                        Icons.business_outlined,
                        color: Theme.of(context).primaryColor,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[900]
                          : Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 1.5,
                        ),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
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
                                    'Save Changes',
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
