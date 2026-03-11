import 'holiday.dart';

class UserProfile {
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String? officeLocation;
  final String? officeAddress;
  final double? officeLat;
  final double? officeLng;
  final bool isAdmin;
  final bool isOnboardingCompleted;
  final Map<String, dynamic> settings;
  final List<String>? selectedHolidays;
  final List<Holiday>? customHolidays;

  UserProfile({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.officeLocation,
    this.officeAddress,
    this.officeLat,
    this.officeLng,
    this.isAdmin = false,
    this.isOnboardingCompleted = false,
    this.settings = const {},
    this.selectedHolidays,
    this.customHolidays,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'officeLocation': officeLocation,
      'officeAddress': officeAddress,
      'officeLat': officeLat,
      'officeLng': officeLng,
      'isAdmin': isAdmin,
      'isOnboardingCompleted': isOnboardingCompleted,
      'settings': settings,
      'selectedHolidays': selectedHolidays,
      'customHolidays': customHolidays?.map((h) => h.toMap()).toList(),
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] ?? '',
      email: map['email'] ?? '',
      displayName: map['displayName'],
      photoUrl: map['photoUrl'],
      officeLocation: map['officeLocation'],
      officeAddress: map['officeAddress'],
      officeLat: map['officeLat'],
      officeLng: map['officeLng'],
      isAdmin: map['isAdmin'] ?? false,
      isOnboardingCompleted: map['isOnboardingCompleted'] ?? false,
      settings: map['settings'] ?? {},
      selectedHolidays: map['selectedHolidays'] != null
          ? List<String>.from(map['selectedHolidays'])
          : null,
      customHolidays: map['customHolidays'] != null
          ? (map['customHolidays'] as List)
                .map(
                  (hMap) => Holiday.fromMap(
                    hMap as Map<String, dynamic>,
                    hMap['id'] as String,
                  ),
                )
                .toList()
          : null,
    );
  }
}
