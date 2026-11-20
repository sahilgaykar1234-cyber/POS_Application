// ESC/POS thermal printing over Bluetooth Low Energy (Web Bluetooth:
// Chrome / Edge on Android, Windows, Mac, ChromeOS). Not available on iPhone.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/receipt/bluetooth_printer_logic.dart';
import 'features/receipt/escpos_receipt.dart';

class EscPosBluetoothPrinter {
  EscPosBluetoothPrinter._();

  static const _prefKey = 'cafe_pos_bluetooth_printer';

  static JSObject? _device;
  static JSObject? _char;
  static bool _withResponse = true;

  static JSObject? get _bluetooth {
    final nav = globalContext['navigator'] as JSObject?;
    final b = nav?['bluetooth'];
    if (b == null || b.isUndefinedOrNull) return null;
    return b as JSObject;
  }

  static bool get isSupported => _bluetooth != null;

  /// Thrown when this browser can't use Bluetooth, saying why.
  static PrinterProblem _unsupported() {
    final ua = ((globalContext['navigator'] as JSObject?)?['userAgent'] as JSString?)?.toDart ?? '';
    final secure = globalContext['isSecureContext'].dartify() == true;
    final reason = bluetoothBlockedReason(userAgent: ua, hasApi: false, secure: secure);
    return PrinterProblem('bt-unsupported:$reason|${browserLabel(ua)}');
  }

  /// Forget the printer: the next print shows the device list again.
  static Future<void> forgetDevice() async {
    final gatt = _device?['gatt'] as JSObject?;
    _device = null;
    _char = null;
    try {
      gatt?.callMethod('disconnect'.toJS);
    } catch (_) {}
    try {
      await (await SharedPreferences.getInstance()).remove(_prefKey);
    } catch (_) {}
  }

  /// The printer chosen before, if the browser still allows it.
  static Future<JSObject?> _rememberedDevice(JSObject bt) async {
    if (!bt.has('getDevices')) return null;
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_prefKey);
      if (saved == null) return null;
      final allowed = (await bt.callMethod<JSPromise<JSArray<JSObject>>>('getDevices'.toJS).toDart).toDart;
      for (final d in allowed) {
        if ((d['id'] as JSString?)?.toDart == saved) return d;
      }
    } catch (_) {}
    return null;
  }

  /// The browser's device list. Must run soon after a tap (browser rule).
  static Future<JSObject> _requestDevice(JSObject bt) {
    final options = {'acceptAllDevices': true, 'optionalServices': kPrinterServices}.jsify();
    return bt.callMethod<JSPromise<JSObject>>('requestDevice'.toJS, options).toDart;
  }

  static Future<JSObject> _connect(JSObject device) =>
      (device['gatt'] as JSObject).callMethod<JSPromise<JSObject>>('connect'.toJS).toDart;

  /// Connects to the printer used before; if that fails (for example it was
  /// not heard yet since the page opened) the device list opens so the
  /// printer is simply picked again.
  static Future<(JSObject, JSObject)> _connectPrinter(JSObject bt) async {
    final known = _device ?? await _rememberedDevice(bt);
    if (known != null) {
      try {
        return (known, await _connect(known));
      } catch (e) {
        debugPrint('Bluetooth connect (saved printer): $e');
        _device = null;
      }
    }
    final picked = await _requestDevice(bt);
    try {
      return (picked, await _connect(picked));
    } catch (e) {
      debugPrint('Bluetooth connect: $e');
      throw const PrinterProblem('bt-connect');
    }
  }

  static Future<JSObject> _characteristic() async {
    final device = _device;
    final connected = (device?['gatt'] as JSObject?)?['connected'];
    if (_char != null && connected.dartify() == true) return _char!;

    final bt = _bluetooth;
    if (bt == null) throw _unsupported();
    final (picked, server) = await _connectPrinter(bt);

    final found = <BtCharacteristic>[];
    try {
      final services = (await server.callMethod<JSPromise<JSArray<JSObject>>>('getPrimaryServices'.toJS).toDart).toDart;
      for (final service in services) {
        final chars = (await service.callMethod<JSPromise<JSArray<JSObject>>>('getCharacteristics'.toJS).toDart).toDart;
        for (final c in chars) {
          final props = c['properties'] as JSObject;
          bool flag(String k) => (props[k] as JSBoolean?)?.toDart ?? false;
          found.add(BtCharacteristic((c['uuid'] as JSString).toDart,
              write: flag('write'), writeWithoutResponse: flag('writeWithoutResponse'), handle: c));
        }
      }
    } catch (e) {
      debugPrint('Bluetooth services: $e');
    }
    final best = pickPrinterCharacteristic(found);
    if (best == null) {
      try {
        server.callMethod('disconnect'.toJS);
      } catch (_) {}
      _device = null;
      throw const PrinterProblem('bt-not-printer');
    }

    _device = picked;
    _char = best.handle as JSObject;
    _withResponse = best.write || !_char!.has('writeValueWithoutResponse');
    try {
      final id = (picked['id'] as JSString?)?.toDart;
      if (id != null) await (await SharedPreferences.getInstance()).setString(_prefKey, id);
    } catch (_) {}
    return _char!;
  }

  static Future<void> _send(Uint8List data) async {
    final c = await _characteristic();
    try {
      for (final part in chunked(data)) {
        if (_withResponse) {
          // The printer confirms each piece: slower, but nothing is lost.
          final method = c.has('writeValueWithResponse') ? 'writeValueWithResponse' : 'writeValue';
          await c.callMethod<JSPromise<JSAny?>>(method.toJS, part.toJS).toDart;
        } else {
          await c.callMethod<JSPromise<JSAny?>>('writeValueWithoutResponse'.toJS, part.toJS).toDart;
          // Give the printer's small buffer time to empty.
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }
      }
    } catch (e) {
      debugPrint('Bluetooth write: $e');
      _char = null; // reconnect next time
      throw const PrinterProblem('bt-write');
    }
  }

  static Future<void> printReceipt({
    required Map<String, dynamic> order,
    required Map<String, dynamic> settings,
    String? orderId,
  }) async =>
      _send(await EscPosReceipt.build(order: order, settings: settings, orderId: orderId));
}
