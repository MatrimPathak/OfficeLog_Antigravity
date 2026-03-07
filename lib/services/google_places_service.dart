import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/config/constants.dart';
import '../data/models/place_suggestion.dart';

class GooglePlacesService {
  static const String _autocompleteUrl =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const String _detailsUrl =
      'https://maps.googleapis.com/maps/api/place/details/json';
  static const String _geocodingUrl =
      'https://maps.googleapis.com/maps/api/geocode/json';

  final String _apiKey = AppConstants.googleMapsApiKey;

  Future<List<PlaceSuggestion>> getAutocompleteSuggestions(
    String input, {
    LatLng? location,
    int radius = 50000,
  }) async {
    if (input.isEmpty) return [];

    final Uri uri = Uri.parse(_autocompleteUrl).replace(
      queryParameters: {
        'input': input,
        'types': 'establishment',
        'keyword': 'office',
        if (location != null)
          'location': '${location.latitude},${location.longitude}',
        'radius': radius.toString(),
        'key': _apiKey,
      },
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List;
          return predictions.map((p) => PlaceSuggestion.fromJson(p)).toList();
        } else if (data['status'] == 'ZERO_RESULTS') {
          return [];
        } else {
          throw Exception(
            'Places API Error: ${data['status']} - ${data['error_message'] ?? 'No message'}',
          );
        }
      } else {
        throw Exception('Failed to load suggestions: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Autocomplete Error: $e');
      return [];
    }
  }

  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    final Uri uri = Uri.parse(_detailsUrl).replace(
      queryParameters: {
        'place_id': placeId,
        'fields': 'name,geometry,formatted_address',
        'key': _apiKey,
      },
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          return PlaceDetails.fromJson(data['result']);
        } else {
          throw Exception('Place Details Error: ${data['status']}');
        }
      } else {
        throw Exception('Failed to load place details: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Details Error: $e');
      return null;
    }
  }

  Future<String?> getAddressFromLatLng(double lat, double lng) async {
    final Uri uri = Uri.parse(
      _geocodingUrl,
    ).replace(queryParameters: {'latlng': '$lat,$lng', 'key': _apiKey});

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final results = data['results'] as List;
          if (results.isNotEmpty) {
            return results.first['formatted_address'] as String;
          }
        }
      }
    } catch (e) {
      debugPrint('Reverse Geocoding Error: $e');
    }
    return null;
  }
}
