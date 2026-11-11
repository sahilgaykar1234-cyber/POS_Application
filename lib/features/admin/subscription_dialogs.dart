import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/subscription/cafe_access.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'admin_service.dart';
import 'cafe_form_screen.dart' show formatAmount;

/// Assign a plan / change subscription dates & status for a cafe.
Future<void> showSetSubscriptionDialog(BuildContext context, CafeSummary cafe) {
  return showDialog(context: context, builder: (_) => _SetSubscriptionDialog(cafe: cafe));
}

/// Record a payment received (optionally renewing the subscription).
Future<String?> showRecordPaymentDialog(BuildContext context, CafeSummary cafe) {
  return showDialog<String>(context: context, builder: (_) => _RecordPaymentDialog(cafe: cafe));
}

class _SetSubscriptionDialog extends StatefulWidget {
  const _SetSubscriptionDialog({required this.cafe});
  final CafeSummary cafe;

  @override
  State<_SetSubscriptionDialog> createState() => _SetSubscriptionDialogState();
}

class _SetSubscriptionDialogState extends State<_SetSubscriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  SubscriptionPlan? _plan;
  late String _status = SubscriptionStatus.all.contains(widget.cafe.subscriptionStatus)
      ? widget.cafe.subscriptionStatus
      : SubscriptionStatus.active;
  late DateTime _start = widget.cafe.startDate ?? DateTime.now();
  late DateTime _expiry = widget.cafe.expiryDate ?? DateTime.now().add(const Duration(days: 30));
  late final _amount = TextEditingController(text: formatAmount(widget.cafe.amount));
  late String _paymentStatus = widget.cafe.paymentStatus == 'paid' ? 'paid' : 'pending';
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_expiry.isAfter(_start)) return showError(context, 'Expiry must be after the start date.');
    setState(() => _saving = true);
    try {
      await AdminService.instance.setSubscription(
        widget.cafe,
        plan: _plan,
        status: _status,
        start: _start,
        expiry: _expiry,
        amount: double.parse(_amount.text.trim()),
        paymentStatus: _paymentStatus,
      );
      if (mounted) {
        Navigator.pop(context);
        showSuccess(context, 'Subscription updated');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, AuthService.friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Subscription · ${widget.cafe.name}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<List<SubscriptionPlan>>(
                  stream: AdminService.instance.watchPlans(),
                  builder: (context, snap) {
                    final plans = (snap.data ?? const []).where((p) => p.isActive).toList();
                    return DropdownButtonFormField<String?>(
                      initialValue: _plan?.id,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Plan',
                        helperText: widget.cafe.planName == null ? null : 'Current: ${widget.cafe.planName}',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Keep / custom')),
                        for (final p in plans)
                          DropdownMenuItem<String?>(value: p.id, child: Text('${p.name} — ${Fmt.money(p.price)} / ${p.cycleLabel}')),
                      ],
                      onChanged: (id) => setState(() {
                        _plan = plans.where((p) => p.id == id).firstOrNull;
                        if (_plan != null) {
                          _amount.text = formatAmount(_plan!.price);
                          _expiry = _start.add(Duration(days: _plan!.durationDays));
                        }
                      }),
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
                  items: [
                    for (final s in SubscriptionStatus.all)
                      DropdownMenuItem(value: s, child: Text(s[0].toUpperCase() + s.substring(1))),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? _status),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _date('Start', _start, (d) => setState(() => _start = d))),
                  const SizedBox(width: 10),
                  Expanded(child: _date('Expiry', _expiry, (d) => setState(() => _expiry = d))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Amount ₹', border: OutlineInputBorder(), isDense: true),
                      validator: (v) => (double.tryParse((v ?? '').trim()) ?? -1) < 0 ? 'Enter an amount' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _paymentStatus,
                      decoration: const InputDecoration(labelText: 'Payment', border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'pending', child: Text('Pending')),
                        DropdownMenuItem(value: 'paid', child: Text('Paid')),
                      ],
                      onChanged: (v) => setState(() => _paymentStatus = v ?? _paymentStatus),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                const Text(
                  'Expired or suspended subscriptions block the cafe\'s POS. No data is ever deleted.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }

  Widget _date(String label, DateTime value, ValueChanged<DateTime> onPicked) => InkWell(
        onTap: () async {
          final d = await pickDate(context, initial: value);
          if (d != null) onPicked(d);
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
          child: Text(Fmt.date(value)),
        ),
      );
}

class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({required this.cafe});
  final CafeSummary cafe;

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.cafe.amount > 0 ? formatAmount(widget.cafe.amount) : '');
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'UPI';
  DateTime _paidAt = DateTime.now();
  bool _renew = true;
  late DateTime _periodStart = _defaultStart();
  late DateTime _periodEnd = _periodStart.add(Duration(days: _defaultDays()));
  bool _saving = false;

  DateTime _defaultStart() {
    final e = widget.cafe.expiryDate;
    final now = DateTime.now();
    // Renew from the current expiry if still running, otherwise from today.
    return (e != null && e.isAfter(now)) ? e : DateTime(now.year, now.month, now.day);
  }

  int _defaultDays() => switch (widget.cafe.subscription['billingCycle']) {
        'yearly' => 365,
        _ => 30,
      };

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_renew && !_periodEnd.isAfter(_periodStart)) return showError(context, 'Period end must be after its start.');
    setState(() => _saving = true);
    try {
      final receipt = await AdminService.instance.recordPayment(
        cafe: widget.cafe,
        amount: double.parse(_amount.text.trim()),
        method: _method,
        referenceId: _ref.text,
        notes: _notes.text,
        paidAt: _paidAt,
        periodStart: _renew ? _periodStart : null,
        periodEnd: _renew ? _periodEnd : null,
        extendTo: _renew ? _periodEnd : null,
      );
      if (mounted) Navigator.pop(context, receipt);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, AuthService.friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget date(String label, DateTime v, ValueChanged<DateTime> f) => InkWell(
          onTap: () async {
            final d = await pickDate(context, initial: v);
            if (d != null) setState(() => f(d));
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
            child: Text(Fmt.date(v)),
          ),
        );

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Record payment · ${widget.cafe.name}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amount,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Amount ₹ *', border: OutlineInputBorder(), isDense: true),
                      validator: (v) => (double.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Enter the amount' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _method,
                      decoration: const InputDecoration(labelText: 'Method', border: OutlineInputBorder(), isDense: true),
                      items: [for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m))],
                      onChanged: (v) => setState(() => _method = v ?? _method),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ref,
                  decoration: const InputDecoration(
                    labelText: 'Transaction / reference ID',
                    hintText: 'UPI ref, UTR, cheque no.…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                date('Payment date', _paidAt, (d) => _paidAt = d),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _renew,
                  onChanged: (v) => setState(() => _renew = v),
                  title: const Text('Renew subscription with this payment'),
                  subtitle: const Text('Sets status Active and moves the expiry date.'),
                ),
                if (_renew)
                  Row(children: [
                    Expanded(child: date('Period from', _periodStart, (d) => _periodStart = d)),
                    const SizedBox(width: 10),
                    Expanded(child: date('Valid until', _periodEnd, (d) => _periodEnd = d)),
                  ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder(), isDense: true),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Record payment')),
      ],
    );
  }
}
