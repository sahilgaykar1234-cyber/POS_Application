import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/friendly_error.dart';
import '../../core/web/wake_lock.dart';
import '../../escpos_bluetooth_printer_stub.dart' if (dart.library.js_interop) '../../escpos_bluetooth_printer_web.dart';
import '../../escpos_usb_printer_stub.dart' if (dart.library.js_interop) '../../escpos_usb_printer_web.dart';
import '../settings/business_settings.dart';
import 'bluetooth_printer_logic.dart';
import 'print_station.dart';
import 'receipt_actions.dart';
import 'package:pos_app/core/i18n/tr.dart';

/// On the device set as Print Station: prints every bill sent from other
/// devices, keeps the screen on and shows a small status bar. Elsewhere it
/// only shows [child].
class PrintStationHost extends StatefulWidget {
  const PrintStationHost({super.key, required this.cafeId, required this.child, this.printJob, this.connectPrinter});

  final String cafeId;
  final Widget child;

  /// Prints one job on this device's printer; replaceable in tests.
  final Future<void> Function(PrintJob job)? printJob;

  /// Connects this device's printer (after a tap); replaceable in tests.
  final Future<void> Function(BuildContext context)? connectPrinter;

  /// Prints on the USB or Bluetooth printer chosen on this device.
  static Future<void> printOnThisDevice(PrintJob job) async {
    final settings = (await BusinessSettingsRepository.instance.load()).receiptSettings;
    switch (await savedReceiptPrinter()) {
      case ReceiptPrinter.usb:
        await EscPosUsbPrinter.printReceipt(order: job.order, orderId: job.orderId, settings: settings);
      case ReceiptPrinter.bluetooth:
        await EscPosBluetoothPrinter.printReceipt(order: job.order, orderId: job.orderId, settings: settings);
      case ReceiptPrinter.station || null:
        throw const PrinterProblem('station-no-printer');
    }
  }

  /// Picks this device's printer if needed, then connects to it.
  static Future<void> connectThisDevice(BuildContext context) async {
    var printer = await savedReceiptPrinter();
    if (printer == null || printer == ReceiptPrinter.station) {
      if (!context.mounted) return;
      printer = await chooseReceiptPrinter(context, forStation: true);
      if (printer == null) throw const PrinterProblem('station-no-printer');
      await saveReceiptPrinter(printer);
    }
    if (printer == ReceiptPrinter.usb) {
      await EscPosUsbPrinter.connect();
    } else {
      await EscPosBluetoothPrinter.connect();
    }
  }

  @override
  State<PrintStationHost> createState() => _PrintStationHostState();
}

class _PrintStationHostState extends State<PrintStationHost> {
  final _svc = PrintStationService.instance;
  final String _stationId = 'st_${Random().nextInt(1 << 30)}';
  StreamSubscription<List<PrintJob>>? _sub;
  Timer? _beat;

  /// The printer was connected in this session (a tap is needed once per
  /// page load: browser rule for Bluetooth).
  bool _ready = false;
  bool _busy = false;
  bool _connecting = false;
  String? _problem;
  int _printed = 0;
  List<PrintJob> _waiting = const [];
  final Set<String> _skipped = {};

  @override
  void initState() {
    super.initState();
    _svc.enabled.addListener(_apply);
    _svc.load(widget.cafeId).then((_) => _apply());
  }

  @override
  void dispose() {
    _svc.enabled.removeListener(_apply);
    _stop();
    super.dispose();
  }

  void _apply() {
    if (!mounted) return;
    final on = _svc.enabled.value;
    if (on && _sub == null) {
      _sub = _svc.watchPending().listen((jobs) {
        if (!mounted) return;
        setState(() => _waiting = jobs);
        _drain();
      }, onError: (_) {});
      unawaited(_heartbeat());
      _beat = Timer.periodic(const Duration(minutes: 1), (_) => _heartbeat());
      unawaited(keepScreenOn(true));
      unawaited(_svc.cleanUp().catchError((Object _) {}));
    } else if (!on && _sub != null) {
      _stop();
    }
    setState(() {});
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _beat?.cancel();
    _beat = null;
    unawaited(keepScreenOn(false));
  }

  Future<void> _heartbeat() async {
    try {
      await _svc.heartbeat(stationId: _stationId, device: tr('Print Station'));
    } catch (_) {}
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _problem = null;
    });
    try {
      await (widget.connectPrinter ?? PrintStationHost.connectThisDevice)(context);
      if (!mounted) return;
      setState(() => _ready = true);
      _skipped.clear();
      unawaited(_drain());
    } catch (e) {
      if (mounted) setState(() => _problem = friendlyPrintError(e));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  /// Prints the waiting bills one by one, oldest first.
  Future<void> _drain() async {
    if (!_ready || _busy || !_svc.enabled.value) return;
    _busy = true;
    try {
      for (final job in [..._waiting]) {
        if (_skipped.contains(job.id)) continue;
        final claimed = await _svc.claim(job.id, _stationId);
        if (claimed == null) {
          _skipped.add(job.id);
          continue;
        }
        try {
          await (widget.printJob ?? PrintStationHost.printOnThisDevice)(claimed);
          await _svc.markPrinted(claimed.id);
          if (mounted) setState(() => _printed++);
        } catch (e) {
          // Printer not ready: the bill waits for "Connect printer".
          await _svc.putBack(claimed.id).catchError((Object _) {});
          if (mounted) {
            setState(() {
              _ready = false;
              _problem = friendlyPrintError(e);
            });
          }
          return;
        }
      }
    } catch (_) {
      // Network trouble: tried again on the next update.
    } finally {
      _busy = false;
    }
    if (_ready && _waiting.any((j) => !_skipped.contains(j.id))) unawaited(_drain());
  }

  @override
  Widget build(BuildContext context) {
    final on = _svc.enabled.value;
    return Column(
      children: [
        if (on) _bar(context),
        Expanded(key: const ValueKey('print-station-child'), child: widget.child),
      ],
    );
  }

  Widget _bar(BuildContext context) {
    final p = context.palette;
    final waiting = _waiting.where((j) => !_skipped.contains(j.id)).length;
    final ok = _ready && _problem == null;
    final text = ok
        ? tr('Print Station on · {0} printed', [_printed])
        : [
            if (_problem != null) _problem! else tr('Print Station: tap Connect printer to start.'),
            if (waiting > 0) tr('{0} bills waiting', [waiting]),
          ].join(' · ');
    return Material(
      color: ok ? p.successTint : p.warningTint,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.print_rounded, size: 18, color: ok ? p.success : p.warning),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(text,
                    key: const Key('print-station-status'),
                    style: TextStyle(color: ok ? p.success : p.warning, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (!_ready)
                FilledButton(
                  key: const Key('print-station-connect'),
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: _connecting ? null : _connect,
                  child: Text(_connecting ? tr('Connecting…') : tr('Connect printer')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
