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
  if (s == 'printer:bt-connect') return tr('Could not connect to the Bluetooth printer. Turn it on, keep it close, and disconnect it from other phones.');
  if (s == 'printer:station-no-printer') return tr('Choose this device\'s printer: tap Connect printer.');
  if (s == 'printer:bt-write') return tr('The printer is connected but the print did not go through. Turn the printer off and on, then try again.');
  if (s == 'printer:bt-not-printer') return tr('That device is not a supported Bluetooth printer. Tap Print again and choose your printer.');
  if (s.startsWith('printer:bt-unsupported')) {
    final parts = '$error'.replaceFirst('printer:bt-unsupported', '').replaceFirst(':', '').split('|');
    final browser = parts.length > 1 ? parts[1] : '';
    return switch (parts.first) {
      'ios' => tr('iPhone browsers can\'t use Bluetooth. Install the free "Bluefy" browser from the App Store and open suratpos.web.app in it.'),
      'in-app' => tr('This page is open inside another app. Open suratpos.web.app in the Google Chrome app.'),
      'insecure' => tr('Bluetooth works only from https://suratpos.web.app. Open that address in Google Chrome.'),
      'browser' => tr('{0} can\'t use Bluetooth. Open suratpos.web.app in the Google Chrome app.', [browser]),
      _ => tr('Bluetooth is not available in this browser ({0}). Open suratpos.web.app in the Google Chrome app.', [browser]),
    };
  }
  if (s.contains('no device selected') || s.contains('notfounderror')) return tr('No printer was selected.');
  if (s.contains('sirf web') || s.contains('unsupported')) return tr('Printing is available in the web app.');
  if (s.contains('securityerror') || s.contains('access denied')) return tr('The browser did not allow access to the printer.');
  return tr('Could not print. Check that the printer is on and connected, then try again.');
}
