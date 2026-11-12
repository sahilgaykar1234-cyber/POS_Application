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
    this.loginDisabled = false,
  });

  /// Turned off by the Super Admin (users/{uid}.status == "disabled").
  final bool loginDisabled;

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

  /// Role and cafe from the server-set token claims; for logins created in
  /// the Super Admin panel (no claims) from users/{uid}, which only the Super
  /// Admin can write. A Super Admin role is NEVER taken from the document.
  factory AppUser.resolve({
    required String uid,
    required String? email,
    required String? displayName,
    required Map<String, dynamic>? claims,
    Map<String, dynamic>? userDoc,
  }) {
    final base = AppUser.fromClaims(uid: uid, email: email, displayName: displayName, claims: claims);
    var role = base.role;
    var cafeId = base.cafeId;
    if (role == null && userDoc != null) {
      final docRole = UserRole.fromClaim(userDoc['role']);
      final docCafe = userDoc['cafeId'];
      if ((docRole == UserRole.manager || docRole == UserRole.captain) && docCafe is String && docCafe.isNotEmpty) {
        role = docRole;
        cafeId = docCafe;
      }
    }
    final docName = (userDoc?['displayName'] ?? '').toString().trim();
    return AppUser(
      uid: uid,
      email: base.email,
      displayName: docName.isNotEmpty ? docName : base.displayName,
      role: role,
      cafeId: cafeId,
      loginDisabled: role != UserRole.superAdmin && userDoc?['status'] == 'disabled',
    );
  }

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
