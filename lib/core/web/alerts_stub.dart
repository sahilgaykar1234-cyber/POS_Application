/// Non-web platforms: no browser sound / system notifications.
void playOrderChime() {}

bool get systemAlertsSupported => false;

/// 'granted', 'denied' or 'default'.
String get systemAlertPermission => 'denied';

Future<String> requestSystemAlerts() async => 'denied';

/// Shows an OS notification, only while the app tab is in the background.
void showSystemAlert(String title, String body, {String? tag}) {}
