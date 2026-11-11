// ignore_for_file: avoid_web_libraries_in_flutter, avoid_print
// ESC/POS thermal printing over WebUSB (Flutter web, Chrome/Edge).
// pubspec.yaml me `web: ^1.0.0` hona chahiye.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' as ui;

extension type _UsbDevice._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> open();
  external JSPromise<JSAny?> close();
  external JSPromise<JSAny?> selectConfiguration(int configurationValue);
  external JSPromise<JSAny?> claimInterface(int interfaceNumber);
  external JSPromise<JSAny?> transferOut(int endpointNumber, JSUint8Array data);
  external JSObject? get configuration;
}

class EscPosUsbPrinter {
  /// 58mm paper = 32 characters per line. 80mm wala ho to 48 kar dena.
  static const int lineWidth = 32;

  /// Logo ki width (dots). 58mm paper max 384. 160-200 achha lagta hai.
  static const int logoWidth = 160;

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

  // ------------------------------------------------------ ESC/POS basics ---
  static final List<int> _b = [];

  static void _raw(List<int> bytes) => _b.addAll(bytes);

  static void _text(String s) {
    for (final c in s.codeUnits) {
      _b.add(c < 128 ? c : 63); // non-ASCII -> '?'
    }
  }

  static void _line(String s) {
    _text(s);
    _b.add(0x0A);
  }

  static void _align(int n) => _raw([0x1B, 0x61, n]); // 0 left, 1 center, 2 right
  static void _bold(bool on) => _raw([0x1B, 0x45, on ? 1 : 0]);
  static void _size(int n) => _raw([0x1D, 0x21, n]); // 0x00 normal, 0x11 double, 0x01 tall
  static void _divider() => _line('-' * lineWidth);

  static String _s(dynamic v) => (v ?? '').toString().trim();

  // Receipt screen jaisa: hamesha 2 decimal (₹ printer me nahi hota, isliye Rs).
  static String _money(num v) => 'Rs ${v.toStringAsFixed(2)}';

  /// Words ke hisaab se wrap (word beech me nahi tutta).
  static List<String> _wrapWords(String text, int width) {
    final out = <String>[];
    var cur = '';
    for (var w in text.split(RegExp(r'\s+'))) {
      if (w.isEmpty) continue;
      while (w.length > width) {
        if (cur.isNotEmpty) {
          out.add(cur);
          cur = '';
        }
        out.add(w.substring(0, width));
        w = w.substring(width);
      }
      if (cur.isEmpty) {
        cur = w;
      } else if (cur.length + 1 + w.length <= width) {
        cur = '$cur $w';
      } else {
        out.add(cur);
        cur = w;
      }
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  /// Wrapped lines, current alignment me.
  static void _para(String s) {
    for (final l in _wrapWords(s, lineWidth)) {
      _line(l);
    }
  }

  /// Center me wrapped text (optional bold).
  static void _centerText(String s, {bool bold = false}) {
    if (s.isEmpty) return;
    _align(1);
    _bold(bold);
    _para(s);
    _bold(false);
    _align(0);
  }

  /// Left + right ek line me. Jagah na ho to 2 line me.
  static void _lr(String l, String r) {
    final pad = lineWidth - l.length - r.length;
    if (pad < 1) {
      _line(l);
      _align(2);
      _line(r);
      _align(0);
    } else {
      _line('$l${' ' * pad}$r');
    }
  }

  /// Shop name: chhota ho to bada font, lamba ho to 2 line, bahut lamba
  /// ho to normal bold font me wrap.
  static void _title(String name) {
    final t = name.trim();
    _align(1);
    _bold(true);
    final big = _wrapWords(t, lineWidth ~/ 2);
    if (big.length <= 2) {
      _size(0x11);
      for (final l in big) {
        _line(l);
      }
    } else {
      _size(0x00);
      _para(t);
    }
    _size(0x00);
    _bold(false);
    _align(0);
  }

  // ------------------------------------------------------------- Logo -------
  /// Base64 image -> ESC/POS raster bytes (GS v 0), Floyd-Steinberg dither.
  static Future<List<int>> _logoBytes(String b64) async {
    final bytes = base64Decode(b64);
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: logoWidth);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final w = img.width;
    final h = img.height;
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return [];

    // grayscale (transparent = white)
    final gray = List<double>.filled(w * h, 255);
    for (int i = 0; i < w * h; i++) {
      final r = bd.getUint8(i * 4);
      final g = bd.getUint8(i * 4 + 1);
      final bl = bd.getUint8(i * 4 + 2);
      final a = bd.getUint8(i * 4 + 3) / 255.0;
      final lum = 0.299 * r + 0.587 * g + 0.114 * bl;
      gray[i] = lum * a + 255 * (1 - a);
    }

    // dither
    final black = List<bool>.filled(w * h, false);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final i = y * w + x;
        final old = gray[i];
        final nw = old < 128 ? 0.0 : 255.0;
        black[i] = nw == 0.0;
        final err = old - nw;
        if (x + 1 < w) gray[i + 1] += err * 7 / 16;
        if (y + 1 < h) {
          if (x > 0) gray[i + w - 1] += err * 3 / 16;
          gray[i + w] += err * 5 / 16;
          if (x + 1 < w) gray[i + w + 1] += err * 1 / 16;
        }
      }
    }

    final wb = (w + 7) >> 3;
    final out = <int>[
      0x1D, 0x76, 0x30, 0x00,
      wb & 0xFF, (wb >> 8) & 0xFF,
      h & 0xFF, (h >> 8) & 0xFF,
    ];
    for (int y = 0; y < h; y++) {
      for (int xb = 0; xb < wb; xb++) {
        int byte = 0;
        for (int bit = 0; bit < 8; bit++) {
          final x = xb * 8 + bit;
          if (x < w && black[y * w + x]) byte |= (0x80 >> bit);
        }
        out.add(byte);
      }
    }
    return out;
  }

  // ----------------------------------------------------------- Helpers ------
  static String _cleanName(String raw) {
    return raw
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'table\s*\S*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // Receipt screen jaisa: order ID ke pehle 6 characters, uppercase.
  static String _billNo(String? orderId) {
    final id = orderId ?? '';
    if (id.isEmpty) return '';
    return '#${id.substring(0, id.length > 6 ? 6 : id.length).toUpperCase()}';
  }

  // Receipt screen jaisa: pehle completedAt, phir createdAt, warna abhi ka time.
  static DateTime _orderDate(Map<String, dynamic> order) {
    for (final key in ['completedAt', 'createdAt']) {
      final ts = order[key];
      if (ts != null) {
        try {
          return (ts as dynamic).toDate() as DateTime;
        } catch (_) {}
      }
    }
    return DateTime.now();
  }

  // ------------------------------------------------------------ Receipt -----
  /// [settings] keys: shopLogoBase64, shopName, tagline, address,
  /// mobileNumber, gstNumber, receiptHeader, receiptFooter, thankYouMessage
  static Future<void> printReceipt({
    required Map<String, dynamic> order,
    required Map<String, dynamic> settings,
    String? orderId,
  }) async {
    _b.clear();
    _raw([0x1B, 0x40]); // init

    // ---- Logo ----
    final logo = _s(settings['shopLogoBase64']);
    if (logo.isNotEmpty) {
      try {
        final bytes = await _logoBytes(logo);
        if (bytes.isNotEmpty) {
          _align(1);
          _raw(bytes);
          _b.add(0x0A);
          _align(0);
        }
      } catch (_) {
        // logo fail ho to bhi receipt print ho
      }
    }

    // ---- Shop details ----
    final shopName = _s(settings['shopName']);
    _title(shopName.isEmpty ? 'SHOP' : shopName.toUpperCase());
    _centerText(_s(settings['tagline']));
    _centerText(_s(settings['address']));
    final phoneShop = _s(settings['mobileNumber']);
    if (phoneShop.isNotEmpty) _centerText('Phone: $phoneShop', bold: true);
    final gst = _s(settings['gstNumber']);
    if (gst.isNotEmpty) _centerText('GSTIN: $gst', bold: true);

    _divider();
    _centerText(_s(settings['receiptHeader']));
    _divider();

    // ---- Bill info ----
    final dt = _orderDate(order);
    String two(int n) => n.toString().padLeft(2, '0');
    final dateStr =
        '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    final bill = _billNo(orderId);
    _lr(bill.isEmpty ? '' : 'Bill: $bill', dateStr);

    final tableNo = _s(order['tableNo']);
    final table = tableNo.isNotEmpty
        ? (tableNo.toLowerCase().contains('table') ? tableNo : 'Table $tableNo')
        : (order['tokenNo'] != null ? 'Takeaway - Token #${order['tokenNo']}' : 'Counter / Takeaway');
    final rawStatus = _s(order['paymentStatus']);
    final mode = (rawStatus.isEmpty ? 'PAID' : rawStatus)
        .replaceAll('paid_', '')
        .toUpperCase();
    _bold(true);
    _lr(table, 'Mode: $mode');
    _bold(false);

    final cname = _s(order['customerName']);
    if (cname.isNotEmpty && cname.toLowerCase() != 'walk-in guest') {
      _para('Customer: $cname');
      final cphone = _s(order['customerPhone']);
      if (cphone.isNotEmpty) _line(cphone);
    }

    // ---- Items ----
    const nameW = 16, qtyW = 4, amtW = 12;
    _divider();
    _bold(true);
    _line('ITEM'.padRight(nameW) + 'QTY'.padLeft(qtyW) + 'AMOUNT'.padLeft(amtW));
    _bold(false);
    _divider();

    final items = (order['items'] as List?) ?? [];
    double computedSubtotal = 0;
    for (final it in items) {
      final qty = ((it['qty'] ?? 1) as num).toInt();
      final price = ((it['price'] ?? 0) as num).toDouble();
      final size = _s(it['size']);
      final label = (size.isEmpty || size == 'Standard')
          ? _s(it['name'])
          : '${_s(it['name'])} ($size)';
      final amount = price * qty;
      computedSubtotal += amount;

      final nameLines = _wrapWords(label, nameW);
      if (nameLines.isEmpty) nameLines.add('');
      for (int i = 0; i < nameLines.length; i++) {
        if (i == 0) {
          _line(nameLines[i].padRight(nameW) +
              '$qty'.padLeft(qtyW) +
              _money(amount).padLeft(amtW));
        } else {
          _line(nameLines[i]);
        }
      }
    }
    _divider();

    // ---- Totals ----
    // Receipt screen ka same formula
    final subtotal =
        ((order['subtotal'] ?? order['totalPrice'] ?? computedSubtotal) as num)
            .toDouble();
    final total = ((order['totalPrice'] ?? subtotal) as num).toDouble();
    final showGst = settings['showGst'] == true || order['hasGst'] == true;
    final gstPct = double.tryParse(
            (settings['gstPercentage'] ?? order['gstPercentage'] ?? '5')
                .toString()) ??
        5.0;
    // Discount (if any) is taken off before GST; old bills have none, so the
    // numbers below are unchanged for them.
    final discount = ((order['discountGiven'] ?? 0) as num).toDouble();
    final taxable = subtotal - discount;
    final taxAmount = showGst
        ? (total - taxable > 0 ? total - taxable : taxable * (gstPct / 100.0))
        : 0.0;

    _lr('Subtotal:', _money(subtotal));
    if (discount > 0) {
      _lr('Discount:', '-${_money(discount)}');
    }
    if (showGst) {
      _lr('GST ($gstPct%):', _money(taxAmount));
    }
    _divider();
    _bold(true);
    _size(0x01); // double height
    _lr('GRAND TOTAL:', _money(total));
    _size(0x00);
    _bold(false);
    _divider();

    // ---- Footer ----
    _centerText(_s(settings['thankYouMessage']), bold: true);
    _centerText(_s(settings['receiptFooter']));
    _centerText('* POWERED BY CAFE POS *');

    _raw([0x0A, 0x0A, 0x0A, 0x0A]); // feed
    _raw([0x1D, 0x56, 0x42, 0x00]); // cut (cutter na ho to ignore)

    await _send(Uint8List.fromList(_b));
  }
}