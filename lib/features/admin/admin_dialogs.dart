import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/subscription/cafe_access.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/business_day.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/ui.dart';
import 'admin_service.dart';
import 'admin_widgets.dart';
import '../../core/utils/friendly_error.dart';

/// Forms of the Super Admin panel. Every save is a Firestore write that the
/// rules allow only for the Super Admin, and each one is audit-logged.

Future<T?> _sheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext, StateSetter) body,
  required List<Widget> Function(BuildContext) actions,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        scrollable: true,
        content: SizedBox(width: 560, child: body(ctx, setState)),
        actions: actions(ctx),
      ),
    ),
  );
}

/// Two fields side by side, stacked on phones. Decided from the screen
/// width: dialogs measure their content (intrinsic size), which a
/// LayoutBuilder can't take part in (that left the dialog blank).
Widget _two(BuildContext context, Widget a, Widget b) => MediaQuery.sizeOf(context).width < 600
    ? Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          a,
          const SizedBox(height: Space.md),
          b,
        ],
      )
    : Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: Space.md),
          Expanded(child: b),
        ],
      );

Future<DateTime?> _pickDay(BuildContext context, DateTime initial) =>
    showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime(2100));

// =================================================================== cafe ==

/// Create a cafe (cafe == null) or edit one. Returns the cafe id on create.
Future<String?> showCafeForm(
  BuildContext context, {
  CafeSummary? cafe,
  int? currentDayEndsAt,
  PlatformSettings? platform,
  List<SubscriptionPlan> plans = const [],
}) async {
  final isNew = cafe == null;
  final c = {
    for (final k in ['name', 'ownerName', 'ownerEmail', 'contactNumber', 'address', 'city', 'state', 'country', 'gstNumber'])
      k: TextEditingController(text: (cafe?.data[k] ?? (k == 'country' && isNew ? 'India' : '')).toString()),
  };
  var dayEnds = currentDayEndsAt ?? platform?.defaultDayEndsAt ?? BusinessDay.defaultCutoffMinutes;
  final trialPlan = plans.where((p) => p.tier == PlanTier.trial && p.isActive).firstOrNull;
  var startTrial = isNew;
  var trialDays = trialPlan?.trialDays ?? platform?.trialDays ?? 14;
  final form = GlobalKey<FormState>();
  var saving = false;

  Widget field(String k, String label, {bool required = false, TextInputType? type, int lines = 1}) => TextFormField(
    controller: c[k],
    keyboardType: type,
    maxLines: lines,
    decoration: InputDecoration(labelText: required ? '$label *' : label),
    validator: (v) {
      final t = (v ?? '').trim();
      if (required && t.isEmpty) return 'Required';
      if (k == 'ownerEmail' && t.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) return 'Not a valid email';
      return null;
    },
  );

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> save() async {
          if (!form.currentState!.validate()) return;
          setState(() => saving = true);
          final profile = {for (final e in c.entries) e.key: e.value.text.trim()};
          try {
            if (isNew) {
              final id = await AdminService.instance.createCafe(
                profile: profile,
                dayEndsAt: dayEnds,
                trialPlan: trialPlan,
                trialDays: startTrial ? trialDays : null,
              );
              if (ctx.mounted) Navigator.pop(ctx, id);
            } else {
              await AdminService.instance.updateCafe(cafe, profile, dayEndsAt: dayEnds);
              if (ctx.mounted) Navigator.pop(ctx, cafe.id);
            }
          } catch (e) {
            setState(() => saving = false);
            if (ctx.mounted) showError(ctx, friendlyError(e, 'save'));
          }
        }

        return AlertDialog(
          title: Text(isNew ? 'New cafe' : 'Edit ${cafe.name}'),
          scrollable: true,
          content: SizedBox(
            width: 600,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field('name', 'Cafe name', required: true),
                  const SizedBox(height: Space.md),
                  _two(ctx, field('ownerName', 'Owner name'), field('contactNumber', 'Phone', type: TextInputType.phone)),
                  const SizedBox(height: Space.md),
                  _two(ctx, field('ownerEmail', 'Email', type: TextInputType.emailAddress), field('gstNumber', 'GST number')),
                  const SizedBox(height: Space.md),
                  field('address', 'Address', lines: 2),
                  const SizedBox(height: Space.md),
                  _two(ctx, field('city', 'City'), field('state', 'State')),
                  const SizedBox(height: Space.md),
                  field('country', 'Country'),
                  const SizedBox(height: Space.md),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Business day ends at'),
                    subtitle: const Text('Orders after midnight until this time count in the previous day.'),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay(hour: dayEnds ~/ 60, minute: dayEnds % 60),
                        );
                        if (t == null) return;
                        final m = t.hour * 60 + t.minute;
                        if (m > BusinessDay.maxCutoffMinutes) {
                          if (ctx.mounted) showError(ctx, 'Pick a time between 12:00 AM and 12:00 PM.');
                          return;
                        }
                        setState(() => dayEnds = m);
                      },
                      child: Text(BusinessDay.label(dayEnds)),
                    ),
                  ),
                  if (isNew) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: startTrial,
                      onChanged: (v) => setState(() => startTrial = v),
                      title: const Text('Start a free trial'),
                      subtitle: Text(startTrial ? '$trialDays days, then assign a plan' : 'Assign a plan later'),
                    ),
                    if (startTrial)
                      Row(
                        children: [
                          const Text('Trial length'),
                          const Spacer(),
                          IconButton(onPressed: trialDays > 1 ? () => setState(() => trialDays--) : null, icon: const Icon(Icons.remove_circle_outline)),
                          Text('$trialDays days', style: const TextStyle(fontWeight: FontWeight.w700)),
                          IconButton(onPressed: trialDays < 90 ? () => setState(() => trialDays++) : null, icon: const Icon(Icons.add_circle_outline)),
                        ],
                      ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'After saving, create the cafe\'s login with the admin script (shown next).',
                      style: TextStyle(color: ctx.palette.inkSubtle, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            OutlinedButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(key: const Key('cafe-save'), onPressed: saving ? null : save, child: Text(saving ? 'Saving…' : (isNew ? 'Create cafe' : 'Save'))),
          ],
        );
      },
    ),
  );
}

Future<void> confirmCafeStatus(BuildContext context, CafeSummary cafe, String status) async {
  final active = status == CafeStatus.active;
  final ok = active
      ? await showConfirmDialog(context, title: 'Activate ${cafe.name}?', message: 'Its staff can use the POS again.', confirmLabel: 'Activate')
      : await showDangerConfirmDialog(
          context,
          title: '${status == CafeStatus.suspended ? 'Suspend' : 'Deactivate'} ${cafe.name}?',
          message: 'Staff of this cafe will be blocked from the POS. No data is deleted and you can activate it again any time.',
          confirmLabel: status == CafeStatus.suspended ? 'Suspend' : 'Deactivate',
        );
  if (!ok || !context.mounted) return;
  try {
    await AdminService.instance.setCafeStatus(cafe, status);
    if (context.mounted) showSuccess(context, '${cafe.name} is now $status');
  } catch (e) {
    if (context.mounted) showError(context, friendlyError(e, 'change the status'));
  }
}

// =================================================================== plan ==

Future<void> showPlanForm(BuildContext context, {SubscriptionPlan? plan}) {
  final name = TextEditingController(text: plan?.name ?? '');
  final monthly = TextEditingController(text: plan == null || plan.monthlyPrice == 0 ? '' : _num(plan.monthlyPrice));
  final yearly = TextEditingController(text: plan == null || plan.yearlyPrice == 0 ? '' : _num(plan.yearlyPrice));
  final trial = TextEditingController(text: plan == null ? '' : (plan.trialDays == 0 ? '' : '${plan.trialDays}'));
  final staff = TextEditingController(text: plan?.maxStaff?.toString() ?? '');
  final devices = TextEditingController(text: plan?.maxDevices?.toString() ?? '');
  final features = TextEditingController(text: plan?.features.join('\n') ?? '');
  final desc = TextEditingController(text: plan?.description ?? '');
  var tier = plan?.tier ?? PlanTier.basic;
  var active = plan?.isActive ?? true;
  var saving = false;
  final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

  return _sheet<void>(
    context,
    title: plan == null ? 'New plan' : 'Edit plan',
    body: (ctx, setState) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _two(
          ctx,
          TextField(
            key: const Key('plan-name'),
            controller: name,
            decoration: const InputDecoration(labelText: 'Plan name *'),
          ),
          DropdownButtonFormField<PlanTier>(
            isExpanded: true,
            initialValue: tier,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [for (final t in PlanTier.values) DropdownMenuItem(value: t, child: Text(t.label))],
            onChanged: (v) => setState(() => tier = v ?? tier),
          ),
        ),
        const SizedBox(height: Space.md),
        if (tier == PlanTier.trial)
          TextField(
            controller: trial,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: const InputDecoration(labelText: 'Trial length (days) *'),
          )
        else
          _two(
            ctx,
            TextField(
              controller: monthly,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: const InputDecoration(labelText: 'Monthly price', prefixText: '₹ '),
            ),
            TextField(
              controller: yearly,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: const InputDecoration(labelText: 'Yearly price', prefixText: '₹ '),
            ),
          ),
        const SizedBox(height: Space.md),
        _two(
          ctx,
          TextField(
            controller: staff,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: const InputDecoration(labelText: 'Max staff logins', hintText: 'Empty = no limit'),
          ),
          TextField(
            controller: devices,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: const InputDecoration(labelText: 'Max devices', hintText: 'Empty = no limit'),
          ),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: features,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Features (one per line)', alignLabelWithHint: true),
        ),
        const SizedBox(height: Space.md),
        TextField(
          controller: desc,
          decoration: const InputDecoration(labelText: 'Short description'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: active,
          onChanged: (v) => setState(() => active = v),
          title: const Text('Available for new subscriptions'),
        ),
      ],
    ),
    actions: (ctx) => [
      OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      StatefulBuilder(
        builder: (ctx2, setBtn) => FilledButton(
          key: const Key('plan-save'),
          onPressed: saving
              ? null
              : () async {
                  if (name.text.trim().isEmpty) return showError(ctx, 'Enter a plan name.');
                  final m = double.tryParse(monthly.text.trim()) ?? 0;
                  final y = double.tryParse(yearly.text.trim()) ?? 0;
                  final td = int.tryParse(trial.text.trim()) ?? 0;
                  if (tier == PlanTier.trial && td <= 0) return showError(ctx, 'Enter the trial length in days.');
                  setBtn(() => saving = true);
                  try {
                    await AdminService.instance.savePlan(plan?.id, {
                      'name': name.text.trim(),
                      'tier': tier.name,
                      'monthlyPrice': tier == PlanTier.trial ? 0 : m,
                      'yearlyPrice': tier == PlanTier.trial ? 0 : y,
                      'trialDays': tier == PlanTier.trial ? td : 0,
                      'maxStaff': int.tryParse(staff.text.trim()),
                      'maxDevices': int.tryParse(devices.text.trim()),
                      'features': features.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                      'description': desc.text.trim(),
                      'isActive': active,
                    });
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      showSuccess(context, 'Plan saved');
                    }
                  } catch (e) {
                    setBtn(() => saving = false);
                    if (ctx.mounted) showError(ctx, friendlyError(e, 'save'));
                  }
                },
          child: Text(saving ? 'Saving…' : 'Save plan'),
        ),
      ),
    ],
  );
}

String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

// ========================================================== subscription ==

/// Assign or change a cafe's plan and period. No money is recorded here.
Future<void> showAssignPlan(BuildContext context, CafeSummary cafe, List<SubscriptionPlan> plans) {
  final usable = plans.where((p) => p.isActive || p.id == cafe.planId).toList();
  SubscriptionPlan? plan = usable.where((p) => p.id == cafe.planId).firstOrNull ?? usable.firstOrNull;
  var cycle = cafe.billingCycle.isNotEmpty && cafe.billingCycle != 'trial' ? cafe.billingCycle : 'monthly';
  var start = DateTime.now();
  DateTime expiryFor() => plan?.tier == PlanTier.trial
      ? start.add(Duration(days: plan!.trialDays))
      : (cycle == 'yearly' ? DateTime(start.year + 1, start.month, start.day) : DateTime(start.year, start.month + 1, start.day));
  var expiry = expiryFor();
  double priceFor() => plan == null ? 0 : (plan!.tier == PlanTier.trial ? 0 : (cycle == 'yearly' ? plan!.yearlyPrice : plan!.monthlyPrice));
  final amount = TextEditingController(text: _num(priceFor()));
  var paid = 'pending';
  var saving = false;

  return _sheet<void>(
    context,
    title: '${cafe.hasSubscription ? 'Change' : 'Assign'} plan · ${cafe.name}',
    body: (ctx, setState) {
      if (usable.isEmpty) {
        return const Text('Create a plan first (Subscriptions › Plans).');
      }
      void recalc() {
        expiry = expiryFor();
        amount.text = _num(priceFor());
      }

      final isTrial = plan?.tier == PlanTier.trial;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('assign-plan'),
            isExpanded: true,
            initialValue: plan?.id,
            decoration: const InputDecoration(labelText: 'Plan'),
            items: [
              for (final p in usable)
                DropdownMenuItem(
                  value: p.id,
                  child: Text('${p.name} · ${p.priceLabel}', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) => setState(() {
              plan = usable.firstWhere((p) => p.id == id);
              recalc();
            }),
          ),
          const SizedBox(height: Space.md),
          if (!isTrial)
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'monthly', label: Text('Monthly')),
                ButtonSegment(value: 'yearly', label: Text('Yearly')),
              ],
              selected: {cycle},
              onSelectionChanged: (s) => setState(() {
                cycle = s.first;
                recalc();
              }),
            ),
          const SizedBox(height: Space.md),
          _two(
            ctx,
            OutlinedButton.icon(
              onPressed: () async {
                final d = await _pickDay(ctx, start);
                if (d == null) return;
                setState(() {
                  start = d;
                  recalc();
                });
              },
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text('Starts ${Fmt.date(start)}'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await _pickDay(ctx, expiry);
                if (d != null) setState(() => expiry = d);
              },
              icon: const Icon(Icons.event_available_outlined, size: 18),
              label: Text('Ends ${Fmt.date(expiry)}'),
            ),
          ),
          if (!isTrial) ...[
            const SizedBox(height: Space.md),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(
                labelText: 'Amount for this period',
                prefixText: '₹ ',
                helperText: cycle == 'yearly' ? 'Counted as amount ÷ 12 in MRR' : null,
              ),
            ),
            const SizedBox(height: Space.md),
            _payChoice(paid, (v) => setState(() => paid = v)),
            const SizedBox(height: Space.xs),
            Text('"Already paid" does not record money. Use Record payment for that.', style: TextStyle(color: ctx.palette.inkSubtle, fontSize: 12)),
          ],
        ],
      );
    },
    actions: (ctx) => [
      OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      if (usable.isNotEmpty)
        StatefulBuilder(
          builder: (ctx2, setBtn) => FilledButton(
            key: const Key('assign-save'),
            onPressed: saving
                ? null
                : () async {
                    if (!expiry.isAfter(start)) return showError(ctx, 'The end date must be after the start date.');
                    setBtn(() => saving = true);
                    final isTrial = plan?.tier == PlanTier.trial;
                    try {
                      await AdminService.instance.assignPlan(
                        cafe,
                        plan: plan,
                        cycle: isTrial ? 'trial' : cycle,
                        status: isTrial ? SubscriptionStatus.trial : (paid == 'paid' ? SubscriptionStatus.active : SubscriptionStatus.pending),
                        start: start,
                        expiry: expiry,
                        amount: isTrial ? 0 : (double.tryParse(amount.text.trim()) ?? 0),
                        paymentStatus: isTrial ? 'none' : paid,
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        showSuccess(context, 'Plan saved for ${cafe.name}');
                      }
                    } catch (e) {
                      setBtn(() => saving = false);
                      if (ctx.mounted) showError(ctx, friendlyError(e, 'save'));
                    }
                  },
            child: Text(saving ? 'Saving…' : 'Save'),
          ),
        ),
    ],
  );
}

/// "Payment pending" / "Already paid" as chips (they wrap on narrow phones).
Widget _payChoice(String value, ValueChanged<String> onChanged) => Wrap(
  spacing: Space.sm,
  runSpacing: Space.xs,
  children: [
    ChoiceChip(label: const Text('Payment pending'), selected: value == 'pending', onSelected: (_) => onChanged('pending')),
    ChoiceChip(label: const Text('Already paid'), selected: value == 'paid', onSelected: (_) => onChanged('paid')),
  ],
);

Future<void> showRenew(BuildContext context, CafeSummary cafe) {
  final now = DateTime.now();
  final from = cafe.expiryDate != null && cafe.expiryDate!.isAfter(now) ? cafe.expiryDate! : now;
  var months = cafe.billingCycle == 'yearly' ? 12 : 1;
  DateTime until() => DateTime(from.year, from.month + months, from.day);
  var paid = 'pending';
  var saving = false;
  return _sheet<void>(
    context,
    title: 'Renew · ${cafe.name}',
    body: (ctx, setState) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${cafe.planName ?? 'Current plan'} · currently ${cafe.expiryDate == null ? 'no end date' : 'ends ${Fmt.date(cafe.expiryDate)}'}'),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          children: [
            for (final m in [1, 3, 6, 12])
              ChoiceChip(
                label: Text(m == 12 ? '1 year' : '$m month${m == 1 ? '' : 's'}'),
                selected: months == m,
                onSelected: (_) => setState(() => months = m),
              ),
          ],
        ),
        const SizedBox(height: Space.md),
        Text('New end date: ${Fmt.date(until())}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: Space.md),
        _payChoice(paid, (v) => setState(() => paid = v)),
      ],
    ),
    actions: (ctx) => [
      OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      StatefulBuilder(
        builder: (ctx2, setBtn) => FilledButton(
          onPressed: saving
              ? null
              : () async {
                  setBtn(() => saving = true);
                  try {
                    await AdminService.instance.renew(cafe, newExpiry: until(), paymentStatus: paid);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      showSuccess(context, '${cafe.name} renewed until ${Fmt.date(until())}');
                    }
                  } catch (e) {
                    setBtn(() => saving = false);
                    if (ctx.mounted) showError(ctx, friendlyError(e, 'renew'));
                  }
                },
          child: Text(saving ? 'Saving…' : 'Renew'),
        ),
      ),
    ],
  );
}

Future<void> confirmCancelSubscription(BuildContext context, CafeSummary cafe) async {
  final ok = await showDangerConfirmDialog(
    context,
    title: 'Cancel ${cafe.name}\'s subscription?',
    message:
        'It will not be renewed. The cafe keeps working until ${cafe.expiryDate == null ? 'you set an end date' : Fmt.date(cafe.expiryDate)}; no data is deleted.',
    confirmLabel: 'Cancel subscription',
  );
  if (!ok || !context.mounted) return;
  try {
    await AdminService.instance.cancel(cafe);
    if (context.mounted) showSuccess(context, 'Subscription cancelled');
  } catch (e) {
    if (context.mounted) showError(context, friendlyError(e, 'cancel the subscription'));
  }
}

// =============================================================== payment ==

/// Records money already received (manual). Never claims a gateway payment.
Future<void> showRecordPayment(BuildContext context, List<CafeSummary> cafes, {CafeSummary? cafe}) {
  final live = cafes.where((c) => !c.isDeleted).toList();
  var selected = cafe ?? live.firstOrNull;
  final amount = TextEditingController(text: selected != null && selected.amount > 0 ? _num(selected.amount) : '');
  final ref = TextEditingController();
  final notes = TextEditingController();
  var method = paymentMethods.first;
  var paidAt = DateTime.now();
  var extend = true;
  int monthsFor(CafeSummary? c) => c?.billingCycle == 'yearly' ? 12 : 1;
  DateTime extendFrom(CafeSummary c) => c.expiryDate != null && c.expiryDate!.isAfter(DateTime.now()) ? c.expiryDate! : DateTime.now();
  DateTime extendTo(CafeSummary c) {
    final f = extendFrom(c);
    return DateTime(f.year, f.month + monthsFor(c), f.day);
  }

  var saving = false;
  return _sheet<void>(
    context,
    title: 'Record payment',
    body: (ctx, setState) {
      if (live.isEmpty) return const Text('No cafes yet.');
      final c = selected!;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'For money already received (UPI, cash, bank). The app does not collect payments.',
            style: TextStyle(color: ctx.palette.inkSubtle, fontSize: 13),
          ),
          const SizedBox(height: Space.md),
          if (cafe == null) ...[
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: c.id,
              decoration: const InputDecoration(labelText: 'Cafe'),
              items: [for (final x in live) DropdownMenuItem(value: x.id, child: Text(x.name))],
              onChanged: (id) => setState(() {
                selected = live.firstWhere((x) => x.id == id);
                if (selected!.amount > 0) amount.text = _num(selected!.amount);
              }),
            ),
            const SizedBox(height: Space.md),
          ],
          _two(
            ctx,
            TextField(
              key: const Key('payment-amount'),
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: 'Amount received *', prefixText: '₹ '),
            ),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: method,
              decoration: const InputDecoration(labelText: 'Method'),
              items: [for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setState(() => method = v ?? method),
            ),
          ),
          const SizedBox(height: Space.md),
          _two(
            ctx,
            TextField(
              controller: ref,
              decoration: const InputDecoration(labelText: 'Transaction / reference ID'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await _pickDay(ctx, paidAt);
                if (d != null) setState(() => paidAt = d);
              },
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text('Received ${Fmt.date(paidAt)}'),
            ),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: notes,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          if (c.hasSubscription)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: extend,
              onChanged: (v) => setState(() => extend = v),
              title: const Text('Extend the subscription'),
              subtitle: Text(extend ? 'Until ${Fmt.date(extendTo(c))} (${monthsFor(c) == 12 ? '1 year' : '1 month'})' : 'Only record the payment'),
            ),
        ],
      );
    },
    actions: (ctx) => [
      OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      if (live.isNotEmpty)
        StatefulBuilder(
          builder: (ctx2, setBtn) => FilledButton(
            key: const Key('payment-save'),
            onPressed: saving
                ? null
                : () async {
                    final a = double.tryParse(amount.text.trim()) ?? 0;
                    if (a <= 0) return showError(ctx, 'Enter the amount received.');
                    final c = selected!;
                    setBtn(() => saving = true);
                    try {
                      final doExtend = extend && c.hasSubscription;
                      final no = await AdminService.instance.recordPayment(
                        cafe: c,
                        amount: a,
                        method: method,
                        referenceId: ref.text,
                        notes: notes.text,
                        paidAt: paidAt,
                        periodStart: doExtend ? extendFrom(c) : null,
                        periodEnd: doExtend ? extendTo(c) : null,
                        extendTo: doExtend ? extendTo(c) : null,
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        showSuccess(context, 'Payment recorded · $no');
                      }
                    } catch (e) {
                      setBtn(() => saving = false);
                      if (ctx.mounted) showError(ctx, friendlyError(e, 'record the payment'));
                    }
                  },
            child: Text(saving ? 'Saving…' : 'Record payment'),
          ),
        ),
    ],
  );
}

/// After a cafe is created: how to give it a login.
Future<void> showNewCafeLoginHelp(BuildContext context, String cafeId, String cafeName) => showAdminCommand(
  context,
  title: '$cafeName is created',
  why:
      'Now create its login. Logins need the admin script (they are Firebase accounts with a role and the cafe ID). '
      'Pick a short username; staff sign in with it and choose Manager or Captain view.',
  command: loginCommand(cafeId),
);

/// Short date or a dash.
String fmtDate(DateTime? d) => d == null ? '—' : Fmt.date(d);

/// Why logins are not created inside the app.
const kLoginHelp =
    'Logins are Firebase accounts with a role and a cafe. They are created and switched on/off with the '
    'admin script on your computer (it needs the private service key, which must never be in the app).';
