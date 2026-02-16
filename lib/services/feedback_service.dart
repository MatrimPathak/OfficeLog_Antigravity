import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> submitFeedback({
    required String userId,
    required String userEmail,
    required int rating,
    required String message,
  }) async {
    await _firestore.collection('feedback').add({
      'userId': userId,
      'userEmail': userEmail,
      'rating': rating,
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
