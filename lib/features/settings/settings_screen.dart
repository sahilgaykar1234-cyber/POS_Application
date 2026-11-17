import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/theme_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/business_day.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/ui.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
import '../../core/auth/manager_pin.dart';
import '../../core/services/audit_service.dart';
import '../../core/utils/friendly_error.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../customers/customer_privacy.dart';
import 'business_settings.dart';
import 'package:pos_app/core/i18n/tr.dart';
import 'package:pos_app/core/i18n/language_picker.dart';

/// Cafe settings (same fields and keys as before) + appearance.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.loader});

  /// Test hook (default: load from Firestore).
  final Future<BusinessSettings> Function()? loader;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{
    for (final k in [
      'shopName',
      'tagline',
      'ownerName',
      'mobileNumber',
      'email',
      'gstNumber',
      'address',
      'receiptHeader',
      'receiptFooter',
      'thankYouMessage',
      'gstPercentage',
      'currencySymbol',
      'currencyCode',
      'defaultTax',
      'numberOfTables',
    ])
      k: TextEditingController(),
  };
  String? _logo;
  bool _showGst = false;
  bool _autoBill = true;
  bool _autoToken = true;
  int _dayEnds = BusinessDay.defaultCutoffMinutes;
  int _keepMonths = 24;
  bool _pinSet = false;
  String _defaultOrderType = 'Dine-In';
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await (widget.loader ?? BusinessSettingsRepository.instance.load)();
      if (!mounted) return;
      setState(() {
        _c['shopName']!.text = s.shopName;
        _c['tagline']!.text = s.tagline;
        _c['ownerName']!.text = s.ownerName;
        _c['mobileNumber']!.text = s.mobileNumber;
        _c['email']!.text = s.email;
        _c['gstNumber']!.text = s.gstNumber;
        _c['address']!.text = s.address;
        _c['receiptHeader']!.text = s.receiptHeader;
        _c['receiptFooter']!.text = s.receiptFooter;
        _c['thankYouMessage']!.text = s.thankYouMessage;
        _c['gstPercentage']!.text = (s.data['gstPercentage'] ?? '5').toString();
        _c['currencySymbol']!.text = s.currencySymbol;
        _c['currencyCode']!.text = s.currencyCode;
        _c['defaultTax']!.text = s.defaultTax;
        _c['numberOfTables']!.text = '${s.numberOfTables}';
        _logo = s.logoBase64;
        _showGst = s.showGst;
        _autoBill = s.autoGenBillNumber;
        _autoToken = s.autoGenTokenNumber;
        _dayEnds = s.dayEndsAtMinutes;
        _keepMonths = s.customerDataMonths;
        _pinSet = s.hasManagerPin;
        _defaultOrderType = s.defaultOrderType;
        _loading = false;
      });
      for (final c in _c.values) {
        c.addListener(_markDirty);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = res?.files.single;
    if (f?.bytes == null) return;
    if (f!.size > 300 * 1024) {
      if (mounted) showError(context, tr('Please choose a logo under 300 KB.'));
      return;
    }
    setState(() {
      _logo = base64Encode(f.bytes!);
      _dirty = true;
    });
  }

  Future<void> _setPin() async {
    final pin = TextEditingController();
    final again = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          void save() {
            if (!ManagerPin.isValid(pin.text)) return setState(() => error = tr('Use 4 to 8 digits.'));
            if (pin.text != again.text) return setState(() => error = tr('The two PINs don\'t match.'));
            Navigator.pop(ctx, true);
          }

          return AlertDialog(
            title: Text(_pinSet ? tr('Change Manager PIN') : tr('Set Manager PIN')),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr('Staff using the cafe login will need this PIN to open the Manager view. For the kitchen, a separate "Kitchen only" login is even safer.'),
                  ),
                  const SizedBox(height: Space.md),
                  TextField(
                    key: const Key('pin-new'),
                    controller: pin,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: tr('New PIN (4–8 digits)')),
                  ),
                  TextField(
                    key: const Key('pin-again'),
                    controller: again,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: tr('PIN again'), errorText: error),
                    onSubmitted: (_) => save(),
                  ),
                ],
              ),
            ),
            actions: [
              OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
              FilledButton(key: const Key('pin-save'), onPressed: save, child: Text(tr('Save PIN'))),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    final salt = ManagerPin.newSalt();
    try {
      await BusinessSettingsRepository.instance.save({'managerPinSalt': salt, 'managerPinHash': ManagerPin.hash(pin.text, salt)});
      await AuditService.instance.log('settings.managerPin', details: {'pin': 'set'});
      if (!mounted) return;
      setState(() => _pinSet = true);
      showSuccess(context, tr('Manager PIN saved'));
    } catch (e) {
      if (mounted) showError(context, friendlyError(e, tr('save the PIN')));
    }
  }

  Future<void> _removePin() async {
    final ok = await showConfirmDialog(
      context,
      title: tr('Remove the Manager PIN?'),
      message: tr('Anyone with the cafe login can then open the Manager view.'),
      confirmLabel: tr('Remove'),
    );
    if (!ok || !mounted) return;
    try {
      await BusinessSettingsRepository.instance.save({'managerPinSalt': FieldValue.delete(), 'managerPinHash': FieldValue.delete()});
      await AuditService.instance.log('settings.managerPin', details: {'pin': 'removed'});
      if (!mounted) return;
      setState(() => _pinSet = false);
      showSuccess(context, tr('Manager PIN removed'));
    } catch (e) {
      if (mounted) showError(context, friendlyError(e, tr('remove the PIN')));
    }
  }

  Future<void> _removeOldCustomerData() async {
    final ok = await showDangerConfirmDialog(
      context,
      title: tr('Remove old customer data?'),
      message: tr('Customer names and numbers on bills older than {0} months will be cleared. Bills, amounts and reports stay. This cannot be undone.', [_keepMonths]),
      confirmLabel: tr('Remove'),
    );
    if (!ok || !mounted) return;
    try {
      final n = await CustomerPrivacy.instance.removeOlderThan(_keepMonths);
      if (mounted) showSuccess(context, n == 0 ? tr('Nothing to remove') : tr('Customer data removed from {0} old bills', [n]));
    } catch (e) {
      if (mounted) showError(context, friendlyError(e, tr('remove the data')));
    }
  }

  Future<void> _pickDayEnd() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _dayEnds ~/ 60, minute: _dayEnds % 60),
      helpText: tr('BUSINESS DAY ENDS AT (AFTER MIDNIGHT)'),
    );
    if (t == null || !mounted) return;
    final m = t.hour * 60 + t.minute;
    if (m > BusinessDay.maxCutoffMinutes) {
      showError(context, tr('Pick a time between 12:00 AM and 12:00 PM (after midnight).'));
      return;
    }
    setState(() {
      _dayEnds = m;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      var tables = int.tryParse(_c['numberOfTables']!.text.trim()) ?? 12;
      if (tables <= 0) tables = 12;
      await BusinessSettingsRepository.instance.save({
        'shopLogoBase64': _logo,
        'shopName': _c['shopName']!.text.trim(),
        'tagline': _c['tagline']!.text.trim(),
        'ownerName': _c['ownerName']!.text.trim(),
        'mobileNumber': _c['mobileNumber']!.text.trim(),
        'email': _c['email']!.text.trim(),
        'gstNumber': _c['gstNumber']!.text.trim(),
        'address': _c['address']!.text.trim(),
        'receiptHeader': _c['receiptHeader']!.text.trim(),
        'receiptFooter': _c['receiptFooter']!.text.trim(),
        'thankYouMessage': _c['thankYouMessage']!.text.trim(),
        'showGst': _showGst,
        'gstPercentage': _c['gstPercentage']!.text.trim(),
        'currencySymbol': _c['currencySymbol']!.text.trim(),
        'currencyCode': _c['currencyCode']!.text.trim(),
        'defaultOrderType': _defaultOrderType,
        'defaultTax': _c['defaultTax']!.text.trim(),
        'autoGenBillNumber': _autoBill,
        'autoGenTokenNumber': _autoToken,
        'dayEndsAt': BusinessDay.format(_dayEnds),
        'customerDataMonths': _keepMonths,
        'numberOfTables': tables,
      });
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
        _c['numberOfTables']!.text = '$tables';
      });
      showSuccess(context, tr('Settings saved'));
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, tr('Could not save settings. Please check your connection.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return LoadingState(label: tr('Loading settings…'));
    final p = context.palette;

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Only present while there are unsaved changes, so it never takes space
      // (and cuts the page) when hidden.
      bottomNavigationBar: !_dirty
          ? null
          : Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: p.surface,
                border: Border(top: BorderSide(color: p.border)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(tr('You have unsaved changes'), style: TextStyle(color: p.inkSubtle)),
                    ),
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () {
                              setState(() => _loading = true);
                              _dirty = false;
                              _load();
                            },
                      child: Text(tr('Discard')),
                    ),
                    const SizedBox(width: Space.sm),
                    FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? tr('Saving…') : tr('Save changes'))),
                  ],
                ),
              ),
            ),

      body: Form(
        key: _form,
        child: PageBody(
          children: [
            PageHeader(title: tr('Settings'), subtitle: tr('Cafe details, billing and receipts')),
            LayoutBuilder(
              builder: (context, c) {
                final profile = SectionCard(
                  title: tr('Cafe profile'),
                  icon: Icons.storefront_outlined,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: Radii.cardR,
                              border: Border.all(color: p.border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: _logo == null ? const Center(child: AppLogo(size: 44)) : Image.memory(base64Decode(_logo!), fit: BoxFit.contain),
                          ),
                          const SizedBox(width: Space.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr('Logo'), style: context.text.titleSmall),
                                Text(tr('Printed on bills. PNG/JPG under 300 KB.'), style: TextStyle(color: p.inkSubtle, fontSize: 12)),
                                const SizedBox(height: Space.sm),
                                Wrap(
                                  spacing: Space.sm,
                                  children: [
                                    OutlinedButton(onPressed: _pickLogo, child: Text(_logo == null ? tr('Upload') : tr('Change'))),
                                    if (_logo != null)
                                      TextButton(
                                        style: TextButton.styleFrom(foregroundColor: p.danger),
                                        onPressed: () => setState(() {
                                          _logo = null;
                                          _dirty = true;
                                        }),
                                        child: Text(tr('Remove')),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.lg),
                      _row([_field('shopName', tr('Cafe name'), required: true), _field('tagline', tr('Tagline'))]),
                      _row([_field('ownerName', tr('Owner name')), _field('mobileNumber', tr('Mobile number'), keyboard: TextInputType.phone)]),
                      _row([_field('email', tr('Email'), keyboard: TextInputType.emailAddress), _field('gstNumber', tr('GST number'))]),
                      _field('address', tr('Address'), maxLines: 2),
                    ],
                  ),
                );
                final billing = SectionCard(
                  title: tr('Billing'),
                  icon: Icons.receipt_long_outlined,
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _showGst,
                        onChanged: (v) => setState(() {
                          _showGst = v;
                          _dirty = true;
                        }),
                        title: Text(tr('Add GST to bills'), style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(tr('New orders include GST at the rate below.')),
                      ),
                      const SizedBox(height: Space.sm),
                      _row([
                        _field('gstPercentage', tr('GST %'), keyboard: const TextInputType.numberWithOptions(decimal: true), number: true),
                        _field('numberOfTables', tr('Number of tables'), keyboard: TextInputType.number, number: true),
                      ]),
                      _row([_field('currencySymbol', tr('Currency symbol')), _field('currencyCode', tr('Currency code'))]),
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: Row(
                          children: [
                            Expanded(child: Text(tr('Default order type'), style: context.text.titleSmall)),
                            SegmentedButton<String>(
                              showSelectedIcon: false,
                              segments: [
                                ButtonSegment(value: 'Dine-In', label: Text(tr('Dine-in'))),
                                ButtonSegment(value: 'Takeaway', label: Text(tr('Takeaway'))),
                              ],
                              selected: {_defaultOrderType == 'Takeaway' ? 'Takeaway' : 'Dine-In'},
                              onSelectionChanged: (s) => setState(() {
                                _defaultOrderType = s.first;
                                _dirty = true;
                              }),
                            ),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _autoBill,
                        onChanged: (v) => setState(() {
                          _autoBill = v;
                          _dirty = true;
                        }),
                        title: Text(tr('Auto bill number')),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _autoToken,
                        onChanged: (v) => setState(() {
                          _autoToken = v;
                          _dirty = true;
                        }),
                        title: Text(tr('Auto token number')),
                      ),
                      ListTile(
                        key: const Key('settings-day-ends'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr('Business day ends at')),
                        subtitle: Text(
                          tr('Orders after midnight until this time count in the previous day (e.g. open 7 PM – 2 AM = one day). Tokens restart at this time.'),
                        ),
                        trailing: OutlinedButton.icon(
                          onPressed: _pickDayEnd,
                          icon: const Icon(Icons.schedule_rounded, size: 18),
                          label: Text(BusinessDay.label(_dayEnds)),
                        ),
                      ),
                    ],
                  ),
                );
                final receipt = SectionCard(
                  title: tr('Receipt text'),
                  icon: Icons.print_outlined,
                  child: Column(
                    children: [_field('receiptHeader', tr('Header')), _field('thankYouMessage', tr('Thank-you message')), _field('receiptFooter', tr('Footer'))],
                  ),
                );
                final security = SectionCard(
                  title: tr('Security & privacy'),
                  icon: Icons.shield_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr('Manager PIN')),
                        subtitle: Text(
                          _pinSet
                              ? tr('On – the Manager view (sales, cancelling bills, settings) asks for it.')
                              : tr('Off – anyone with the cafe login can open the Manager view.'),
                        ),
                        trailing: Wrap(
                          spacing: Space.xs,
                          children: [
                            OutlinedButton(key: const Key('pin-set'), onPressed: _setPin, child: Text(_pinSet ? tr('Change') : tr('Set PIN'))),
                            if (_pinSet) TextButton(onPressed: _removePin, child: Text(tr('Remove'))),
                          ],
                        ),
                      ),
                      const Divider(height: Space.xl),
                      Text(tr('Customer data'), style: context.text.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        tr('Names and mobile numbers are used only for bills, WhatsApp and the customer list. They are removed from old bills after the time below (the bills and amounts stay).'),
                        style: TextStyle(color: p.inkSubtle, fontSize: 13),
                      ),
                      const SizedBox(height: Space.md),
                      Row(
                        children: [
                          Expanded(child: Text(tr('Keep customer numbers for'))),
                          DropdownButton<int>(
                            value: const [12, 24, 36, 0].contains(_keepMonths) ? _keepMonths : 24,
                            items: [
                              DropdownMenuItem(value: 12, child: Text(tr('12 months'))),
                              DropdownMenuItem(value: 24, child: Text(tr('24 months'))),
                              DropdownMenuItem(value: 36, child: Text(tr('36 months'))),
                              DropdownMenuItem(value: 0, child: Text(tr('Always'))),
                            ],
                            onChanged: (v) => setState(() {
                              _keepMonths = v ?? _keepMonths;
                              _dirty = true;
                            }),
                          ),
                        ],
                      ),
                      if (_keepMonths > 0)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _removeOldCustomerData,
                            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                            label: Text(tr('Remove numbers older than {0} months now', [_keepMonths])),
                          ),
                        ),
                    ],
                  ),
                );
                final language = SectionCard(
                  title: tr('Language'),
                  icon: Icons.translate_rounded,
                  subtitle: tr('For this login on this device. Bills and WhatsApp messages stay in English.'),
                  child: const Align(alignment: Alignment.centerLeft, child: LanguagePicker()),
                );
                final appearance = SectionCard(
                  title: tr('Appearance'),
                  icon: Icons.palette_outlined,
                  subtitle: tr('Saved on this device only'),
                  child: ValueListenableBuilder<ThemeMode>(
                    valueListenable: ThemeController.instance,
                    builder: (context, mode, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: ThemeMode.light, label: Text(tr('Light')), icon: Icon(Icons.light_mode_outlined, size: 18)),
                          ButtonSegment(value: ThemeMode.dark, label: Text(tr('Dark')), icon: Icon(Icons.dark_mode_outlined, size: 18)),
                          ButtonSegment(value: ThemeMode.system, label: Text(tr('Auto')), icon: Icon(Icons.brightness_auto_outlined, size: 18)),
                        ],
                        selected: {mode},
                        onSelectionChanged: (s) => ThemeController.instance.set(s.first),
                      ),
                    ),
                  ),
                );
                if (c.maxWidth < 1000) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [language, profile, billing, security, receipt, appearance]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [profile, security, receipt]),
                    ),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [language, billing, appearance]),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) => LayoutBuilder(
    builder: (context, c) => c.maxWidth < 520
        ? Column(children: children)
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: Space.md), Expanded(child: children[i])],
            ],
          ),
  );

  Widget _field(String key, String label, {bool required = false, TextInputType? keyboard, int maxLines = 1, bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: TextFormField(
        controller: _c[key],
        keyboardType: keyboard,
        maxLines: maxLines,
        inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
        decoration: InputDecoration(labelText: required ? '$label *' : label),
        validator: required ? (v) => (v ?? '').trim().isEmpty ? tr('Required') : null : null,
      ),
    );
  }
}
