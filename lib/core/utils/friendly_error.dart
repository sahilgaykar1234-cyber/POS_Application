import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Turns any error into a short sentence for staff. The technical details
/// go to the debug console only – users never see raw Firebase messages,
/// codes or links.
///
///   friendlyError(e, 'save the plan')
///   → "Could not save the plan. Please check the internet connection and try again."
String friendlyError(Object? error, [String? action]) {
  debugPrint('Error${action == null ? '' : ' ($action)'}: $error');
  final prefix = action == null ? '' : 'Could not $action. ';
  return '$prefix${_reason(error)}';
}

String _reason(Object? e) {
  if (e is TimeoutException) return 'The connection is slow. Please try again.';
  if (e is FirebaseException) {
    return switch (e.code) {
      'permission-denied' => 'You don\'t have permission to do this.',
      'unauthenticated' => 'Your session has expired. Please sign in again.',
      'unavailable' || 'deadline-exceeded' || 'network-request-failed' => 'Please check the internet connection and try again.',
      'not-found' => 'It no longer exists. Please refresh.',
      'already-exists' => 'It already exists.',
      'resource-exhausted' => 'Too many requests right now. Please try again in a minute.',
      'failed-precondition' => 'This isn\'t set up on the server yet. Please try again later.',
      _ => 'Something went wrong. Please try again.',
    };
  }
  final s = '$e'.toLowerCase();
  if (s.contains('network') || s.contains('offline') || s.contains('failed to fetch')) {
    return 'Please check the internet connection and try again.';
  }
  return 'Something went wrong. Please try again.';
}

/// Printer problems in plain words.
String friendlyPrintError(Object? error) {
  debugPrint('Print error: $error');
  final s = '$error'.toLowerCase();
  if (s.contains('no device selected') || s.contains('notfounderror')) return 'No printer was selected.';
  if (s.contains('sirf web') || s.contains('unsupported')) return 'Printing is available in the web app.';
  if (s.contains('securityerror') || s.contains('access denied')) return 'The browser did not allow access to the printer.';
  return 'Could not print. Check that the printer is on and connected, then try again.';
}
