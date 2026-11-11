import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../data/firestore_paths.dart';
import '../theme/theme_controller.dart';
import 'app_user.dart';

/// All authentication goes through here. Passwords are handled entirely by
/// Firebase Authentication — the app never stores or sees them.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// The user for the current session, set by [AuthGate] once claims load.
  /// Screens read this instead of re-fetching the token.
  AppUser? currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Builds the [AppUser] from a *fresh* ID token so role changes made by an
  /// admin take effect on next sign-in/refresh.
  Future<AppUser> loadAppUser(User user) async {
    final token = await user.getIdTokenResult(true);
    final appUser = AppUser.fromClaims(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      claims: token.claims,
    );
    currentUser = appUser;
    return appUser;
  }

  /// [identifier] is a username (e.g. "flammywood") or an email.
  Future<void> signIn({required String identifier, required String password}) async {
    await _auth.signInWithEmailAndPassword(
      email: AppConfig.loginEmail(identifier),
      password: AppConfig.loginPassword(identifier, password),
    );
    // Mark an invited (email) account as active. Shared username logins are
    // created active already, so skip the call. Best-effort: never blocks sign-in.
    if (AppConfig.isUsername(identifier.trim())) return;
    try {
      await FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion)
          .httpsCallable('confirmFirstSignIn')
          .call();
    } catch (e) {
      debugPrint('confirmFirstSignIn skipped: $e');
    }
  }

  /// Sends Firebase's password reset email. Used for "Forgot password" and as
  /// the delivery channel for staff invites and admin-initiated resets.
  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() async {
    currentUser = null;
    FirestorePaths.setActiveCafe(null);
    ThemeController.instance.legacyAdmin.value = false;
    await _auth.signOut();
  }

  /// Turns Firebase error codes into short messages staff can understand.
  /// Deliberately vague for wrong email vs wrong password (security).
  static String friendlyError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
        case 'invalid-login-credentials':
          return 'Incorrect username or password.';
        case 'invalid-email':
          return 'Please enter a valid username or email.';
        case 'user-disabled':
          return 'This account has been disabled. Please contact your manager.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a few minutes and try again.';
        case 'network-request-failed':
          return 'No internet connection. Please check your network.';
      }
      return error.message ?? 'Sign-in failed. Please try again.';
    }
    if (error is FirebaseFunctionsException) {
      return error.message ?? 'Request failed. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}
