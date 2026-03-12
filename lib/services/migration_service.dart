import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class MigrationService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Call this method immediately after a user successfully logs in.
  Future<void> autoMigrateUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("MigrationService: No authenticated user found. Skipping migration.");
      return;
    }

    try {
      debugPrint("MigrationService: Triggering auto-migration for user ${user.uid} (${user.email})...");

      // Call the cloud function. The function will verify via context.auth natively.
      final HttpsCallable callable = _functions.httpsCallable('autoMigrateUser');
      
      final result = await callable.call();
      
      final data = (result.data as Map?)?.cast<String, dynamic>() ?? {};
      
      if (data['success'] == true) {
        debugPrint("MigrationService: Migration completed successfully! Message: ${data['message']}");
      } else {
        debugPrint("MigrationService: Migration finished but returned false. Data: $data");
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint("MigrationService: Caught FirebaseFunctionsException!");
      debugPrint("Code: ${e.code}");
      debugPrint("Message: ${e.message}");
      debugPrint("Details: ${e.details}");
    } catch (e, stacktrace) {
      debugPrint("MigrationService: An unknown error occurred during auto-migration: $e\n$stacktrace");
    }
  }
}

/*
// Example Usage in Auth Service after login:
// ==========================================
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'migration_service.dart';

Future<UserCredential?> signInWithEmail(String email, String password) async {
  try {
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email, 
      password: password
    );
    
    // Trigger migration asynchronously after successful login
    if (credential.user != null) {
      MigrationService().autoMigrateUserData().catchError((e) {
        // Fire and forget; don't block the UI login flow for an background migration error
        debugPrint("Background migration failed: $e");
      });
    }
    
    return credential;
  } catch (e) {
    debugPrint("Login error: $e");
    return null;
  }
}
*/
