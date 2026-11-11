import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../core/subscription/cafe_access.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../auth/login_screen.dart';
import '../staff/staff_management_screen.dart';
import 'admin_service.dart';
import 'cafe_detail_screen.dart';

/// Create a new cafe (full onboarding form) or edit an existing cafe's profile.
class CafeFormScreen extends StatefulWidget {
  const CafeFormScreen({super.key, this.cafe});

  /// null = create.
  final CafeSummary? cafe;

  @override
  State<CafeFormScreen> createState() => _CafeFormScreenState();
}

class _CafeFormScreenState extends State<CafeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.cafe?.name ?? '');
  late final _owner = TextEditingController(text: widget.cafe?.ownerName ?? '');
  late final _ownerEmail = TextEditingController(text: widget.cafe?.ownerEmail ?? '');
  late final _phone = TextEditingController(text: widget.cafe?.contactNumber ?? '');
  late final _address = TextEditingController(text: widget.cafe?.address ?? '');
  late final _gst = TextEditingController(text: widget.cafe?.gstNumber ?? '');

  // create-only
  String? _logoBase64;
  SubscriptionPlan? _plan;
  String _subStatus = SubscriptionStatus.trial;
  DateTime _start = DateTime.now();
  DateTime _expiry = DateTime.now().add(const Duration(days: 14));
  final _amount = TextEditingController(text: '0');
  String _paymentStatus = 'pending';
  bool _recordPayment = false;
  final _payAmount = TextEditingController();
  String _payMethod = 'UPI';
  final _payRef = TextEditingController();
  bool _addManager = true;
  final _managerName = TextEditingController();
  final _managerEmail = TextEditingController();

  bool _saving = false;
  bool get _isEdit => widget.cafe != null;

  @override
  void dispose() {
    for (final c in [_name, _owner, _ownerEmail, _phone, _address, _gst, _amount, _payAmount, _payRef, _managerName, _managerEmail]) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPlan(SubscriptionPlan? p) {
    setState(() {
      _plan = p;
      if (p != null) {
        _amount.text = formatAmount(p.price);
        _expiry = _start.add(Duration(days: p.durationDays));
        if (_subStatus == SubscriptionStatus.trial) _subStatus = SubscriptionStatus.active;
      }
    });
  }

  Future<void> _pickLogo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = res?.files.single;
    if (f?.bytes == null) return;
    if (f!.size > 300 * 1024) {
      if (mounted) showError(context, 'Please choose a logo under 300 KB.');
      return;
    }
    setState(() => _logoBase64 = base64Encode(f.bytes!));
  }

  String? _req(String? v, String what) => (v ?? '').trim().length < 2 ? 'Please enter $what' : null;

  String? _optEmail(String? v) {
    final s = (v ?? '').trim();
    return s.isEmpty ? null : LoginValidators.email(s);
  }

  String? _optPhone(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    return RegExp(r'^[0-9+\-\s()]{6,20}$').hasMatch(s) ? null : 'Enter a valid phone number';
  }

  String? _optGst(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    return RegExp(r'^[0-9A-Za-z]{15}$').hasMatch(s) ? null : 'GSTIN has 15 letters/digits';
  }

  String? _money(String? v, {bool allowZero = true}) {
    final d = double.tryParse((v ?? '').trim());
    if (d == null || d < 0) return 'Enter an amount';
    if (!allowZero && d == 0) return 'Must be more than 0';
    return null;
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    if (!_isEdit && !_expiry.isAfter(_start)) {
      showError(context, 'Expiry date must be after the start date.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await AdminService.instance.updateCafeProfile(widget.cafe!.id, {
          'name': _name.text.trim(),
          'ownerName': _owner.text.trim(),
          'ownerEmail': _ownerEmail.text.trim().toLowerCase(),
          'contactNumber': _phone.text.trim(),
          'address': _address.text.trim(),
          'gstNumber': _gst.text.trim().toUpperCase(),
        });
        if (mounted) {
          showSuccess(context, 'Cafe updated');
          Navigator.pop(context);
        }
        return;
      }

      final result = await AdminService.instance.createCafe({
        'name': _name.text.trim(),
        'ownerName': _owner.text.trim(),
        'ownerEmail': _ownerEmail.text.trim(),
        'contactNumber': _phone.text.trim(),
        'address': _address.text.trim(),
        'gstNumber': _gst.text.trim(),
        'logoBase64': _logoBase64,
        'subscription': {
          'planId': _plan?.id,
          'planName': _plan?.name,
          'billingCycle': _plan?.billingCycle,
          'status': _subStatus,
          'startDate': _start.millisecondsSinceEpoch,
          'expiryDate': _expiry.millisecondsSinceEpoch,
          'amount': double.tryParse(_amount.text.trim()) ?? 0,
          'paymentStatus': _paymentStatus,
        },
        if (_recordPayment)
          'payment': {
            'record': true,
            'amount': double.tryParse(_payAmount.text.trim()) ?? 0,
            'method': _payMethod,
            'referenceId': _payRef.text.trim(),
            'paidAt': DateTime.now().millisecondsSinceEpoch,
          },
        if (_addManager) 'manager': {'name': _managerName.text.trim(), 'email': _managerEmail.text.trim()},
      });

      if (result.managerEmail != null && result.managerSetupLink != null) {
        await AdminService.instance.sendInviteEmail(result.managerEmail!);
      }
      if (!mounted) return;

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CafeDetailScreen(cafeId: result.cafeId)));
      if (result.managerSetupLink != null) {
        await showLinkDialog(
          context,
          title: 'Cafe created',
          message: 'Cafe ID: ${result.cafeId}\n'
              '${result.receiptNo != null ? 'Payment receipt: ${result.receiptNo}\n' : ''}'
              'An invitation email was sent to ${result.managerEmail}. You can also share this set-password link:',
          link: result.managerSetupLink!,
        );
      } else if (result.managerError != null) {
        showError(context, 'Cafe created, but the manager could not be added: ${result.managerError}');
      } else {
        showSuccess(context, 'Cafe created (ID ${result.cafeId})');
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(_isEdit ? 'Edit ${widget.cafe!.name}' : 'New cafe'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18),
              label: Text(_isEdit ? 'Save' : 'Create cafe'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  title: 'Cafe details',
                  icon: Icons.storefront_outlined,
                  child: Column(
                    children: [
                      if (!_isEdit) ...[
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _pickLogo,
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _logoBase64 == null
                                    ? const Icon(Icons.add_photo_alternate_outlined, color: Colors.black38)
                                    : Image.memory(base64Decode(_logoBase64!), fit: BoxFit.contain),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('Cafe logo (optional, under 300 KB). Printed on bills.',
                                  style: TextStyle(color: Colors.white54, fontSize: 12)),
                            ),
                            if (_logoBase64 != null)
                              TextButton(onPressed: () => setState(() => _logoBase64 = null), child: const Text('Remove')),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                      _field(_name, 'Cafe name *', validator: (v) => _req(v, 'the cafe name')),
                      _twoCols(
                        _field(_owner, 'Owner name'),
                        _field(_ownerEmail, 'Owner email', validator: _optEmail, keyboard: TextInputType.emailAddress),
                      ),
                      _twoCols(
                        _field(_phone, 'Contact number', validator: _optPhone, keyboard: TextInputType.phone),
                        _field(_gst, 'GST number (optional)', validator: _optGst),
                      ),
                      _field(_address, 'Address', maxLines: 2),
                    ],
                  ),
                ),
                if (!_isEdit) ...[
                  _subscriptionSection(),
                  _paymentSection(),
                  _managerSection(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _subscriptionSection() {
    return SectionCard(
      title: 'Subscription',
      icon: Icons.workspace_premium_outlined,
      child: Column(
        children: [
          StreamBuilder<List<SubscriptionPlan>>(
            stream: AdminService.instance.watchPlans(),
            builder: (context, snap) {
              final plans = (snap.data ?? const []).where((p) => p.isActive).toList();
              return DropdownButtonFormField<String?>(
                initialValue: _plan?.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Plan', border: OutlineInputBorder(), isDense: true),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Custom / no plan')),
                  for (final p in plans)
                    DropdownMenuItem<String?>(value: p.id, child: Text('${p.name} — ${Fmt.money(p.price)} / ${p.cycleLabel}')),
                ],
                onChanged: (id) => _applyPlan(plans.where((p) => p.id == id).firstOrNull),
              );
            },
          ),
          const SizedBox(height: 12),
          _twoCols(
            _padded(DropdownButtonFormField<String>(
              initialValue: _subStatus,
              decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
              items: [
                for (final s in SubscriptionStatus.all.where((s) => s != SubscriptionStatus.expired))
                  DropdownMenuItem(value: s, child: Text(s[0].toUpperCase() + s.substring(1))),
              ],
              onChanged: (v) => setState(() => _subStatus = v ?? _subStatus),
            )),
            _field(_amount, 'Subscription amount ₹', validator: _money, keyboard: TextInputType.number),
          ),
          _twoCols(
            _dateField('Start date', _start, (d) => setState(() {
                  _start = d;
                  if (_plan != null) _expiry = d.add(Duration(days: _plan!.durationDays));
                })),
            _dateField('Expiry date', _expiry, (d) => setState(() => _expiry = d)),
          ),
          DropdownButtonFormField<String>(
            initialValue: _paymentStatus,
            decoration: const InputDecoration(labelText: 'Payment status', border: OutlineInputBorder(), isDense: true),
            items: const [
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'paid', child: Text('Paid')),
            ],
            onChanged: (v) => setState(() {
              _paymentStatus = v ?? _paymentStatus;
              if (_paymentStatus == 'paid' && !_recordPayment) {
                _recordPayment = true;
                _payAmount.text = _amount.text;
              }
            }),
          ),
        ],
      ),
    );
  }

  Widget _paymentSection() {
    return SectionCard(
      title: 'First payment',
      icon: Icons.payments_outlined,
      trailing: Switch(value: _recordPayment, onChanged: (v) => setState(() {
            _recordPayment = v;
            if (v && _payAmount.text.isEmpty) _payAmount.text = _amount.text;
          })),
      child: !_recordPayment
          ? const Text('Turn on to record a payment received now (a receipt number is generated).',
              style: TextStyle(color: Colors.white54, fontSize: 12))
          : Column(
              children: [
                _twoCols(
                  _field(_payAmount, 'Amount received ₹ *',
                      validator: (v) => _money(v, allowZero: false), keyboard: TextInputType.number),
                  _padded(DropdownButtonFormField<String>(
                    initialValue: _payMethod,
                    decoration: const InputDecoration(labelText: 'Method', border: OutlineInputBorder(), isDense: true),
                    items: [for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m))],
                    onChanged: (v) => setState(() => _payMethod = v ?? _payMethod),
                  )),
                ),
                _field(_payRef, 'Transaction / reference ID'),
              ],
            ),
    );
  }

  Widget _managerSection() {
    return SectionCard(
      title: 'First manager',
      icon: Icons.badge_outlined,
      trailing: Switch(value: _addManager, onChanged: (v) => setState(() => _addManager = v)),
      child: !_addManager
          ? const Text('You can add managers later from the cafe\'s Staff tab.', style: TextStyle(color: Colors.white54, fontSize: 12))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('The manager receives an email to set their own password.',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 10),
                _twoCols(
                  _field(_managerName, 'Manager name *', validator: (v) => _req(v, 'the manager name')),
                  _field(_managerEmail, 'Manager email *',
                      validator: LoginValidators.email, keyboard: TextInputType.emailAddress),
                ),
              ],
            ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {String? Function(String?)? validator, TextInputType? keyboard, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        validator: validator,
        keyboardType: keyboard,
        maxLines: maxLines,
        enabled: !_saving,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      ),
    );
  }

  Widget _dateField(String label, DateTime value, ValueChanged<DateTime> onPicked) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final d = await pickDate(context, initial: value);
          if (d != null) onPicked(d);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: const Icon(Icons.calendar_today, size: 18),
          ),
          child: Text(Fmt.date(value)),
        ),
      ),
    );
  }

  Widget _padded(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);

  Widget _twoCols(Widget a, Widget b) => LayoutBuilder(
        builder: (context, c) => c.maxWidth < 520
            ? Column(children: [a, b])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: a),
                const SizedBox(width: 12),
                Expanded(child: b),
              ]),
      );
}

String formatAmount(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
