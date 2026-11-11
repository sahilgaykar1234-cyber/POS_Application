/// Platform-wide constants. The product is a generic multi-cafe POS; each
/// cafe's own name/logo comes from its data, never from here.
class AppConfig {
  AppConfig._();

  static const String appName = 'Cafe POS';
  static const String appTagline = 'Point of Sale for Cafes & Restaurants';

  /// Must match `setGlobalOptions({ region })` in functions/index.js.
  static const String functionsRegion = 'asia-south1';
}
