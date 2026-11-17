import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:pos_app/core/i18n/tr.dart';

/// Turns any error into a short sentence for staff. The technical details
/// go to the debug console only – users never see raw Firebase messages,
/// codes or links.
///
///   friendlyError(e, 'save the plan')
///   → "Could not save the plan. Please check the internet connection and try again."
String friendlyError(Object? error, [String? action]) {
  debugPrint('Error${action == null ? '' : ' ($action)'}: $error');
  final prefix = action == null ? '' : tr('Could not {0}. ', [action]);
  return '$prefix${_reason(error)}';
}

String _reason(Object? e) {
  if (e is TimeoutException) return tr('The connection is slow. Please try again.');
  if (e is FirebaseException) {
    return switch (e.code) {
      'permission-denied' => tr('You don\'t have permission to do this.'),
      'unauthenticated' => tr('Your session has expired. Please sign in again.'),
      'unavailable' || 'deadline-exceeded' || 'network-request-failed' => tr('Please check the internet connection and try again.'),
      'not-found' => tr('It no longer exists. Please refresh.'),
      'already-exists' => tr('It already exists.'),
      'resource-exhausted' => tr('Too many requests right now. Please try again in a minute.'),
      'failed-precondition' => tr('This isn\'t set up on the server yet. Please try again later.'),
      _ => tr('Something went wrong. Please try again.'),
    };
  }
  final s = '$e'.toLowerCase();
  if (s.contains('network') || s.contains('offline') || s.contains('failed to fetch')) {
    return tr('Please check the internet connection and try again.');
  }
  return tr('Something went wrong. Please try again.');
}

/// Printer problems in plain words.
String friendlyPrintError(Object? error) {
  debugPrint('Print error: $error');
  final s = '$error'.toLowerCase();
  if (s.contains('no device selected') || s.contains('notfounderror')) return tr('No printer was selected.');
  if (s.contains('sirf web') || s.contains('unsupported')) return tr('Printing is available in the web app.');
  if (s.contains('securityerror') || s.contains('access denied')) return tr('The browser did not allow access to the printer.');
  return tr('Could not print. Check that the printer is on and connected, then try again.');
}
