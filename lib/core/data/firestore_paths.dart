import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Single source of truth for every Firestore location the app reads/writes.
///
/// Multi-tenant layout (each cafe's data is isolated under its own document):
///
///   cafes/{cafeId}                         cafe profile + subscription
///   cafes/{cafeId}/settings/business       receipt/business settings
///   cafes/{cafeId}/categories/{id}         menu categories
///   cafes/{cafeId}/subcategories/{id}      menu subcategories
///   cafes/{cafeId}/menuItems/{id}          menu items (variants + add-ons)
///   cafes/{cafeId}/orders/{id}             customer orders / bills
///   users/{uid}                            staff profiles (backend-written)
///   plans/{id}, subscriptionPayments/{id}  SaaS billing (Super Admin)
///   auditLogs/{id}, notifications/{id}
///
/// Firestore Security Rules (firestore.rules) enforce that a user can only
/// reach their own cafe; these helpers just keep the app consistent.
///
/// Rule for new code: never call `FirebaseFirestore.instance.collection(...)`
/// directly from a widget — add a getter here instead.
class FirestorePaths {
  FirestorePaths._();

  /// Tests can point the app at a fake Firestore.
  @visibleForTesting
  static FirebaseFirestore? overrideDb;

  static FirebaseFirestore get db => overrideDb ?? FirebaseFirestore.instance;
  static FirebaseFirestore get _db => db;

  // ---------------------------------------------------------------------------
  // Active cafe (set by AuthGate after sign-in from the user's verified claim).
  // ---------------------------------------------------------------------------

  static String? _activeCafeId;

  /// Called when the signed-in cafe changes (sign-in, sign-out), e.g. to
  /// close shared listeners of the previous cafe.
  static final List<void Function()> onCafeChanged = [];

  static void setActiveCafe(String? cafeId) {
    if (cafeId == _activeCafeId) return;
    _activeCafeId = cafeId;
    for (final f in [...onCafeChanged]) {
      f();
    }
  }

  /// The signed-in staff member's cafe. Throws if used before sign-in, which
  /// is a programming error (it can never silently fall back to another cafe).
  static String get activeCafeId {
    final id = _activeCafeId;
    if (id == null || id.isEmpty) {
      throw StateError('No active cafe. FirestorePaths.setActiveCafe() must be called after sign-in.');
    }
    return id;
  }

  static String _cafeOrActive(String? cafeId) => cafeId ?? activeCafeId;

  // ---------------------------------------------------------------------------
  // Cafe-scoped data
  // ---------------------------------------------------------------------------

  static const String settingsDocId = 'business';

  /// Customer orders (POS bills). Doc IDs double as bill numbers, so they are
  /// preserved by the migration.
  static CollectionReference<Map<String, dynamic>> orders([String? cafeId]) =>
      cafe(_cafeOrActive(cafeId)).collection('orders');

  /// Cafe business/receipt settings (single document).
  static DocumentReference<Map<String, dynamic>> businessSettings([String? cafeId]) =>
      cafe(_cafeOrActive(cafeId)).collection('settings').doc(settingsDocId);

  static CollectionReference<Map<String, dynamic>> categories([String? cafeId]) =>
      cafe(_cafeOrActive(cafeId)).collection('categories');

  static CollectionReference<Map<String, dynamic>> subcategories([String? cafeId]) =>
      cafe(_cafeOrActive(cafeId)).collection('subcategories');

  static CollectionReference<Map<String, dynamic>> menuItems([String? cafeId]) =>
      cafe(_cafeOrActive(cafeId)).collection('menuItems');

  // ---------------------------------------------------------------------------
  // Platform collections
  // ---------------------------------------------------------------------------

  /// Staff profiles: users/{uid} {email, displayName, role, cafeId, status}.
  /// Mirrors the Auth custom claims; claims remain the source of truth.
  static CollectionReference<Map<String, dynamic>> users() => _db.collection('users');

  static CollectionReference<Map<String, dynamic>> cafes() => _db.collection('cafes');

  static DocumentReference<Map<String, dynamic>> cafe(String cafeId) => cafes().doc(cafeId);

  static CollectionReference<Map<String, dynamic>> plans() => _db.collection('plans');

  /// Platform-wide settings of the SaaS (Super Admin only): platform/settings.
  static DocumentReference<Map<String, dynamic>> platformSettings() => _db.collection('platform').doc('settings');

  /// A cafe's subscription changes, newest first: cafes/{id}/subscriptionHistory.
  static CollectionReference<Map<String, dynamic>> subscriptionHistory(String cafeId) =>
      cafe(cafeId).collection('subscriptionHistory');

  static CollectionReference<Map<String, dynamic>> subscriptionPayments() =>
      _db.collection('subscriptionPayments');

  static CollectionReference<Map<String, dynamic>> auditLogs() => _db.collection('auditLogs');

  static CollectionReference<Map<String, dynamic>> notifications() => _db.collection('notifications');

  /// Counters (e.g. sequential subscription receipt numbers).
  static DocumentReference<Map<String, dynamic>> counter(String name) =>
      _db.collection('counters').doc(name);

  /// Per-cafe counters, e.g. the daily takeaway token: cafes/{id}/counters/{name}.
  static DocumentReference<Map<String, dynamic>> cafeCounter(String name, [String? cafeId]) =>
      cafe(_cafeOrActive(cafeId)).collection('counters').doc(name);

  // ---------------------------------------------------------------------------
  // Legacy (pre-multi-tenant) collection names. Read only by the migration
  // script; the app no longer touches them. Kept for documentation.
  // ---------------------------------------------------------------------------
  static const String legacyOrders = 'orders';
  static const String legacyMenuCategories = 'menu_categories';
  static const String legacySettingsDoc = 'settings/business_settings';
}
