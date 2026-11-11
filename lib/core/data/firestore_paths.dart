import 'package:cloud_firestore/cloud_firestore.dart';

/// Single source of truth for every Firestore location the app reads/writes.
///
/// Phase 1: these point at the existing (global, single-cafe) collections, so
/// behaviour is unchanged. In the multi-tenant migration these getters will
/// switch to `cafes/{cafeId}/...` and every screen follows automatically.
///
/// Rule for new code: never call `FirebaseFirestore.instance.collection(...)`
/// directly from a widget — add a getter here instead.
class FirestorePaths {
  FirestorePaths._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // Existing (legacy, pre-multi-tenant) collection names.
  static const String ordersCollection = 'orders';
  static const String menuCategoriesCollection = 'menu_categories';
  static const String settingsCollection = 'settings';
  static const String businessSettingsDocId = 'business_settings';

  /// Customer orders (POS bills). Doc IDs are also used as bill numbers,
  /// so they must be preserved during any migration.
  static CollectionReference<Map<String, dynamic>> orders() =>
      _db.collection(ordersCollection);

  /// Menu categories, each holding an `items` array.
  static CollectionReference<Map<String, dynamic>> menuCategories() =>
      _db.collection(menuCategoriesCollection);

  /// Cafe business/receipt settings (single document).
  static DocumentReference<Map<String, dynamic>> businessSettings() =>
      _db.collection(settingsCollection).doc(businessSettingsDocId);

  // ---- Platform collections (multi-tenant). Written only by the backend. ----

  /// Staff profiles: users/{uid} {email, displayName, role, cafeId, status}.
  /// Mirrors the Auth custom claims; claims remain the source of truth.
  static CollectionReference<Map<String, dynamic>> users() => _db.collection('users');

  /// Cafes: cafes/{cafeId} {name, status, legacyData, ...}.
  static CollectionReference<Map<String, dynamic>> cafes() => _db.collection('cafes');

  static DocumentReference<Map<String, dynamic>> cafe(String cafeId) => cafes().doc(cafeId);
}
