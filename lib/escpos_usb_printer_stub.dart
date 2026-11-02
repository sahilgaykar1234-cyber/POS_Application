class EscPosUsbPrinter {
  static bool get isSupported => false;

  static Future<void> printReceipt({
    required Map<String, dynamic> order,
    required Map<String, dynamic> settings,
    String? orderId,
  }) async {
    throw UnsupportedError('USB printing sirf web (Chrome/Edge) par available hai.');
  }
}