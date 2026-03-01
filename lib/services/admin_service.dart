import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/office_location.dart';
import '../data/models/user_profile.dart'; // Added UserProfile import
import '../data/models/holiday.dart'; // Added Holiday import
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
    final docRef = _firestore.collection('holidays').doc();
    final holiday = Holiday(
      id: docRef.id,
      date: date,
      name: name,
      officeLocations: officeLocations ?? [],
      isRecurring: isRecurring,
    );

    await docRef.set(holiday.toMap());
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

  Stream<List<Holiday>> getHolidaysStream() {
    return _firestore.collection('holidays').orderBy('date').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) {
        return Holiday.fromMap(doc.data(), doc.id);
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

  Future<void> updateOfficeLocation(OfficeLocation location) async {
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

  // --- Users ---

  Stream<List<UserProfile>> getUsersStream() {
    return _firestore.collection('users').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return UserProfile.fromMap(doc.data());
      }).toList();
    });
  }

  Future<void> updateUserRole(String uid, bool isAdmin) async {
    await _firestore.collection('users').doc(uid).update({'isAdmin': isAdmin});
  }

  // --- Feedback ---

  Stream<List<Map<String, dynamic>>> getFeedbackStream() {
    return _firestore
        .collection('feedback')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
        });
  }

  Future<void> deleteFeedback(String id) async {
    await _firestore.collection('feedback').doc(id).delete();
  }
}

final adminServiceProvider = Provider<AdminService>((ref) => AdminService());

final sortedHolidaysProvider = StreamProvider<List<Holiday>>((ref) {
  return ref.watch(adminServiceProvider).getHolidaysStream().map((holidays) {
    holidays.sort((a, b) {
      return a.date.compareTo(b.date);
    });
    return holidays;
  });
});

final usersStreamProvider = StreamProvider<List<UserProfile>>((ref) {
  return ref.watch(adminServiceProvider).getUsersStream();
});

final holidaysStreamProvider = StreamProvider<List<DateTime>>((ref) {
  final adminService = ref.watch(adminServiceProvider);
  final userProfileAsync = ref.watch(userProfileProvider);

  return adminService.getHolidaysStream().map((list) {
    final userOffice = userProfileAsync.value?.officeLocation;

    return list
        .where((holiday) {
          final offices = holiday.officeLocations;

          if (offices.isEmpty || offices.contains('All Offices')) {
            return true;
          }

          if (userOffice != null && offices.contains(userOffice)) {
            return true;
          }

          return false;
        })
        .expand<DateTime>((holiday) {
          final date = holiday.date;
          final isRecurring = holiday.isRecurring;

          if (!isRecurring) {
            return [date];
          }

          // If recurring, generate dates for current year and next year
          final currentYear = DateTime.now().year;
          return [
            DateTime(currentYear - 1, date.month, date.day),
            DateTime(currentYear, date.month, date.day),
            DateTime(currentYear + 1, date.month, date.day),
            DateTime(currentYear + 2, date.month, date.day),
          ];
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

final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(userProfileProvider).value?.isAdmin ?? false;
});

final feedbackStreamProvider = StreamProvider<List<Map<String, dynamic>>>((
  ref,
) {
  final adminService = ref.watch(adminServiceProvider);
  return adminService.getFeedbackStream();
});
