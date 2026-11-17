import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../admin/admin_models.dart';
import 'renewal_service.dart';
import 'upi_payment.dart';

/// "Pay now" for a cafe's Manager: pay the platform owner by UPI (QR or the
/// UPI app), then send the UPI reference number. The subscription is renewed
/// when the Super Admin approves it – never by this screen.
Future<void> showPayNowDialog(
  BuildContext context, {
  required String cafeId,
  required String cafeName,
  Map<String, dynamic> subscription = const {},
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _PayNowDialog(cafeId: cafeId, cafeName: cafeName, subscription: subscription),
    );

class _PayNowDialog extends StatefulWidget {
  const _PayNowDialog({required this.cafeId, required this.cafeName, required this.subscription});
  final String cafeId;
  final String cafeName;
  final Map<String, dynamic> subscription;

  @override
  State<_PayNowDialog> createState() => _PayNowDialogState();
}

class _PayNowDialogState extends State<_PayNowDialog> {
  final _svc = RenewalService.instance;
  late final _payee = _svc.watchPayee();
  late final _plans = _svc.watchPaidPlans();
  late final _claim = _svc.watchClaim(widget.cafeId);
  final _utr = TextEditingController();

  String? _planId;
  String? _cycle;
  bool _sending = false;
  String? _error;

  DateTime? get _expiry => Fmt.toDate(widget.subscription['expiryDate']);

  @override
  void dispose() {
    _utr.dispose();
    super.dispose();
  }

  SubscriptionPlan _plan(List<SubscriptionPlan> plans) {
    final want = _planId ?? widget.subscription['planId']?.toString();
    return plans.where((p) => p.id == want).firstOrNull ?? plans.first;
  }

  String _cycleFor(SubscriptionPlan plan) {
    final want = _cycle ?? (widget.subscription['billingCycle'] == 'yearly' ? 'yearly' : 'monthly');
    if (want == 'yearly' && plan.yearlyPrice > 0) return 'yearly';
    return plan.monthlyPrice > 0 ? 'monthly' : 'yearly';
  }

  double _price(SubscriptionPlan plan, String cycle) => cycle == 'yearly' ? plan.yearlyPrice : plan.monthlyPrice;

  Future<void> _send(SubscriptionPlan plan, String cycle) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _svc.submitClaim(
        cafeId: widget.cafeId,
        cafeName: widget.cafeName,
        utr: _utr.text,
        amount: _price(plan, cycle),
        plan: plan,
        cycle: cycle,
      );
      if (mounted) showSuccess(context, 'Payment details sent. We\'ll confirm it shortly.');
    } on ClaimException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send it. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renew your subscription'),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: StreamBuilder<PaymentClaim?>(
          stream: _claim,
          builder: (context, claimSnap) {
            final claim = claimSnap.data;
            if (claim != null && claim.isPending) return _pending(context, claim);
            return StreamBuilder<UpiPayee>(
              stream: _payee,
              builder: (context, payeeSnap) => StreamBuilder<List<SubscriptionPlan>>(
                stream: _plans,
                builder: (context, plansSnap) {
                  if (payeeSnap.hasError || plansSnap.hasError) {
                    return const Text('Could not load the payment details. Please check your internet connection.');
                  }
                  if (!payeeSnap.hasData || !plansSnap.hasData) {
                    return const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()));
                  }
                  final payee = payeeSnap.data!;
                  final plans = plansSnap.data!;
                  if (!payee.isSet || plans.isEmpty) {
                    return const Text('Online payment is not set up yet. Please contact support to renew.');
                  }
                  return _payForm(context, payee, plans, claim);
                },
              ),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }

  Widget _pending(BuildContext context, PaymentClaim claim) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.hourglass_top_rounded, size: 40, color: p.info),
        const SizedBox(height: Space.md),
        Text('Payment received – being verified', textAlign: TextAlign.center, style: context.text.titleMedium),
        const SizedBox(height: Space.sm),
        Text(
          '${Fmt.money(claim.amount)} · ${claim.planName} ${claim.cycleLabel.toLowerCase()} · UTR ${claim.utr}\n'
          'Sent ${Fmt.dateTime(claim.submittedAt)}. Your subscription is renewed as soon as we confirm the payment.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.inkMuted, height: 1.4),
        ),
      ],
    );
  }

  Widget _payForm(BuildContext context, UpiPayee payee, List<SubscriptionPlan> plans, PaymentClaim? last) {
    final p = context.palette;
    final plan = _plan(plans);
    final cycle = _cycleFor(plan);
    final amount = _price(plan, cycle);
    final link = upiPayLink(payee: payee, amount: amount, note: upiNote(widget.cafeName, plan.name, cycle));
    final until = renewedUntil(currentExpiry: _expiry, cycle: cycle, now: DateTime.now());

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (last != null && last.isRejected) ...[
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(color: p.dangerTint, borderRadius: BorderRadius.circular(10)),
            child: Text(
              'Your last payment (UTR ${last.utr}) could not be verified'
              '${last.rejectReason.isEmpty ? '' : ': ${last.rejectReason}'}. Please check and try again.',
              style: TextStyle(color: p.danger, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: Space.md),
        ],
        if (plans.length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: plan.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Plan'),
            items: [for (final x in plans) DropdownMenuItem(value: x.id, child: Text('${x.name} · ${x.priceLabel}', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _planId = v),
          ),
          const SizedBox(height: Space.md),
        ],
        if (plan.monthlyPrice > 0 && plan.yearlyPrice > 0) ...[
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'monthly', label: Text('Monthly')),
              ButtonSegment(value: 'yearly', label: Text('Yearly')),
            ],
            selected: {cycle},
            onSelectionChanged: (s) => setState(() => _cycle = s.first),
          ),
          const SizedBox(height: Space.md),
        ],
        Text(Fmt.money(amount), textAlign: TextAlign.center, style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        Text('${plan.name} · ${cycle == 'yearly' ? '1 year' : '1 month'} · until ${Fmt.date(until)}',
            textAlign: TextAlign.center, style: TextStyle(color: p.inkSubtle)),
        const SizedBox(height: Space.lg),
        Text('1. Pay by UPI', style: context.text.titleSmall),
        const SizedBox(height: Space.sm),
        Center(
          child: Container(
            padding: const EdgeInsets.all(Space.sm),
            color: Colors.white,
            // Painted at a fixed size: QrImageView uses a LayoutBuilder, which a
            // scrollable dialog can't measure.
            child: SizedBox(
              key: const Key('pay-qr'),
              width: 200,
              height: 200,
              child: CustomPaint(
                painter: QrPainter(
                  data: link,
                  version: QrVersions.auto,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        Text('Scan with GPay, PhonePe, Paytm or any UPI app', textAlign: TextAlign.center, style: TextStyle(color: p.inkSubtle, fontSize: 12.5)),
        const SizedBox(height: Space.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.sm,
          runSpacing: Space.xs,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => launchUrl(Uri.parse(link), webOnlyWindowName: '_self'),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open UPI app'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: payee.upiId));
                showSuccess(context, 'UPI ID copied');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(payee.upiId),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        Text('2. Send the UPI reference number', style: context.text.titleSmall),
        const SizedBox(height: Space.sm),
        TextField(
          key: const Key('claim-utr'),
          controller: _utr,
          keyboardType: TextInputType.number,
          maxLength: 14,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
          decoration: InputDecoration(
            labelText: 'UPI reference no. (UTR, 12 digits)',
            helperText: 'In your UPI app: open the payment → "UPI Ref No." / "UTR"',
            errorText: _error,
          ),
        ),
        const SizedBox(height: Space.sm),
        FilledButton(
          key: const Key('claim-send'),
          onPressed: _sending ? null : () => _send(plan, cycle),
          child: Text(_sending ? 'Sending…' : 'I\'ve paid'),
        ),
        const SizedBox(height: Space.sm),
        Text(
          'We renew your subscription as soon as we see the payment in our account (usually within a few hours). '
          'Sending a reference number alone does not renew it.',
          style: TextStyle(color: p.inkSubtle, fontSize: 12),
        ),
      ],
    );
  }
}
