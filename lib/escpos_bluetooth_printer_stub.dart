import 'features/receipt/bluetooth_printer_logic.dart';

class EscPosBluetoothPrinter {
  static bool get isSupported => false;

  static Future<void> forgetDevice() async {}

  static Future<void> connect() async => throw const PrinterProblem('bt-unsupported');

  static Future<void> printReceipt({
    required Map<String, dynamic> order,
    required Map<String, dynamic> settings,
    String? orderId,
  }) async =>
      throw const PrinterProblem('bt-unsupported');
}
