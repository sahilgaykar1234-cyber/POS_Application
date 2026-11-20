import 'dart:typed_data';

/// Bluetooth (BLE) services that cheap thermal receipt printers use for
/// ESC/POS. The browser only lets the app talk to services listed here.
const kPrinterServices = [
  '000018f0-0000-1000-8000-00805f9b34fb', // most 58 mm printers (char 2af1)
  'e7810a71-73ae-499d-8c15-faa9aef0c3f2',
  '49535343-fe7d-4ae5-8fa9-9fafd205e455', // ISSC / Microchip modules
  '0000ff00-0000-1000-8000-00805f9b34fb',
  '0000ffe0-0000-1000-8000-00805f9b34fb',
  '0000fee7-0000-1000-8000-00805f9b34fb',
  '0000ae30-0000-1000-8000-00805f9b34fb',
  '0000fff0-0000-1000-8000-00805f9b34fb',
  '6e400001-b5a3-f393-e0a9-e50e24dcca9e', // Nordic UART
];

/// Characteristics known to accept print data, best first.
const kPrinterCharacteristics = [
  '00002af1-0000-1000-8000-00805f9b34fb',
  'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f',
  '49535343-8841-43f4-a8d4-ecbe34729bb3',
  '0000ff02-0000-1000-8000-00805f9b34fb',
  '0000ffe1-0000-1000-8000-00805f9b34fb',
  '0000ae01-0000-1000-8000-00805f9b34fb',
  '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
];

/// Bytes per Bluetooth write. 20 works on every printer (smallest packet).
const kBluetoothChunk = 20;

class BtCharacteristic {
  const BtCharacteristic(this.uuid, {this.write = false, this.writeWithoutResponse = false, this.handle});
  final String uuid;
  final bool write;
  final bool writeWithoutResponse;

  /// The browser object behind it (web only).
  final Object? handle;

  bool get writable => write || writeWithoutResponse;
}

/// The characteristic to send the receipt to: a known printer one first,
/// otherwise any writable one. null = this device can't print.
BtCharacteristic? pickPrinterCharacteristic(List<BtCharacteristic> all) {
  final writable = all.where((c) => c.writable).toList();
  for (final known in kPrinterCharacteristics) {
    final hit = writable.where((c) => c.uuid.toLowerCase() == known).firstOrNull;
    if (hit != null) return hit;
  }
  return writable.firstOrNull;
}

/// [data] cut into pieces of at most [size] bytes, in order.
List<Uint8List> chunked(Uint8List data, [int size = kBluetoothChunk]) => [
      for (var i = 0; i < data.length; i += size) Uint8List.sublistView(data, i, i + size > data.length ? data.length : i + size),
    ];

/// Why printing failed, shown to staff by friendlyPrintError.
class PrinterProblem implements Exception {
  const PrinterProblem(this.code);

  /// bt-unsupported:<reason>|<browser> | bt-not-printer | bt-connect | bt-write
  final String code;

  @override
  String toString() => 'printer:$code';
}

/// Why this browser can't use a Bluetooth printer (null = it can).
///   ios        iPhone / iPad: no browser there may use Bluetooth
///   in-app     opened inside WhatsApp, Instagram etc. (an app's web view)
///   browser    a browser without Bluetooth (Samsung Internet, Mi, Firefox …)
///   insecure   not opened from the https address
///   other      anything else
String? bluetoothBlockedReason({required String userAgent, required bool hasApi, required bool secure}) {
  if (hasApi) return null;
  final ua = userAgent.toLowerCase();
  if (ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod')) return 'ios';
  if (!secure) return 'insecure';
  if (RegExp(r'; wv\)|fban|fbav|instagram|whatsapp|line/|snapchat').hasMatch(ua)) return 'in-app';
  if (RegExp(r'samsungbrowser|miuibrowser|xiaomi/miuibrowser|firefox|fxios|ucbrowser|opr/|heytapbrowser|vivobrowser').hasMatch(ua)) return 'browser';
  return 'other';
}

/// Short browser name and version from a user agent, e.g. "Chrome 131".
String browserLabel(String userAgent) {
  for (final (name, pattern) in [
    ('Samsung Internet', r'SamsungBrowser/(\d+)'),
    ('Mi Browser', r'MiuiBrowser/(\d+)'),
    ('Firefox', r'Firefox/(\d+)'),
    ('Edge', r'Edg[A]?/(\d+)'),
    ('Opera', r'OPR/(\d+)'),
    ('Chrome', r'Chrome/(\d+)'),
    ('Safari', r'Version/(\d+).*Safari'),
  ]) {
    final m = RegExp(pattern).firstMatch(userAgent);
    if (m != null) return '$name ${m.group(1)}';
  }
  return 'unknown browser';
}
