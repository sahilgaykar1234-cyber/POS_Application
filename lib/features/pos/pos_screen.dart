import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_service.dart';
import '../../core/data/firestore_paths.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/ui.dart';
import '../menu/item_picker_sheet.dart';
import '../menu/menu_models.dart';
import '../menu/menu_repository.dart';
import '../orders/order_model.dart';
import '../orders/order_service.dart';
import '../settings/business_settings.dart';
import 'pos_cart.dart';
import 'print_helper.dart';

/// Take a new order or edit an existing one (Manager and Captain).
///
/// Wide screens: categories | items | cart side by side.
/// Phones: item list with a sticky "View order" bar opening the cart.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key, this.editing, this.prefilledTable, this.standalone = false, this.onDone, this.menuStream, this.settingsStream});

  /// Test hooks (default: live Firestore).
  final Stream<MenuData>? menuStream;
  final Stream<BusinessSettings>? settingsStream;

  final PosOrder? editing;
  final String? prefilledTable;

  /// Opened as its own page (has an app bar and pops when done).
  final bool standalone;

  /// Called after an order is placed/updated (embedded use).
  final VoidCallback? onDone;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final cart = PosCart();
  final _table = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  final _search = TextEditingController();
  String _query = '';
  String? _categoryId;
  String? _subcategoryId;
  KnownCustomer? _known;
  bool _lookingUp = false;
  bool _saving = false;

  late final Stream<MenuData> _menu = widget.menuStream ?? MenuRepository(FirestorePaths.activeCafeId).watchMenu();
  late final Stream<BusinessSettings> _settings = widget.settingsStream ?? BusinessSettingsRepository.instance.watch();
  BusinessSettings _bs = BusinessSettings.empty;
  StreamSubscription<BusinessSettings>? _bsSub;

  @override
  void initState() {
    super.initState();
    _bsSub = _settings.listen((s) {
      if (!mounted) return;
      setState(() {
        final first = identical(_bs, BusinessSettings.empty);
        _bs = s;
        if (first && widget.editing == null) cart.orderType = s.defaultOrderType;
      });
    });
    final e = widget.editing;
    if (e != null) {
      cart.loadFrom(e);
      final rawTable = e.tableNo;
      final rawName = e.customerName;
      final clean = rawName.replaceAll(r'$1', '').replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '').trim();
      _table.text = rawTable.isNotEmpty ? rawTable : (rawName.toLowerCase().startsWith('table') ? rawName : '');
      _name.text = clean.toLowerCase().startsWith('table') ? '' : clean;
      _phone.text = e.customerPhone;
      _note.text = e.specialRequest;
    } else if (widget.prefilledTable != null) {
      _table.text = int.tryParse(widget.prefilledTable!) != null ? 'Table ${widget.prefilledTable}' : widget.prefilledTable!;
    }
    cart.addListener(_onCart);
  }

  void _onCart() => setState(() {});

  @override
  void dispose() {
    _bsSub?.cancel();
    cart.removeListener(_onCart);
    for (final c in [_table, _name, _phone, _note, _search]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- actions

  Future<void> _tapItem(MenuItem item) async {
    if (item.variants.isEmpty || !item.isAvailable) return;
    final line = item.hasChoices ? await showItemPickerSheet(context, item) : CartLine.build(item, item.variants.first, const []);
    if (line == null || !mounted) return;
    HapticFeedback.selectionClick();
    cart.add(line);
  }

  Future<void> _lookup(String v) async {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      if (_known != null) {
        setState(() => _known = null);
        cart.touch();
      }
      return;
    }
    setState(() => _lookingUp = true);
    cart.touch();
    try {
      final k = await OrderService.instance.lookupByPhone(digits);
      if (!mounted) return;
      setState(() {
        _known = k;
        if (k != null && _name.text.trim().isEmpty) _name.text = k.name;
      });
      cart.touch();
    } catch (_) {
      // Lookup is a convenience only.
    } finally {
      if (mounted) {
        setState(() => _lookingUp = false);
        cart.touch();
      }
    }
  }

  Map<String, dynamic> _draft() {
    final b = cart.bill(gstEnabled: _bs.showGst, gstPercent: _bs.gstPercent);
    return {
      'customerName': _name.text.trim().isEmpty ? 'Walk-in Guest' : _name.text.trim(),
      'customerPhone': _phone.text.trim(),
      'tableNo': _table.text.trim(),
      'items': cart.lines.map((e) => Map<String, dynamic>.from(e)).toList(),
      'subtotal': b.subtotal,
      'totalPrice': b.total,
      'hasGst': _bs.showGst,
      'gstPercentage': _bs.gstPercent,
      'paymentStatus': widget.editing?.paymentStatus ?? 'pending',
    };
  }

  Future<void> _printDraft() async {
    if (cart.isEmpty) return showError(context, 'Add at least one item to print the bill.');
    await printBill(context, order: _draft(), settings: _bs.receiptSettings, orderId: widget.editing?.id);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (cart.isEmpty) return showError(context, 'Add at least one item.');
    setState(() => _saving = true);
    cart.touch();
    try {
      await OrderService.instance.saveOrder(
        existing: widget.editing,
        tableNo: _table.text,
        rawName: _name.text,
        rawPhone: _phone.text,
        orderType: cart.orderType,
        note: _note.text,
        cart: cart.lines,
        gstEnabled: _bs.showGst,
        gstPercent: _bs.gstPercent,
        createdByRole: AuthService.instance.currentUser?.role?.claim,
      );
      if (!mounted) return;
      final msg = widget.editing == null ? 'Order sent to kitchen' : 'Order updated';
      if (widget.standalone) {
        Navigator.pop(context, true);
        showSuccess(context, msg);
        return;
      }
      if (_sheetOpen) Navigator.of(context).pop();
      showSuccess(context, msg);
      setState(() {
        cart.clear(orderType: _bs.defaultOrderType);
        for (final c in [_table, _name, _phone, _note]) {
          c.clear();
        }
        _known = null;
      });
      widget.onDone?.call();
    } catch (e) {
      if (mounted) showError(context, 'Could not save the order. Please check your connection.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        cart.touch();
      }
    }
  }

  Future<void> _confirmClear() async {
    if (cart.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear the cart?'),
        content: const Text('All items in this order will be removed.'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) cart.clear();
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final body = StreamBuilder<MenuData>(
      stream: _menu,
      builder: (context, snap) {
        if (snap.hasError) return const ErrorState(message: 'Could not load the menu.');
        if (!snap.hasData) return const LoadingState(label: 'Loading menu…');
        final menu = snap.data!;
        return LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= 900) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c.maxWidth >= 1180) _CategoryRail(menu: menu, selected: _categoryId, onSelect: _selectCategory),
                Expanded(child: _menuArea(menu, wide: true, showCategoryPills: c.maxWidth < 1180)),
                SizedBox(width: c.maxWidth >= 1180 ? 400 : 360, child: _cartPanel()),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: _menuArea(menu, wide: false, showCategoryPills: true)),
              _MobileCartBar(cart: cart, total: cart.bill(gstEnabled: _bs.showGst, gstPercent: _bs.gstPercent).total, onOpen: _openCartSheet),
            ],
          );
        });
      },
    );

    if (!widget.standalone) return body;
    return Scaffold(
      appBar: AppBar(title: Text(widget.editing == null ? 'New order' : 'Edit ${widget.editing!.displayName}')),
      body: body,
    );
  }

  void _selectCategory(String? id) => setState(() {
        _categoryId = id;
        _subcategoryId = null;
      });

  bool _sheetOpen = false;

  Future<void> _openCartSheet() async {
    _sheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => ListenableBuilder(
        listenable: cart,
        builder: (ctx, _) => SizedBox(height: MediaQuery.sizeOf(ctx).height * 0.92, child: _cartPanel(inSheet: true)),
      ),
    );
    _sheetOpen = false;
  }

  // ------------------------------------------------------------ menu area

  Widget _menuArea(MenuData menu, {required bool wide, required bool showCategoryPills}) {
    final p = context.palette;
    final pad = context.isMobile ? Space.lg : Space.xl;
    final subs = _categoryId == null ? const <MenuSubcategory>[] : menu.subcategoriesOf(_categoryId!);

    final items = menu.items.where((i) {
      if (_query.isNotEmpty) {
        return i.name.toLowerCase().contains(_query) || i.description.toLowerCase().contains(_query);
      }
      if (_categoryId != null && i.categoryId != _categoryId) return false;
      if (_subcategoryId != null && i.subcategoryId != _subcategoryId) return false;
      return true;
    }).toList();

    // Group by category (and subcategory) for headings when browsing "All".
    final groups = <(String, List<MenuItem>)>[];
    if (_query.isEmpty && _subcategoryId == null) {
      for (final cat in menu.categories) {
        if (_categoryId != null && cat.id != _categoryId) continue;
        final direct = menu.itemsOf(cat.id, directOnly: true);
        if (direct.isNotEmpty) groups.add((_categoryId == null ? cat.name : '', direct));
        for (final s in menu.subcategoriesOf(cat.id)) {
          final si = menu.itemsOf(cat.id, subcategoryId: s.id);
          if (si.isNotEmpty) groups.add((_categoryId == null ? '${cat.name} · ${s.name}' : s.name, si));
        }
      }
    } else {
      groups.add(('', items));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: p.surface,
          padding: EdgeInsets.fromLTRB(pad, Space.md, pad, Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SearchField(
                controller: _search,
                hint: 'Search menu',
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
              if (showCategoryPills && _query.isEmpty) ...[
                const SizedBox(height: Space.md),
                FilterPills<String?>(
                  options: [(null, 'All'), for (final c in menu.categories) (c.id, c.name)],
                  selected: _categoryId,
                  onSelected: _selectCategory,
                ),
              ],
              if (subs.isNotEmpty && _query.isEmpty) ...[
                const SizedBox(height: Space.sm),
                FilterPills<String?>(
                  options: [(null, 'All'), for (final s in subs) (s.id, s.name)],
                  selected: _subcategoryId,
                  onSelected: (v) => setState(() => _subcategoryId = v),
                ),
              ],
            ],
          ),
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: menu.items.isEmpty
              ? const EmptyState(icon: Icons.restaurant_menu, title: 'Menu is empty', message: 'Add items from the Menu section.')
              : items.isEmpty
                  ? const EmptyState(icon: Icons.search_off_rounded, title: 'No items found')
                  : ListView(
                      padding: EdgeInsets.fromLTRB(pad, Space.lg, pad, Space.xxl),
                      children: [
                        for (final (title, list) in groups) ...[
                          if (title.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.sm, top: Space.xs),
                              child: Text(title.toUpperCase(),
                                  style: context.text.labelMedium?.copyWith(color: p.inkSubtle, letterSpacing: 0.6)),
                            ),
                          if (wide)
                            ResponsiveGrid(
                              minTileWidth: 168,
                              spacing: Space.md,
                              children: [for (final i in list) _ItemCard(item: i, qty: cart.qtyOfItem(i.name), onTap: () => _tapItem(i))],
                            )
                          else
                            for (final i in list)
                              Padding(
                                padding: const EdgeInsets.only(bottom: Space.sm),
                                child: _ItemRow(item: i, cart: cart, onAdd: () => _tapItem(i)),
                              ),
                          const SizedBox(height: Space.lg),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ cart panel

  Widget _cartPanel({bool inSheet = false}) {
    final p = context.palette;
    final b = cart.bill(gstEnabled: _bs.showGst, gstPercent: _bs.gstPercent);
    final editing = widget.editing;

    return Material(
      color: p.surface,
      child: Container(
        decoration: inSheet ? null : BoxDecoration(border: Border(left: BorderSide(color: p.border))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.md),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(editing == null ? 'Current order' : 'Editing ${editing.billNo}', style: context.text.titleLarge),
                      ),
                      if (!cart.isEmpty)
                        TextButton(
                          onPressed: _confirmClear,
                          style: TextButton.styleFrom(foregroundColor: p.danger),
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Dine-In', label: Text('Dine-in'), icon: Icon(Icons.table_restaurant_outlined, size: 18)),
                      ButtonSegment(value: 'Takeaway', label: Text('Takeaway'), icon: Icon(Icons.shopping_bag_outlined, size: 18)),
                    ],
                    selected: {cart.orderType == 'Takeaway' ? 'Takeaway' : 'Dine-In'},
                    onSelectionChanged: (s) => cart.setOrderType(s.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: Space.md),
                  TextField(
                    controller: _table,
                    decoration: const InputDecoration(labelText: 'Table / counter', prefixIcon: Icon(Icons.table_restaurant_outlined, size: 20)),
                  ),
                  const SizedBox(height: Space.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                          onChanged: _lookup,
                          decoration: InputDecoration(
                            labelText: 'Mobile',
                            prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                            suffixIcon: _lookingUp
                                ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Customer name'),
                        ),
                      ),
                    ],
                  ),
                  if (_known != null) ...[
                    const SizedBox(height: Space.sm),
                    Container(
                      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.xs, Space.sm),
                      decoration: BoxDecoration(color: p.successTint, borderRadius: Radii.controlR),
                      child: Row(
                        children: [
                          Icon(Icons.verified_rounded, size: 18, color: p.success),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: Text(
                              'Welcome back, ${_known!.name}${_known!.lastVisit != null ? ' · last visit ${Fmt.date(_known!.lastVisit)}' : ''}',
                              style: TextStyle(color: p.success, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                          if (_known!.lastItems.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                cart.addAll(_known!.lastItems);
                                showSuccess(context, 'Previous items added');
                              },
                              child: const Text('Repeat'),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.lg),
                  if (cart.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: Space.xxl),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Icon(Icons.shopping_cart_outlined, size: 36, color: p.borderStrong),
                          const SizedBox(height: Space.sm),
                          Text('No items yet', style: TextStyle(color: p.inkSubtle, fontWeight: FontWeight.w600)),
                          Text('Tap a menu item to add it', style: TextStyle(color: p.inkSubtle, fontSize: 12)),
                        ],
                      ),
                    )
                  else
                    for (var i = 0; i < cart.lines.length; i++) _cartLine(i),
                  const SizedBox(height: Space.md),
                  TextField(
                    controller: _note,
                    maxLines: 2,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Kitchen note (optional)',
                      hintText: 'e.g. less spicy, Jain, no onion',
                      prefixIcon: Icon(Icons.sticky_note_2_outlined, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(color: p.surfaceAlt, border: Border(top: BorderSide(color: p.border))),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _totalRow('Subtotal', Fmt.money(b.subtotal)),
                    if (b.gstEnabled) _totalRow('GST ${formatPrice(b.gstPercent)}%', '₹${b.gst.toStringAsFixed(2)}'),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Total', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        MoneyText(b.total, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: Space.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: cart.isEmpty ? null : _printDraft,
                            icon: const Icon(Icons.print_outlined, size: 18),
                            label: const Text('Print bill'),
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: cart.isEmpty || _saving ? null : _save,
                              child: _saving
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                  : Text(editing == null ? 'Send to kitchen' : 'Update order', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Text(label, style: TextStyle(color: context.palette.inkMuted)),
            const Spacer(),
            Text(value, style: TextStyle(color: context.palette.inkMuted, fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      );

  Widget _cartLine(int i) {
    final p = context.palette;
    final l = cart.lines[i];
    final qty = ((l['qty'] ?? 1) as num).toInt();
    final price = ((l['price'] ?? 0) as num).toDouble();
    final size = (l['size'] ?? 'Standard').toString();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  [if (size != 'Standard') size, '₹${formatPrice(price)} each', if (l['isDone'] == true) 'sent'].join(' · '),
                  style: TextStyle(fontSize: 12, color: p.inkSubtle),
                ),
              ],
            ),
          ),
          QuantityStepper(qty: qty, onChanged: (q) => cart.setQty(i, q)),
          SizedBox(
            width: 72,
            child: Text(Fmt.money(price * qty),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ],
      ),
    );
  }
}

// ============================================================================

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.menu, required this.selected, required this.onSelect});
  final MenuData menu;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget tile(String? id, String label, int count) {
      final sel = id == selected;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: sel ? p.primaryTint : Colors.transparent,
          borderRadius: Radii.controlR,
          child: InkWell(
            borderRadius: Radii.controlR,
            onTap: () => onSelect(id),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? p.primaryHover : p.inkMuted)),
                  ),
                  Text('$count', style: TextStyle(color: sel ? p.primaryHover : p.inkSubtle, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 200,
      decoration: BoxDecoration(color: p.surface, border: Border(right: BorderSide(color: p.border))),
      child: ListView(
        padding: const EdgeInsets.all(Space.md),
        children: [
          tile(null, 'All items', menu.items.length),
          for (final c in menu.categories) tile(c.id, c.name, menu.itemsOf(c.id).length),
        ],
      ),
    );
  }
}

/// Grid card (tablet/desktop).
class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.qty, required this.onTap});
  final MenuItem item;
  final int qty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final off = !item.isAvailable;
    return Material(
      color: off ? p.surfaceAlt : p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.cardR,
        side: BorderSide(color: qty > 0 ? p.primary : p.border, width: qty > 0 ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: off ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 92,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ItemImage(item: item),
                  if (off)
                    Container(
                      color: p.surface.withValues(alpha: 0.7),
                      alignment: Alignment.center,
                      child: const StatusChip('Sold out'),
                    ),
                  if (qty > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 26),
                        height: 26,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(Radii.pill)),
                        alignment: Alignment.center,
                        child: Text('$qty', style: TextStyle(color: p.onPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, 10, Space.md, Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: off ? p.inkSubtle : p.ink)),
                      ),
                      _Flags(item: item),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_priceLine(item), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.inkSubtle)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// List row (phones) with a direct stepper for single-size items.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.cart, required this.onAdd});
  final MenuItem item;
  final PosCart cart;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final off = !item.isAvailable;
    final simpleIdx = item.hasChoices ? -1 : cart.indexOfSimple(item);
    final qty = cart.qtyOfItem(item.name);

    Widget action;
    if (off) {
      action = const StatusChip('Sold out');
    } else if (simpleIdx >= 0) {
      action = QuantityStepper(
        qty: ((cart.lines[simpleIdx]['qty'] ?? 1) as num).toInt(),
        filled: true,
        onChanged: (q) => cart.setQty(simpleIdx, q),
      );
    } else {
      action = SizedBox(
        height: kTouch,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: p.primaryHover,
            backgroundColor: p.primaryTint,
            side: BorderSide(color: p.primary),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onPressed: onAdd,
          child: Text(qty > 0 ? 'Add · $qty' : 'Add'),
        ),
      );
    }

    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: Radii.cardR, side: BorderSide(color: qty > 0 ? p.primary : p.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: off ? null : onAdd,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 60, height: 60, child: _ItemImage(item: item))),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: off ? p.inkSubtle : p.ink)),
                      ),
                      _Flags(item: item),
                    ]),
                    if (item.description.isNotEmpty)
                      Text(item.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.inkSubtle)),
                    const SizedBox(height: 2),
                    Text(item.priceSummary, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              action,
            ],
          ),
        ),
      ),
    );
  }
}

String _priceLine(MenuItem i) {
  if (i.variants.length <= 1) return i.priceSummary;
  return i.variants.map((v) => '${v.label} ₹${formatPrice(v.price)}').join(' · ');
}

class _ItemImage extends StatelessWidget {
  const _ItemImage({required this.item});
  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final placeholder = Container(
      color: p.primaryTint,
      alignment: Alignment.center,
      child: Text(
        item.name.isEmpty ? '?' : item.name.characters.first.toUpperCase(),
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.primary.withValues(alpha: 0.55)),
      ),
    );
    if (item.imageUrl == null) return placeholder;
    return Image.network(item.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);
  }
}

class _Flags extends StatelessWidget {
  const _Flags({required this.item});
  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.isJain)
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: p.infoTint, borderRadius: BorderRadius.circular(4)),
            child: Text('J', style: TextStyle(color: p.info, fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        if (item.spicyLevel > 0)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (var i = 0; i < item.spicyLevel; i++) Icon(Icons.local_fire_department_rounded, size: 14, color: p.danger)],
            ),
          ),
      ],
    );
  }
}

class _MobileCartBar extends StatelessWidget {
  const _MobileCartBar({required this.cart, required this.total, required this.onOpen});
  final PosCart cart;
  final double total;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: onOpen,
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: Radii.cardR), padding: const EdgeInsets.symmetric(horizontal: Space.lg)),
            child: Row(
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 28),
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(color: p.onPrimary, borderRadius: BorderRadius.circular(Radii.pill)),
                  alignment: Alignment.center,
                  child: Text('${cart.itemCount}', style: TextStyle(color: p.primary, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: Space.md),
                Expanded(child: Text(cart.isEmpty ? 'Order details' : 'View order', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                MoneyText(total, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
