import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'menu_models.dart';

/// Asks which size/add-ons to use for [item]. Returns null if cancelled.
/// Items with a single size and no add-ons don't need this sheet.
Future<CartLine?> showItemPickerSheet(BuildContext context, MenuItem item) {
  return showModalBottomSheet<CartLine>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 520),
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
    final p = context.palette;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.name, style: context.text.headlineSmall),
            if (item.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(item.description, style: TextStyle(color: p.inkSubtle)),
              ),
            const SizedBox(height: Space.lg),
            if (item.variants.length > 1) ...[
              Text('Size', style: context.text.titleSmall),
              const SizedBox(height: Space.sm),
              for (final v in item.variants)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Material(
                    color: v == _variant ? p.primaryTint : p.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: Radii.cardR,
                      side: BorderSide(color: v == _variant ? p.primary : p.border, width: v == _variant ? 2 : 1),
                    ),
                    child: InkWell(
                      borderRadius: Radii.cardR,
                      onTap: () => setState(() {
                        _variant = v;
                        _addOns.removeWhere((n) => !_available.any((a) => a.name == n));
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 14),
                        child: Row(
                          children: [
                            Icon(v == _variant ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: v == _variant ? p.primary : p.inkSubtle),
                            const SizedBox(width: Space.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(v.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  if (v.note.isNotEmpty) Text(v.note, style: TextStyle(fontSize: 12, color: p.inkSubtle)),
                                ],
                              ),
                            ),
                            Text('₹${formatPrice(v.price)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            if (_available.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Text('Add-ons', style: context.text.titleSmall),
              for (final a in _available)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _addOns.contains(a.name),
                  onChanged: (sel) => setState(() => sel == true ? _addOns.add(a.name) : _addOns.remove(a.name)),
                  title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  secondary: Text('+₹${formatPrice(a.price)}', style: TextStyle(color: p.primary, fontWeight: FontWeight.w700)),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ],
            const SizedBox(height: Space.lg),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _line),
                child: Text('Add to order  ·  ₹${formatPrice(_line.unitPrice)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
