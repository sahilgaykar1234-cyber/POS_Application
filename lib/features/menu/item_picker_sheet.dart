import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'menu_models.dart';

/// Asks which size/add-ons to use for [item]. Returns null if cancelled.
/// Items with a single size and no add-ons don't need this sheet.
Future<CartLine?> showItemPickerSheet(BuildContext context, MenuItem item) {
  return showModalBottomSheet<CartLine>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ItemPicker(item: item),
  );
}

class _ItemPicker extends StatefulWidget {
  const _ItemPicker({required this.item});
  final MenuItem item;

  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  late MenuVariant _variant = widget.item.variants.first;
  final Set<String> _addOns = {};

  List<MenuAddOn> get _available => widget.item.addOns.where((a) => a.appliesTo(_variant.label)).toList();

  CartLine get _line =>
      CartLine.build(widget.item, _variant, widget.item.addOns.where((a) => _addOns.contains(a.name)).toList());

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.accent)),
            if (item.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(item.description, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            const SizedBox(height: 14),
            if (item.variants.length > 1) ...[
              const Text('Choose size', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final v in item.variants)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    tileColor: v == _variant ? AppColors.primary.withValues(alpha: 0.18) : AppColors.surfaceAlt,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: v == _variant ? AppColors.primary : Colors.transparent),
                    ),
                    leading: Icon(v == _variant ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: v == _variant ? AppColors.primary : Colors.white38),
                    title: Text(v.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: v.note.isEmpty ? null : Text(v.note, style: const TextStyle(fontSize: 12)),
                    trailing: Text('₹${formatPrice(v.price)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent, fontSize: 16)),
                    onTap: () => setState(() {
                      _variant = v;
                      // Drop add-ons that don't apply to the new size.
                      _addOns.removeWhere((n) => !_available.any((a) => a.name == n));
                    }),
                  ),
                ),
            ],
            if (_available.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Add-ons', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final a in _available)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _addOns.contains(a.name),
                  onChanged: (sel) => setState(() => sel == true ? _addOns.add(a.name) : _addOns.remove(a.name)),
                  title: Text(a.name),
                  secondary: Text('+₹${formatPrice(a.price)}', style: const TextStyle(color: AppColors.accent)),
                ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, _line),
                child: Text('Add to order  ·  ₹${formatPrice(_line.unitPrice)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
