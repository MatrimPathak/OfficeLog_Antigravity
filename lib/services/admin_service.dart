import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/office_location.dart';

class AdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- Holidays ---

  Future<void> addHoliday(DateTime date, String name) async {
    final id = '${date.year}_${date.month}_${date.day}';
    await _firestore.collection('holidays').doc(id).set({
      'date': Timestamp.fromDate(date),
      'name': name,
    });
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
  return adminService.getHolidaysStream().map((list) {
    return list.map((item) => (item['date'] as Timestamp).toDate()).toList();
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
