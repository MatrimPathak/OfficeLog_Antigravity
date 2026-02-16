import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../data/models/user_profile.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // GoogleSignIn is a singleton in v7
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<User?> signInWithGoogle() async {
    try {
      // 1. Authenticate (Interactive)
      final GoogleSignInAccount account = await GoogleSignIn.instance
          .authenticate();

      // 2. Get ID Token
      final GoogleSignInAuthentication googleAuth = account.authentication;

      // 3. Get Access Token (Authorization)
      // Provide empty scopes to get base token, or required scopes if any.
      final GoogleSignInClientAuthorization authz = await account
          .authorizationClient
          .authorizeScopes(['email', 'openid']);

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: authz.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      final User? user = userCredential.user;

      if (user != null) {
        await _saveUserToFirestore(user);
      }

      return user;
    } on GoogleSignInException catch (e) {
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    } catch (e, stack) {
      debugPrint('General Sign-In Error: $e\n$stack');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  Future<void> deleteUserAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;

    try {
      // 1. Re-authenticate (Required for sensitive operations like delete)
      // Sign out of Google first to avoid session conflicts (error code 16)
      await GoogleSignIn.instance.signOut();
      final GoogleSignInAccount account = await GoogleSignIn.instance
          .authenticate();

      final GoogleSignInAuthentication googleAuth = account.authentication;
      final GoogleSignInClientAuthorization authz = await account
          .authorizationClient
          .authorizeScopes(['email', 'openid']);

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: authz.accessToken,
        idToken: googleAuth.idToken,
      );

      await user.reauthenticateWithCredential(credential);

      // 2. Delete Attendance Logs from Firestore
      final attendanceRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('attendance');

      final attendanceDocs = await attendanceRef.get();
      final batch = _firestore.batch();
      for (var doc in attendanceDocs.docs) {
        batch.delete(doc.reference);
      }

      // 3. Delete User Profile from Firestore
      batch.delete(_firestore.collection('users').doc(uid));

      // Commit Firestore deletions
      await batch.commit();

      // 4. Clear local Hive box
      final box = await Hive.openBox<Map>('attendance_logs');
      await box.clear();

      // 5. Sign out from Google
      await GoogleSignIn.instance.signOut();

      // 6. Delete Firebase User
      await user.delete();
    } on FirebaseAuthException catch (e) {
      debugPrint(
        'Firebase Auth Error deleting account: ${e.code} - ${e.message}',
      );
      rethrow;
    } catch (e) {
      debugPrint('Error deleting account: $e');
      rethrow;
    }
  }

  Future<void> _saveUserToFirestore(User user) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final snapshot = await userRef.get();

    if (!snapshot.exists) {
      final newUser = UserProfile(
        id: user.uid,
        email: user.email ?? '',
        displayName: user.displayName,
        photoUrl: user.photoURL,
        settings: {},
      );
      await userRef.set(newUser.toMap());
    }
  }

  Stream<UserProfile?> getUserProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return UserProfile.fromMap(snapshot.data() as Map<String, dynamic>);
      }
      return null;
    });
  }

  Future<void> updateOfficeLocation(
    String uid,
    String location,
    double? lat,
    double? lng,
  ) async {
    await _firestore.collection('users').doc(uid).update({
      'officeLocation': location,
      'officeLat': lat,
      'officeLng': lng,
    });
  }

  Future<void> updateUserSettings(
    String uid,
    Map<String, dynamic> settings,
  ) async {
    await _firestore.collection('users').doc(uid).update({
      'settings': settings,
    });
  }
}
