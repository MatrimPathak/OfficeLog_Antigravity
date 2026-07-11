import 'package:cloud_firestore/cloud_firestore.dart';

class PlannedDaysService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String userId;

  PlannedDaysService(this.userId);

  CollectionReference get _plannedCollection =>
      _firestore.collection('users').doc(userId).collection('planned');

  String _docId(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Stream<List<DateTime>> getPlannedDatesStream() {
    return _plannedCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final ts = data['date'] as Timestamp;
        return ts.toDate();
      }).toList();
    });
  }

  /// Adds the date if not already planned, removes it if it is.
  Future<void> toggle(DateTime date) async {
    final normalized = DateTime(date.year, date.month, date.day);
    final docRef = _plannedCollection.doc(_docId(normalized));
    final snapshot = await docRef.get();
    if (snapshot.exists) {
      await docRef.delete();
    } else {
      await docRef.set({'date': Timestamp.fromDate(normalized)});
    }
  }

  Future<void> clear() async {
    final snapshot = await _plannedCollection.get();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
