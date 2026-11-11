import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import 'admin_service.dart';
import 'cafe_form_screen.dart' show formatAmount;

/// Subscription plans you sell (monthly / yearly / custom).
class PlansTab extends StatelessWidget {
  const PlansTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-plan',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New plan', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => showDialog(context: context, builder: (_) => const _PlanDialog()),
      ),
      body: StreamBuilder<List<SubscriptionPlan>>(
        stream: AdminService.instance.watchPlans(),
        builder: (context, snap) {
          if (snap.hasError) return const EmptyState(icon: Icons.error_outline, title: 'Could not load plans');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          final plans = snap.data!;
          if (plans.isEmpty) {
            return const EmptyState(
              icon: Icons.workspace_premium_outlined,
              title: 'No plans yet',
              message: 'Create plans like "Monthly ₹999" or "Yearly ₹9,999" and assign them to cafes.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              ResponsiveGrid(
                minTileWidth: 260,
                children: [for (final p in plans) _PlanCard(plan: p)],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});
  final SubscriptionPlan plan;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: plan.isActive ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(plan.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              StatusChip(plan.isActive ? 'active' : 'inactive'),
            ]),
            const SizedBox(height: 8),
            Text(Fmt.money(plan.price), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.accent)),
            Text('per ${plan.cycleLabel.toLowerCase()} (${plan.durationDays} days)', style: const TextStyle(color: Colors.white54)),
            if (plan.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(plan.description, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
                onPressed: () => showDialog(context: context, builder: (_) => _PlanDialog(plan: plan)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanDialog extends StatefulWidget {
  const _PlanDialog({this.plan});
  final SubscriptionPlan? plan;

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.plan?.name ?? '');
  late final _price = TextEditingController(text: widget.plan == null ? '' : formatAmount(widget.plan!.price));
  late final _days = TextEditingController(text: '${widget.plan?.durationDays ?? 30}');
  late final _desc = TextEditingController(text: widget.plan?.description ?? '');
  late String _cycle = widget.plan?.billingCycle ?? 'monthly';
  late bool _active = widget.plan?.isActive ?? true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _price, _days, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AdminService.instance.savePlan(
        id: widget.plan?.id,
        name: _name.text,
        billingCycle: _cycle,
        price: double.parse(_price.text.trim()),
        durationDays: int.parse(_days.text.trim()),
        description: _desc.text,
        isActive: _active,
      );
      if (mounted) {
        Navigator.pop(context);
        showSuccess(context, 'Plan saved');
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
      title: Text(widget.plan == null ? 'New plan' : 'Edit plan'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Plan name *', hintText: 'e.g. Basic Monthly', border: OutlineInputBorder()),
                  validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _cycle,
                  decoration: const InputDecoration(labelText: 'Billing cycle', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom duration')),
                  ],
                  onChanged: (v) => setState(() {
                    _cycle = v ?? _cycle;
                    if (_cycle == 'monthly') _days.text = '30';
                    if (_cycle == 'yearly') _days.text = '365';
                  }),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Price ₹ *', border: OutlineInputBorder()),
                      validator: (v) => (double.tryParse((v ?? '').trim()) ?? -1) < 0 ? 'Enter a price' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _days,
                      enabled: _cycle == 'custom',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Days', border: OutlineInputBorder()),
                      validator: (v) {
                        final d = int.tryParse((v ?? '').trim());
                        return d == null || d < 1 || d > 3660 ? '1–3660' : null;
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _desc,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder()),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  title: const Text('Available for new subscriptions'),
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
}
