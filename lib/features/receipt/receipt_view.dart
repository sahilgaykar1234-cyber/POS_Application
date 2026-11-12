import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

import 'receipt_data.dart';

/// The bill as the customer sees it: a white paper receipt that looks the
/// same in light and dark mode (it is also what gets shared as an image).
/// Used by the payment-success view, bill details and WhatsApp sharing.
class ReceiptView extends StatelessWidget {
  const ReceiptView({super.key, required this.data, this.width = 360});
  final ReceiptData data;
  final double width;

  static const _ink = Color(0xFF111827);
  static const _muted = Color(0xFF4B5563);
  static const _rule = Color(0xFFD1D5DB);

  @override
  Widget build(BuildContext context) {
    final r = data;
    final logo = _logo(r.logoBase64);
    // Bundled Inter: the receipt must not depend on a font download.
    const base = TextStyle(
      fontFamily: AppTheme.fontFamily,
      color: _ink,
      fontSize: 13,
      height: 1.35,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    Widget row(String l, String v, {TextStyle? style, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l, style: (style ?? base).copyWith(color: color ?? _muted)),
              const SizedBox(width: 12),
              // Long names / addresses wrap instead of running off the paper.
              Expanded(child: Text(v, textAlign: TextAlign.right, style: (style ?? base).copyWith(color: color ?? _ink))),
            ],
          ),
        );

    return DefaultTextStyle(
      style: base,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(color: Color(0x1A101828), blurRadius: 18, offset: Offset(0, 8)),
            BoxShadow(color: Color(0x0F101828), blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cafe
            if (logo != null) ...[
              Center(child: SizedBox(height: 56, child: logo)),
              const SizedBox(height: 8),
            ],
            if (r.shopName.isNotEmpty)
              Text(r.shopName, textAlign: TextAlign.center, style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
            for (final line in [r.tagline, r.address, if (r.phone.isNotEmpty) 'Ph: ${r.phone}', if (r.gstNumber.isNotEmpty) 'GSTIN: ${r.gstNumber}'])
              if (line.isNotEmpty) Text(line, textAlign: TextAlign.center, style: base.copyWith(color: _muted, fontSize: 12)),
            if (r.header.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(r.header, textAlign: TextAlign.center, style: base.copyWith(color: _muted, fontSize: 12, fontStyle: FontStyle.italic)),
            ],
            const _Rule(),

            // Bill details
            row('Bill No', r.billNo, style: base.copyWith(fontWeight: FontWeight.w700)),
            row('Date', receiptDate(r.billTime)),
            row(r.isTakeaway && r.tableNo.isEmpty ? 'Order' : 'Table', r.whereLabel),
            if (r.customerName.isNotEmpty) row('Customer', r.customerName),
            if (r.customerPhone.isNotEmpty) row('Mobile', r.customerPhone),
            const _Rule(),

            // Items
            Row(children: [
              Expanded(child: Text('ITEM', style: base.copyWith(color: _muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6))),
              Text('AMOUNT', style: base.copyWith(color: _muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            ]),
            const SizedBox(height: 4),
            for (final l in r.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.variant.isEmpty ? l.name : '${l.name} (${l.variant})', style: base.copyWith(fontWeight: FontWeight.w600)),
                          Text('${l.qty} × ${receiptMoney(l.unitPrice)}', style: base.copyWith(color: _muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(receiptMoney(l.amount, always2: true), style: base),
                  ],
                ),
              ),
            const _Rule(),

            // Totals
            row('Subtotal', receiptMoney(r.subtotal, always2: true)),
            if (r.discount > 0) row('Discount', '−${receiptMoney(r.discount, always2: true)}', color: const Color(0xFFB45309)),
            if (r.hasGst) ...[
              row('CGST ${_pct((r.gstPercent ?? 0) / 2)}%', receiptMoney(r.cgst, always2: true)),
              row('SGST ${_pct((r.gstPercent ?? 0) / 2)}%', receiptMoney(r.sgst, always2: true)),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: _ink, width: 1.2))),
              child: Row(children: [
                Expanded(child: Text('TOTAL', style: base.copyWith(fontSize: 15, fontWeight: FontWeight.w800))),
                Text(receiptMoney(r.total, always2: true), style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(height: 8),

            // Payment
            row('Payment', r.isPaid ? 'PAID' : 'PENDING',
                style: base.copyWith(fontWeight: FontWeight.w700), color: r.isPaid ? const Color(0xFF047857) : const Color(0xFFB45309)),
            if (r.isPaid && r.paymentMethod.isNotEmpty) row('Paid by', r.paymentMethod),
            if (r.cashReceived != null) row('Cash received', receiptMoney(r.cashReceived!, always2: true)),
            if ((r.changeReturned ?? 0) > 0) row('Change', receiptMoney(r.changeReturned!, always2: true)),

            // Thanks
            if (r.thanks.isNotEmpty || r.footer.isNotEmpty) ...[
              const _Rule(),
              for (final t in [r.thanks, r.footer])
                if (t.isNotEmpty) Text(t, textAlign: TextAlign.center, style: base.copyWith(fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  static String _pct(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static Widget? _logo(String? b64) {
    if (b64 == null) return null;
    try {
      return Image.memory(base64Decode(b64), fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox.shrink());
    } catch (_) {
      return null;
    }
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: LayoutBuilder(
          builder: (context, c) {
            const dash = 4.0, gap = 3.0;
            final n = (c.maxWidth / (dash + gap)).floor();
            return Row(
              children: [
                for (var i = 0; i < n; i++) ...[
                  Container(width: dash, height: 1, color: ReceiptView._rule),
                  if (i < n - 1) const SizedBox(width: gap),
                ],
              ],
            );
          },
        ),
      );
}
