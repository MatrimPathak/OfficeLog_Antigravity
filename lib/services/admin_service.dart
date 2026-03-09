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

  Future<void> batchAddHolidays(List<Holiday> holidays) async {
    // Firestore batches have a limit of 500 writes per batch
    final batchSize = 500;

    for (int i = 0; i < holidays.length; i += batchSize) {
      final batch = _firestore.batch();
      final end = (i + batchSize < holidays.length)
          ? i + batchSize
          : holidays.length;
      final currentBatch = holidays.sublist(i, end);

      for (final holiday in currentBatch) {
        final docRef = _firestore.collection('holidays').doc();

        final newHoliday = Holiday(
          id: docRef.id,
          date: holiday.date,
          name: holiday.name,
          officeLocations: holiday.officeLocations,
          isRecurring: holiday.isRecurring,
        );

        batch.set(docRef, newHoliday.toMap());
      }

      await batch.commit();
    }
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

final globalHolidaysStreamProvider = StreamProvider<List<Holiday>>((ref) {
  return ref.watch(adminServiceProvider).getHolidaysStream();
});

final sortedHolidaysProvider = Provider<AsyncValue<List<Holiday>>>((ref) {
  final globalAsync = ref.watch(globalHolidaysStreamProvider);
  final userProfileAsync = ref.watch(userProfileProvider);

  return globalAsync.when(
    data: (globalHolidays) {
      final customHolidays = userProfileAsync.value?.customHolidays ?? [];
      final allHolidays = [...globalHolidays, ...customHolidays];

      allHolidays.sort((a, b) => a.date.compareTo(b.date));
      return AsyncValue.data(allHolidays);
    },
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});

final userSelectedHolidaysProvider = Provider<AsyncValue<List<Holiday>>>((ref) {
  final sortedAsync = ref.watch(sortedHolidaysProvider);
  final userProfileAsync = ref.watch(userProfileProvider);

  return sortedAsync.when(
    data: (allHolidays) {
      final selectedIds = userProfileAsync.value?.selectedHolidays ?? [];
      final filtered = allHolidays
          .where((h) => selectedIds.contains(h.id))
          .toList();
      return AsyncValue.data(filtered);
    },
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});

final usersStreamProvider = StreamProvider<List<UserProfile>>((ref) {
  return ref.watch(adminServiceProvider).getUsersStream();
});

final holidaysStreamProvider = StreamProvider<List<DateTime>>((ref) {
  final adminService = ref.watch(adminServiceProvider);
  final userProfileAsync = ref.watch(userProfileProvider);

  return adminService.getHolidaysStream().map((list) {
    final selectedHolidays = userProfileAsync.value?.selectedHolidays;
    final customHolidays = userProfileAsync.value?.customHolidays ?? [];

    // Prepend user's custom holidays so they are evaluated with the rest
    final mergedList = [...customHolidays, ...list];

    return mergedList
        .where((holiday) {
          if (selectedHolidays != null) {
            return selectedHolidays.contains(holiday.id);
          }
          return false; // Default: none selected until user explicitly saves
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
