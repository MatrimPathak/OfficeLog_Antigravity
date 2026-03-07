class PlaceSuggestion {
  final String placeId;
  final String description;

  PlaceSuggestion({required this.placeId, required this.description});

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    return PlaceSuggestion(
      placeId: json['place_id'] as String,
      description: json['description'] as String,
    );
  }
}

class PlaceDetails {
  final String name;
  final double lat;
  final double lng;
  final String formattedAddress;

  PlaceDetails({
    required this.name,
    required this.lat,
    required this.lng,
    required this.formattedAddress,
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    final location = json['geometry']['location'];
    return PlaceDetails(
      name: json['name'] as String,
      lat: location['lat'] as double,
      lng: location['lng'] as double,
      formattedAddress: json['formatted_address'] as String,
    );
  }
}
