/// The three platform roles. Stored as Firebase Auth custom claims, which only
/// the backend can set — the app only ever reads them.
enum UserRole {
  superAdmin('superAdmin', 'Super Admin'),
  manager('manager', 'Manager'),
  captain('captain', 'Captain');

  const UserRole(this.claim, this.label);

  /// Value used in custom claims and Firestore `users/{uid}.role`.
  final String claim;
  final String label;

  static UserRole? fromClaim(Object? value) {
    for (final r in UserRole.values) {
      if (r.claim == value) return r;
    }
    return null;
  }
}

/// The signed-in user as seen by the app, built from verified token claims.
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.cafeId,
  });

  final String uid;
  final String email;
  final String displayName;

  /// null = account exists but has no role yet (not set up / revoked).
  final UserRole? role;

  /// The cafe this user belongs to. null for Super Admin.
  final String? cafeId;

  bool get isSuperAdmin => role == UserRole.superAdmin;
  bool get isManager => role == UserRole.manager;
  bool get isCaptain => role == UserRole.captain;

  /// Manager/Captain must be tied to a cafe to be usable.
  bool get hasValidAssignment =>
      role == UserRole.superAdmin || (role != null && (cafeId?.isNotEmpty ?? false));

  factory AppUser.fromClaims({
    required String uid,
    required String? email,
    required String? displayName,
    required Map<String, dynamic>? claims,
  }) {
    final c = claims ?? const {};
    final cafe = c['cafeId'];
    return AppUser(
      uid: uid,
      email: email ?? '',
      displayName: (displayName == null || displayName.isEmpty) ? (email ?? 'User') : displayName,
      role: UserRole.fromClaim(c['role']),
      cafeId: cafe is String && cafe.isNotEmpty ? cafe : null,
    );
  }
}
