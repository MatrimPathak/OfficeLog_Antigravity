class UserProfile {
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String? officeLocation;
  final double? officeLat;
  final double? officeLng;
  final bool isAdmin;
  final Map<String, dynamic> settings;

  UserProfile({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.officeLocation,
    this.officeLat,
    this.officeLng,
    this.isAdmin = false,
    this.settings = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'officeLocation': officeLocation,
      'officeLat': officeLat,
      'officeLng': officeLng,
      'isAdmin': isAdmin,
      'settings': settings,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] ?? '',
      email: map['email'] ?? '',
      displayName: map['displayName'],
      photoUrl: map['photoUrl'],
      officeLocation: map['officeLocation'],
      officeLat: map['officeLat'],
      officeLng: map['officeLng'],
      isAdmin: map['isAdmin'] ?? false,
      settings: map['settings'] ?? {},
    );
  }
}
