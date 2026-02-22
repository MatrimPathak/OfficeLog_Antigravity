import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/office_location.dart';
import '../presentation/providers/providers.dart';

class AdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- Holidays ---

  Future<void> addHoliday(
    DateTime date,
    String name, [
    List<String>? officeLocations,
    bool isRecurring = false,
  ]) async {
    // For backwards compatibility and logical simplicity, if they select nothing we default to 'All Offices'
    final List<String> finalLocations =
        (officeLocations == null || officeLocations.isEmpty)
        ? ['All Offices']
        : officeLocations;

    // Sort to ensure consistent ID regardless of selection order
    final sortedLocations = List<String>.from(finalLocations)..sort();
    final locationSuffix = sortedLocations.contains('All Offices')
        ? ''
        : '_${sortedLocations.join("_").replaceAll(" ", "")}';

    final id =
        '${date.year}_${date.month}_${date.day}_${name.replaceAll(" ", "_")}$locationSuffix';

    await _firestore.collection('holidays').doc(id).set({
      'date': Timestamp.fromDate(date),
      'name': name,
      'officeLocations': finalLocations,
      'isRecurring': isRecurring,
    });
  }

  Future<void> updateHoliday(
    String oldId,
    DateTime newDate,
    String newName, [
    List<String>? newOfficeLocations,
    bool isRecurring = false,
  ]) async {
    // 1. Delete the old holiday
    await deleteHoliday(oldId);
    // 2. Add the new holiday
    await addHoliday(newDate, newName, newOfficeLocations, isRecurring);
  }

  Future<void> deleteHoliday(String id) async {
    await _firestore.collection('holidays').doc(id).delete();
  }

  Stream<List<Map<String, dynamic>>> getHolidaysStream() {
    return _firestore.collection('holidays').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data; // {id, date: Timestamp, name: String}
      }).toList();
    });
  }

  // --- Office Locations ---

  Future<void> addOfficeLocation(OfficeLocation location) async {
    await _firestore
        .collection('office_locations')
        .doc(location.id)
        .set(location.toMap());
  }

  Future<void> deleteOfficeLocation(String id) async {
    await _firestore.collection('office_locations').doc(id).delete();
  }

  Stream<List<OfficeLocation>> getOfficeLocationsStream() {
    return _firestore.collection('office_locations').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) {
        return OfficeLocation.fromMap(doc.data());
      }).toList();
    });
  }

  // --- Global Config ---

  Stream<Map<String, dynamic>> getGlobalConfigStream() {
    return _firestore
        .collection('config')
        .doc('global')
        .snapshots()
        .map((snapshot) => snapshot.data() ?? {});
  }

  Future<void> updateGlobalConfig(Map<String, dynamic> config) async {
    await _firestore
        .collection('config')
        .doc('global')
        .set(config, SetOptions(merge: true));
  }
}

final adminServiceProvider = Provider<AdminService>((ref) => AdminService());

final holidaysStreamProvider = StreamProvider<List<DateTime>>((ref) {
  final adminService = ref.watch(adminServiceProvider);
  final userProfileAsync = ref.watch(userProfileProvider);

  return adminService.getHolidaysStream().map((list) {
    // If we haven't loaded the user profile yet, or user has no office,
    // we still return "All Offices" and legacy holidays.
    final userOffice = userProfileAsync.value?.officeLocation;

    return list
        .where((item) {
          final legacyHolidayOffice = item['officeLocation'] as String?;
          final holidayOffices = (item['officeLocations'] as List<dynamic>?)
              ?.cast<String>();

          // Condition 1: Legacy 'All Offices' or new array containing 'All Offices'
          if (legacyHolidayOffice == 'All Offices' ||
              (holidayOffices?.contains('All Offices') ?? false) ||
              (legacyHolidayOffice == null && holidayOffices == null)) {
            return true;
          }

          // Condition 2: Target is specific to the user's office
          if (userOffice != null) {
            if (holidayOffices != null && holidayOffices.contains(userOffice)) {
              return true;
            }
            if (legacyHolidayOffice != null &&
                legacyHolidayOffice == userOffice) {
              return true;
            }
          }

          return false;
        })
        .expand<DateTime>((item) {
          final date = (item['date'] as Timestamp).toDate();
          final isRecurring = item['isRecurring'] as bool? ?? false;

          if (!isRecurring) {
            return [date];
          }

          // If recurring, generate dates for 100 years out starting from 2000
          // (or whichever bounds you prefer). Let's do 2000 to 2100.
          return List.generate(
            101, // 2000 to 2100 inclusive
            (index) => DateTime(2000 + index, date.month, date.day),
          );
        })
        .toList();
  });
});

final officeLocationsProvider = StreamProvider<List<OfficeLocation>>((ref) {
  final adminService = ref.watch(adminServiceProvider);
  return adminService.getOfficeLocationsStream();
});

final globalConfigProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final adminService = ref.watch(adminServiceProvider);
  return adminService.getGlobalConfigStream();
});
