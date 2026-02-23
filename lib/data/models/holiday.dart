import 'package:cloud_firestore/cloud_firestore.dart';

class Holiday {
  final String id;
  final DateTime date;
  final String name;
  final List<String> officeLocations;
  final bool isRecurring;

  Holiday({
    required this.id,
    required this.date,
    required this.name,
    this.officeLocations = const [],
    this.isRecurring = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': Timestamp.fromDate(date),
      'name': name,
      'officeLocations': officeLocations,
      'isRecurring': isRecurring,
    };
  }

  factory Holiday.fromMap(Map<String, dynamic> map, String id) {
    return Holiday(
      id: id,
      date: (map['date'] as Timestamp).toDate(),
      name: map['name'] ?? '',
      officeLocations: map['officeLocations'] != null
          ? List<String>.from(map['officeLocations'])
          : (map['officeLocation'] != null
                ? [map['officeLocation'] as String]
                : []), // Legacy support
      isRecurring: map['isRecurring'] ?? false,
    );
  }
}
