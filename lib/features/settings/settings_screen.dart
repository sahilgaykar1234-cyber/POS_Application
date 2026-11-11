import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/theme_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/ui.dart';
import 'business_settings.dart';

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
      if (mounted) showError(context, 'Please choose a logo under 300 KB.');
      return;
    }
    setState(() {
      _logo = base64Encode(f.bytes!);
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
        'numberOfTables': tables,
      });
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
        _c['numberOfTables']!.text = '$tables';
      });
      showSuccess(context, 'Settings saved');
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, 'Could not save settings. Please check your connection.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingState(label: 'Loading settings…');
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
                      child: Text('You have unsaved changes', style: TextStyle(color: p.inkSubtle)),
                    ),
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () {
                              setState(() => _loading = true);
                              _dirty = false;
                              _load();
                            },
                      child: const Text('Discard'),
                    ),
                    const SizedBox(width: Space.sm),
                    FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save changes')),
                  ],
                ),
              ),
            ),

      body: Form(
        key: _form,
        child: PageBody(

          children: [
            const PageHeader(title: 'Settings', subtitle: 'Cafe details, billing and receipts'),
            LayoutBuilder(
              builder: (context, c) {
                final profile = SectionCard(
                  title: 'Cafe profile',
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
                            child: _logo == null
                                ? const Center(child: AppLogo(size: 44))
                                : Image.memory(base64Decode(_logo!), fit: BoxFit.contain),
                          ),
                          const SizedBox(width: Space.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Logo', style: context.text.titleSmall),
                                Text('Printed on bills. PNG/JPG under 300 KB.', style: TextStyle(color: p.inkSubtle, fontSize: 12)),
                                const SizedBox(height: Space.sm),
                                Wrap(
                                  spacing: Space.sm,
                                  children: [
                                    OutlinedButton(onPressed: _pickLogo, child: Text(_logo == null ? 'Upload' : 'Change')),
                                    if (_logo != null)
                                      TextButton(
                                        style: TextButton.styleFrom(foregroundColor: p.danger),
                                        onPressed: () => setState(() {
                                          _logo = null;
                                          _dirty = true;
                                        }),
                                        child: const Text('Remove'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.lg),
                      _row([_field('shopName', 'Cafe name', required: true), _field('tagline', 'Tagline')]),
                      _row([_field('ownerName', 'Owner name'), _field('mobileNumber', 'Mobile number', keyboard: TextInputType.phone)]),
                      _row([_field('email', 'Email', keyboard: TextInputType.emailAddress), _field('gstNumber', 'GST number')]),
                      _field('address', 'Address', maxLines: 2),
                    ],
                  ),
                );
                final billing = SectionCard(
                  title: 'Billing',
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
                        title: const Text('Add GST to bills', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('New orders include GST at the rate below.'),
                      ),
                      const SizedBox(height: Space.sm),
                      _row([
                        _field('gstPercentage', 'GST %', keyboard: const TextInputType.numberWithOptions(decimal: true), number: true),
                        _field('numberOfTables', 'Number of tables', keyboard: TextInputType.number, number: true),
                      ]),
                      _row([_field('currencySymbol', 'Currency symbol'), _field('currencyCode', 'Currency code')]),
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: Row(
                          children: [
                            Expanded(child: Text('Default order type', style: context.text.titleSmall)),
                            SegmentedButton<String>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(value: 'Dine-In', label: Text('Dine-in')),
                                ButtonSegment(value: 'Takeaway', label: Text('Takeaway')),
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
                        title: const Text('Auto bill number'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _autoToken,
                        onChanged: (v) => setState(() {
                          _autoToken = v;
                          _dirty = true;
                        }),
                        title: const Text('Auto token number'),
                      ),
                    ],
                  ),
                );
                final receipt = SectionCard(
                  title: 'Receipt text',
                  icon: Icons.print_outlined,
                  child: Column(
                    children: [
                      _field('receiptHeader', 'Header'),
                      _field('thankYouMessage', 'Thank-you message'),
                      _field('receiptFooter', 'Footer'),
                    ],
                  ),
                );
                final appearance = SectionCard(
                  title: 'Appearance',
                  icon: Icons.palette_outlined,
                  subtitle: 'Saved on this device only',
                  child: ValueListenableBuilder<ThemeMode>(
                    valueListenable: ThemeController.instance,
                    builder: (context, mode, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined, size: 18)),
                          ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined, size: 18)),
                          ButtonSegment(value: ThemeMode.system, label: Text('Auto'), icon: Icon(Icons.brightness_auto_outlined, size: 18)),
                        ],
                        selected: {mode},
                        onSelectionChanged: (s) => ThemeController.instance.set(s.first),
                      ),
                    ),
                  ),
                );
                if (c.maxWidth < 1000) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [profile, billing, receipt, appearance]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [profile, receipt]),
                    ),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [billing, appearance]),
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
        validator: required ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null : null,
      ),
    );
  }
}
