/// Platform-wide constants. The product is a generic multi-cafe POS; each
/// cafe's own name/logo comes from its data, never from here.
class AppConfig {
  AppConfig._();

  static const String appName = 'Cafe POS';
  static const String appTagline = 'Point of Sale for Cafes & Restaurants';

  /// Must match `setGlobalOptions({ region })` in functions/index.js.
  static const String functionsRegion = 'asia-south1';

  // ---------------------------------------------------------------------------
  // Username logins (e.g. "flammywood" / "123").
  //
  // Firebase Auth needs an email and a 6+ character password, so a username
  // login is stored as a Firebase account "<username>@pos.example.com" and the
  // typed PIN is prefixed before it is sent. Nothing is stored in Firestore.
  // MUST stay identical to tools/admin/lib/login.js.
  // ---------------------------------------------------------------------------
  static const String usernameDomain = 'pos.example.com';
  static const String pinPrefix = 'cafepos-';

  static bool isUsername(String input) => !input.contains('@');

  /// What the user typed (username or email) → Firebase Auth email.
  static String loginEmail(String input) {
    final s = input.trim().toLowerCase();
    return isUsername(s) ? '$s@$usernameDomain' : s;
  }

  /// What the user typed as password → Firebase Auth password.
  static String loginPassword(String identifier, String password) =>
      isUsername(identifier.trim()) ? '$pinPrefix$password' : password;

  /// "flammywood@pos.example.com" → "flammywood" (for display).
  static String displayLogin(String email) =>
      email.endsWith('@$usernameDomain') ? email.substring(0, email.length - usernameDomain.length - 1) : email;
}
