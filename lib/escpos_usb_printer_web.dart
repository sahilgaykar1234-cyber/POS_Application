// ignore_for_file: avoid_web_libraries_in_flutter, avoid_print
// ESC/POS thermal printing over WebUSB (Flutter web, Chrome/Edge).
// pubspec.yaml me `web: ^1.0.0` hona chahiye.
import 'features/receipt/escpos_receipt.dart';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

extension type _UsbDevice._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> open();
  external JSPromise<JSAny?> close();
  external JSPromise<JSAny?> selectConfiguration(int configurationValue);
  external JSPromise<JSAny?> claimInterface(int interfaceNumber);
  external JSPromise<JSAny?> transferOut(int endpointNumber, JSUint8Array data);
  external JSObject? get configuration;
}

class EscPosUsbPrinter {
  static _UsbDevice? _device;
  static int _interfaceNumber = 0;
  static int _endpointNumber = 1;

  // ---------------------------------------------------------------- USB ----
  static JSObject? get _usb {
    final nav = globalContext['navigator'] as JSObject?;
    final u = nav?['usb'];
    if (u == null || u.isUndefinedOrNull) return null;
    return u as JSObject;
  }

  static bool get isSupported => _usb != null;

  /// Saved device bhool jao (retry ya printer badalne ke liye).
  static Future<void> forgetDevice() async {
    final d = _device;
    _device = null;
    if (d != null) {
      try {
        await d.close().toDart;
      } catch (_) {}
    }
  }

  /// Configuration me se OUT bulk endpoint dhundo.
  /// [strict] true ho to sirf printer class (7) / vendor specific (255)
  /// interface dekhta hai. Na mile to strict=false se dobara try hota hai.
  static bool _findEndpoint(JSObject cfg, {required bool strict}) {
    final ifaces = (cfg['interfaces'] as JSArray).toDart;
    for (final i in ifaces) {
      final io = i as JSObject;
      final alt = io['alternate'] as JSObject;
      if (strict) {
        final cls = (alt['interfaceClass'] as JSNumber).toDartInt;
        if (cls != 7 && cls != 255) continue;
      }
      final eps = (alt['endpoints'] as JSArray).toDart;
      for (final e in eps) {
        final eo = e as JSObject;
        final dir = (eo['direction'] as JSString).toDart;
        final type = (eo['type'] as JSString).toDart;
        if (dir == 'out' && type == 'bulk') {
          _interfaceNumber = (io['interfaceNumber'] as JSNumber).toDartInt;
          _endpointNumber = (eo['endpointNumber'] as JSNumber).toDartInt;
          return true;
        }
      }
    }
    return false;
  }

  static Future<_UsbDevice> _getDevice() async {
    if (_device != null) return _device!;
    final usb = _usb;
    if (usb == null) {
      throw Exception('Is browser me WebUSB nahi hai. Chrome/Edge use karein.');
    }

    final granted = (await usb
            .callMethod<JSPromise<JSArray<JSAny?>>>('getDevices'.toJS)
            .toDart)
        .toDart;

    JSObject? picked;
    if (granted.isNotEmpty) {
      picked = granted.first as JSObject;
    } else {
      // NOTE: ye button click ke andar se hi call hona chahiye.
      final opts = {'filters': <Object>[]}.jsify();
      picked = await usb
          .callMethod<JSPromise<JSObject>>('requestDevice'.toJS, opts)
          .toDart;
    }

    final dev = _UsbDevice._(picked);

    try {
      await dev.open().toDart;
    } catch (e) {
      print('USB open error: $e');
      throw Exception('Printer open nahi hua: $e');
    }

    try {
      if (dev.configuration == null) {
        await dev.selectConfiguration(1).toDart;
      }
    } catch (e) {
      print('USB selectConfiguration error: $e');
      try {
        await dev.close().toDart;
      } catch (_) {}
      throw Exception('Printer configuration select nahi hua: $e');
    }

    final cfg = dev.configuration!;
    var found = _findEndpoint(cfg, strict: true);
    if (!found) found = _findEndpoint(cfg, strict: false);
    if (!found) {
      try {
        await dev.close().toDart;
      } catch (_) {}
      throw Exception('Printer ka OUT endpoint nahi mila.');
    }

    try {
      await dev.claimInterface(_interfaceNumber).toDart;
    } catch (e) {
      // Asli error console (F12) me dikhega.
      print('claimInterface error: $e');
      _device = null;
      try {
        await dev.close().toDart;
      } catch (_) {}
      throw Exception(
          'Printer claim nahi hua: $e\n'
          '(1) Baaki saare tabs/Chrome windows band karein, '
          '(2) Windows me Zadig se WinUSB driver lagayein, '
          '(3) Linux me `sudo rmmod usblp` + udev rule check karein.');
    }

    _device = dev;
    return dev;
  }

  static Future<void> _send(Uint8List data) async {
    final dev = await _getDevice();
    try {
      const chunk = 512;
      for (int i = 0; i < data.length; i += chunk) {
        final end = (i + chunk < data.length) ? i + chunk : data.length;
        await dev
            .transferOut(_endpointNumber, data.sublist(i, end).toJS)
            .toDart;
      }
    } catch (e) {
      print('transferOut error: $e');
      await forgetDevice();
      rethrow;
    }
  }

  // ------------------------------------------------------------ Receipt -----
  static Future<void> printReceipt({
    required Map<String, dynamic> order,
    required Map<String, dynamic> settings,
    String? orderId,
  }) async =>
      _send(await EscPosReceipt.build(order: order, settings: settings, orderId: orderId));
}
