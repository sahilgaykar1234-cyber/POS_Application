import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';
import 'receipt_actions.dart';
import 'receipt_data.dart';
import 'receipt_view.dart';

enum BillMode {
  /// Right after a payment was saved.
  paymentSuccess,

  /// The table was freed without a payment.
  closedUnpaid,

  /// Any saved bill (dashboard, orders list, takeaway history).
  details,
}

/// Shows a saved bill: a dialog with the receipt beside it on wide screens,
/// a full screen on phones. Everything comes from [order] (the saved order
/// [orderId]); printing / sharing never change it.
Future<void> showBill(
  BuildContext context, {
  required Map<String, dynamic> order,
  required String orderId,
  required Map<String, dynamic> settings,
  BillMode mode = BillMode.details,
}) {
  final view = BillView(order: order, orderId: orderId, settings: settings, mode: mode);
  if (MediaQuery.sizeOf(context).width >= 760) {
    return showDialog<void>(
      context: context,
      barrierDismissible: mode == BillMode.details,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(Space.xl),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720), child: view),
      ),
    );
  }
  return Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => view));
}

class BillView extends StatefulWidget {
  const BillView({super.key, required this.order, required this.orderId, required this.settings, this.mode = BillMode.details});
  final Map<String, dynamic> order;
  final String orderId;
  final Map<String, dynamic> settings;
  final BillMode mode;

  @override
  State<BillView> createState() => _BillViewState();
}

class _BillViewState extends State<BillView> {
  late final ReceiptData r = ReceiptData.from(widget.order, widget.orderId, widget.settings);
  final _receiptKey = GlobalKey();
  Uint8List? _png;

  @override
  void initState() {
    super.initState();
    // Render the receipt image ahead of time, so "Share image" can open the
    // phone's share sheet straight from the tap.
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  Future<void> _capture() async {
    try {
      final boundary = _receiptKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final img = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null && mounted) _png = bytes.buffer.asUint8List();
    } catch (_) {}
  }

  void _print({bool choose = false}) =>
      printSavedBill(context, order: widget.order, orderId: widget.orderId, settings: widget.settings, choose: choose);

  void _whatsApp() => shareSavedBillOnWhatsApp(context, order: widget.order, orderId: widget.orderId, settings: widget.settings);

  Future<void> _shareImage() async {
    if (_png == null) await _capture();
    if (!mounted) return;
    if (_png == null) return showError(context, 'Could not create the receipt image.');
    await shareReceiptImage(context, _png!, r);
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final receipt = RepaintBoundary(
      key: _receiptKey,
      child: Padding(
        // Room for the paper shadow in the shared image.
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, c) => ReceiptView(data: r, width: c.maxWidth.clamp(260, 380).toDouble()),
        ),
      ),
    );
    return wide ? _wide(context, receipt) : _phone(context, receipt);
  }

  // ------------------------------------------------------------ desktop --
  Widget _wide(BuildContext context, Widget receipt) {
    final p = context.palette;
    return Material(
      color: p.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, Space.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StatusHeader(r: r, mode: widget.mode),
                        const SizedBox(height: Space.xl),
                        _Facts(r: r),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(28, Space.lg, 28, 24),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                  child: _Actions(
                    mode: widget.mode,
                    onPrint: _print,
                    onChoosePrinter: () => _print(choose: true),
                    onWhatsApp: _whatsApp,
                    onShareImage: _shareImage,
                    onClose: _close,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: p.canvas,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.xl, Space.md, Space.sm, 0),
                    child: Row(children: [
                      Text('RECEIPT', style: TextStyle(color: p.inkSubtle, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                      const Spacer(),
                      IconButton(tooltip: 'Close', onPressed: _close, icon: const Icon(Icons.close_rounded)),
                    ]),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
                      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 404), child: receipt)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- phone --
  Widget _phone(BuildContext context, Widget receipt) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: _close),
        title: Text(widget.mode == BillMode.details ? 'Bill ${r.billNo}' : 'Bill'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) => v == 'image' ? _shareImage() : _print(choose: true),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'image', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('Share receipt image'))),
              PopupMenuItem(value: 'printer', child: ListTile(leading: Icon(Icons.print_outlined), title: Text('Change printer'))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xl),
        children: [
          SurfaceCard(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusHeader(r: r, mode: widget.mode),
                  const SizedBox(height: Space.lg),
                  _Facts(r: r),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          Text('RECEIPT', style: TextStyle(color: p.inkSubtle, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: Space.xs),
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 404), child: receipt)),
          if (widget.mode != BillMode.details) ...[
            const SizedBox(height: Space.md),
            OutlinedButton(onPressed: _close, child: const Text('Done · New order')),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
          decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
          child: Row(
            children: [
              Expanded(child: _WhatsAppButton(onPressed: _whatsApp)),
              const SizedBox(width: Space.sm),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    key: const Key('bill-print'),
                    onPressed: _print,
                    icon: const Icon(Icons.print_rounded, size: 20),
                    label: const Text('Print'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.r, required this.mode});
  final ReceiptData r;
  final BillMode mode;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, color, tint, title) = switch (mode) {
      BillMode.paymentSuccess => (Icons.check_rounded, p.success, p.successTint, 'Payment successful'),
      BillMode.closedUnpaid => (Icons.schedule_rounded, p.warning, p.warningTint, 'Bill closed · payment pending'),
      BillMode.details => r.isPaid
          ? (Icons.receipt_long_rounded, p.success, p.successTint, 'Paid bill')
          : (Icons.receipt_long_rounded, p.warning, p.warningTint, r.orderStatus == 'completed' ? 'Closed · payment pending' : 'Running bill'),
    };
    final animate = mode == BillMode.paymentSuccess;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: animate ? 0.4 : 1, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutBack,
          builder: (context, s, child) => Transform.scale(scale: s, alignment: Alignment.centerLeft, child: child),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: context.onStatusFill, size: 22),
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        Text(title, key: const Key('bill-status'), style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(
          [if (r.shopName.isNotEmpty) r.shopName, 'Bill ${r.billNo}'].join(' · '),
          style: TextStyle(color: p.inkSubtle),
        ),
        const SizedBox(height: Space.lg),
        Text(r.isPaid ? 'Amount paid' : 'Bill amount', style: TextStyle(color: p.inkSubtle, fontSize: 13)),
        Text(
          receiptMoney(r.total),
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: p.ink, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.r});
  final ReceiptData r;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget fact(String label, String value, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 112, child: Text(label, style: TextStyle(color: p.inkSubtle, fontSize: 13))),
              Expanded(child: trailing ?? Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
            ],
          ),
        );
    final summary = r.lines.map((l) => '${l.qty}× ${l.name}').join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fact('Payment', '', trailing: Align(alignment: Alignment.centerLeft, child: StatusChip(
          r.paymentLabel,
          color: r.isPaid ? p.success : p.warning,
          tint: r.isPaid ? p.successTint : p.warningTint,
        ))),
        fact('Date & time', receiptDate(r.billTime)),
        fact(r.isTakeaway && r.tableNo.isEmpty ? 'Order' : 'Table', r.whereLabel),
        if (r.customerName.isNotEmpty || r.customerPhone.isNotEmpty)
          fact('Customer', [r.customerName, r.customerPhone].where((s) => s.isNotEmpty).join(' · ')),
        fact('Items', '${r.itemCount} item${r.itemCount == 1 ? '' : 's'} · $summary'),
        fact('Order status', r.statusLabel),
        if (r.cashReceived != null)
          fact('Cash', '${receiptMoney(r.cashReceived!)} received${(r.changeReturned ?? 0) > 0 ? ' · ${receiptMoney(r.changeReturned!)} change' : ''}'),
        if (r.takenBy.isNotEmpty) fact('Taken by', r.takenBy[0].toUpperCase() + r.takenBy.substring(1)),
        fact('Order ID', r.orderRef),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.mode,
    required this.onPrint,
    required this.onChoosePrinter,
    required this.onWhatsApp,
    required this.onShareImage,
    required this.onClose,
  });
  final BillMode mode;
  final VoidCallback onPrint;
  final VoidCallback onChoosePrinter;
  final VoidCallback onWhatsApp;
  final VoidCallback onShareImage;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: FilledButton.icon(
                key: const Key('bill-print'),
                onPressed: onPrint,
                icon: const Icon(Icons.print_rounded, size: 20),
                label: const Text('Print receipt'),
              ),
            ),
          ),
          const SizedBox(width: Space.xs),
          IconButton.outlined(tooltip: 'Change printer / paper', onPressed: onChoosePrinter, icon: const Icon(Icons.tune_rounded, size: 20)),
        ]),
        const SizedBox(height: Space.sm),
        _WhatsAppButton(onPressed: onWhatsApp, label: 'Share on WhatsApp'),
        const SizedBox(height: Space.xs),
        Row(children: [
          TextButton.icon(onPressed: onShareImage, icon: const Icon(Icons.image_outlined, size: 18), label: const Text('Receipt image')),
          const Spacer(),
          TextButton(
            key: const Key('bill-close'),
            onPressed: onClose,
            child: Text(mode == BillMode.details ? 'Close' : 'Done · New order'),
          ),
        ]),
      ],
    );
  }
}

class _WhatsAppButton extends StatelessWidget {
  const _WhatsAppButton({required this.onPressed, this.label = 'WhatsApp'});
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: FilledButton.icon(
          key: const Key('bill-whatsapp'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF128C4A), foregroundColor: Colors.white),
          onPressed: onPressed,
          icon: const Icon(Icons.chat_rounded, size: 20),
          label: Text(label),
        ),
      );
}
