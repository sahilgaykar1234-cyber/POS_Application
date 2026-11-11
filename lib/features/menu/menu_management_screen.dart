import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';
import '../../core/widgets/confirm_dialog.dart';
import 'menu_models.dart';
import 'menu_repository.dart';

/// Manager's menu editor: categories → subcategories → items (with sizes,
/// add-ons, photo, availability). Everything is stored per cafe in Firestore.
class MenuManagementScreen extends StatefulWidget {
  const MenuManagementScreen({super.key, required this.cafeId, this.readOnly = false, this.menuStream});

  /// Test hook (default: live Firestore).
  final Stream<MenuData>? menuStream;

  final String cafeId;

  /// Super Admin viewing a cafe's menu.
  final bool readOnly;

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  late final MenuRepository _repo = MenuRepository(widget.cafeId);
  late final Stream<MenuData> _menu = widget.menuStream ?? _repo.watchMenu();
  String _search = '';

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _guard(Future<void> Function() action, {String? success}) async {
    try {
      await action();
      if (success != null) _toast(success);
    } on MenuActionBlocked catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast('Could not save. Please check your connection and try again.', error: true);
    }
  }

  // ---------------------------------------------------------------- dialogs

  Future<String?> _askName(String title, {String initial = '', String label = 'Name'}) {
    final ctrl = TextEditingController(text: initial);
    final key = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: key,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return 'Please enter a name';
              if (s.length > 60) return 'Name is too long';
              return null;
            },
            onFieldSubmitted: (_) {
              if (key.currentState!.validate()) Navigator.pop(ctx, ctrl.text.trim());
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(ctx, ctrl.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _addCategory(MenuData menu) async {
    final name = await _askName('New category', label: 'Category name (e.g. Pizza)');
    if (name == null) return;
    if (menu.categories.any((c) => c.name.toLowerCase() == name.toLowerCase())) {
      return _toast('A category with this name already exists.', error: true);
    }
    final maxOrder = menu.categories.fold<int>(0, (m, c) => c.sortOrder > m ? c.sortOrder : m);
    await _guard(() => _repo.saveCategory(name: name, sortOrder: maxOrder + 1), success: 'Category added');
  }

  Future<void> _renameCategory(MenuCategory c) async {
    final name = await _askName('Rename category', initial: c.name);
    if (name == null || name == c.name) return;
    await _guard(() => _repo.saveCategory(id: c.id, name: name, isActive: c.isActive), success: 'Category renamed');
  }

  Future<void> _deleteCategory(MenuCategory c) async {
    final ok = await showDangerConfirmDialog(
      context,
      title: 'Delete "${c.name}"?',
      message: 'The category will be removed from the menu. (Only empty categories can be deleted.)',
      confirmLabel: 'Delete',
    );
    if (ok) await _guard(() => _repo.deleteCategory(c.id), success: 'Category deleted');
  }

  Future<void> _addSubcategory(MenuCategory c, MenuData menu) async {
    final name = await _askName('New subcategory in ${c.name}', label: 'Subcategory name (e.g. Classic)');
    if (name == null) return;
    final subs = menu.subcategoriesOf(c.id);
    if (subs.any((s) => s.name.toLowerCase() == name.toLowerCase())) {
      return _toast('This subcategory already exists.', error: true);
    }
    final maxOrder = subs.fold<int>(0, (m, s) => s.sortOrder > m ? s.sortOrder : m);
    await _guard(() => _repo.saveSubcategory(categoryId: c.id, name: name, sortOrder: maxOrder + 1),
        success: 'Subcategory added');
  }

  Future<void> _renameSubcategory(MenuSubcategory s) async {
    final name = await _askName('Rename subcategory', initial: s.name);
    if (name == null || name == s.name) return;
    await _guard(() => _repo.saveSubcategory(id: s.id, categoryId: s.categoryId, name: name),
        success: 'Subcategory renamed');
  }

  Future<void> _deleteSubcategory(MenuSubcategory s) async {
    final ok = await showDangerConfirmDialog(
      context,
      title: 'Delete "${s.name}"?',
      message: 'The subcategory will be removed. (Only empty subcategories can be deleted.)',
      confirmLabel: 'Delete',
    );
    if (ok) await _guard(() => _repo.deleteSubcategory(s.id), success: 'Subcategory deleted');
  }

  Future<void> _openItemEditor(MenuData menu, {MenuItem? item, String? categoryId, String? subcategoryId}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MenuItemEditorScreen(
          repo: _repo,
          menu: menu,
          item: item,
          initialCategoryId: categoryId,
          initialSubcategoryId: subcategoryId,
        ),
      ),
    );
    if (saved == true) _toast(item == null ? 'Item added' : 'Item updated');
  }

  Future<void> _deleteItem(MenuItem item) async {
    final ok = await showDangerConfirmDialog(
      context,
      title: 'Delete "${item.name}"?',
      message: 'This item will be removed from the menu. Past bills are not affected.\n\n'
          'Tip: to hide it temporarily, switch it to "Unavailable" instead.',
      confirmLabel: 'Delete',
    );
    if (ok) await _guard(() => _repo.deleteItem(item), success: 'Item deleted');
  }

  Future<void> _move<T>(List<T> list, int index, int delta, String Function(T) id, int Function(T) order,
      dynamic Function(String) refOf) async {
    final j = index + delta;
    if (j < 0 || j >= list.length) return;
    await _guard(() => _repo.swapOrder(refOf(id(list[index])), order(list[index]), refOf(id(list[j])), order(list[j])));
  }

  // ---------------------------------------------------------------- build

  String? _selCat; // null = all items
  String? _selSub;
  String _avail = 'all'; // all | available | soldout

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MenuData>(
      stream: _menu,
      builder: (context, snap) {
        if (snap.hasError) return const ErrorState(message: 'Could not load the menu. Please check your connection.');
        if (!snap.hasData) return const LoadingState(label: 'Loading menu…');
        final menu = snap.data!;
        if (_selCat != null && !menu.categories.any((c) => c.id == _selCat)) _selCat = null;
        if (_selSub != null && !menu.subcategories.any((s) => s.id == _selSub)) _selSub = null;

        final wide = MediaQuery.sizeOf(context).width >= 1100;
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: widget.readOnly || wide
              ? null
              : FloatingActionButton(
                  heroTag: 'menu-add-item',
                  tooltip: 'Add item',
                  onPressed: menu.categories.isEmpty ? () => _toast('Add a category first.', error: true) : () => _openItemEditor(menu, categoryId: _selCat, subcategoryId: _selSub),
                  child: const Icon(Icons.add),
                ),
          body: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 290, child: _categoryTree(menu)),
                    VerticalDivider(width: 1, color: context.palette.border),
                    Expanded(child: _itemsPanel(menu, wide: true)),
                  ],
                )
              : _itemsPanel(menu, wide: false),
        );
      },
    );
  }

  List<MenuItem> _visibleItems(MenuData menu) {
    return menu.items.where((i) {
      if (_search.isNotEmpty && !(i.name.toLowerCase().contains(_search) || i.description.toLowerCase().contains(_search))) return false;
      if (_search.isEmpty && _selCat != null && i.categoryId != _selCat) return false;
      if (_search.isEmpty && _selSub != null && i.subcategoryId != _selSub) return false;
      if (_avail == 'available' && !i.isAvailable) return false;
      if (_avail == 'soldout' && i.isAvailable) return false;
      return true;
    }).toList();
  }

  // ------------------------------------------------------------ left tree

  Widget _categoryTree(MenuData menu) {
    final p = context.palette;
    Widget row({required String label, required int count, required bool selected, required VoidCallback onTap, double indent = 0, Widget? menuBtn, bool bold = true}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: selected ? p.primaryTint : Colors.transparent,
          borderRadius: Radii.controlR,
          child: InkWell(
            borderRadius: Radii.controlR,
            onTap: onTap,
            child: SizedBox(
              height: indent > 0 ? 40 : kTouch,
              child: Row(
                children: [
                  SizedBox(width: 12 + indent),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: selected ? FontWeight.w700 : (bold ? FontWeight.w600 : FontWeight.w500),
                          fontSize: indent > 0 ? 13 : 14,
                          color: selected ? p.primaryHover : (bold ? p.ink : p.inkMuted),
                        )),
                  ),
                  Text('$count', style: TextStyle(color: selected ? p.primaryHover : p.inkSubtle, fontSize: 12, fontWeight: FontWeight.w600)),
                  menuBtn ?? const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final children = <Widget>[
      row(label: 'All items', count: menu.items.length, selected: _selCat == null, onTap: () => setState(() {
            _selCat = null;
            _selSub = null;
          })),
      const SizedBox(height: Space.sm),
    ];
    for (var i = 0; i < menu.categories.length; i++) {
      final c = menu.categories[i];
      children.add(row(
        label: c.name,
        count: menu.itemsOf(c.id).length,
        selected: _selCat == c.id && _selSub == null,
        onTap: () => setState(() {
          _selCat = c.id;
          _selSub = null;
        }),
        menuBtn: widget.readOnly ? null : _categoryMenu(menu, c, i),
      ));
      for (final s in menu.subcategoriesOf(c.id)) {
        children.add(row(
          label: s.name,
          count: menu.itemsOf(c.id, subcategoryId: s.id).length,
          selected: _selSub == s.id,
          indent: 16,
          bold: false,
          onTap: () => setState(() {
            _selCat = c.id;
            _selSub = s.id;
          }),
          menuBtn: widget.readOnly ? null : _subcategoryMenu(menu, c, s),
        ));
      }
    }

    return Container(
      color: p.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.sm, Space.sm),
            child: Row(
              children: [
                Expanded(child: Text('Categories', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                if (!widget.readOnly)
                  IconButton(tooltip: 'Add category', icon: const Icon(Icons.create_new_folder_outlined), onPressed: () => _addCategory(menu)),
              ],
            ),
          ),
          Expanded(
            child: menu.categories.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: Text('No categories yet. Add one to start building the menu.', style: TextStyle(color: p.inkSubtle)),
                  )
                : ListView(padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.lg), children: children),
          ),
        ],
      ),
    );
  }

  Widget _categoryMenu(MenuData menu, MenuCategory c, int index) => PopupMenuButton<String>(
        tooltip: 'Category actions',
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (v) {
          switch (v) {
            case 'item':
              _openItemEditor(menu, categoryId: c.id);
            case 'sub':
              _addSubcategory(c, menu);
            case 'rename':
              _renameCategory(c);
            case 'up':
              _move(menu.categories, index, -1, (x) => x.id, (x) => x.sortOrder, _repo.categoryRef);
            case 'down':
              _move(menu.categories, index, 1, (x) => x.id, (x) => x.sortOrder, _repo.categoryRef);
            case 'delete':
              _deleteCategory(c);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'item', child: Text('Add item here')),
          const PopupMenuItem(value: 'sub', child: Text('Add subcategory')),
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          if (index > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
          if (index < menu.categories.length - 1) const PopupMenuItem(value: 'down', child: Text('Move down')),
          PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: context.palette.danger))),
        ],
      );

  Widget _subcategoryMenu(MenuData menu, MenuCategory c, MenuSubcategory s) => PopupMenuButton<String>(
        tooltip: 'Subcategory actions',
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (v) {
          if (v == 'item') _openItemEditor(menu, categoryId: c.id, subcategoryId: s.id);
          if (v == 'rename') _renameSubcategory(s);
          if (v == 'delete') _deleteSubcategory(s);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'item', child: Text('Add item here')),
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: context.palette.danger))),
        ],
      );

  // ------------------------------------------------------------ items panel

  Widget _itemsPanel(MenuData menu, {required bool wide}) {
    final p = context.palette;
    final items = _visibleItems(menu);
    final cat = menu.categories.where((c) => c.id == _selCat).firstOrNull;
    final sub = menu.subcategories.where((s) => s.id == _selSub).firstOrNull;
    final title = _search.isNotEmpty ? 'Search results' : (sub?.name ?? cat?.name ?? 'All items');
    final pad = wide ? Space.xl : Space.lg;

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, 96),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sub != null && cat != null) Text(cat.name, style: TextStyle(color: p.inkSubtle, fontSize: 13)),
                Text(title, style: context.text.headlineSmall),
                Text(
                  '${menu.items.length} items · ${menu.items.where((i) => !i.isAvailable).length} sold out',
                  style: TextStyle(color: p.inkSubtle, fontSize: 13),
                ),
              ],
            ),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SearchField(width: wide ? 260 : null, hint: 'Search items', onChanged: (v) => setState(() => _search = v.trim().toLowerCase())),
                if (!widget.readOnly && !wide)
                  OutlinedButton.icon(onPressed: () => _addCategory(menu), icon: const Icon(Icons.create_new_folder_outlined, size: 18), label: const Text('Category')),
                if (!widget.readOnly && wide)
                  FilledButton.icon(
                    onPressed: menu.categories.isEmpty ? () => _toast('Add a category first.', error: true) : () => _openItemEditor(menu, categoryId: _selCat, subcategoryId: _selSub),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add item'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        if (!wide && menu.categories.isNotEmpty) ...[
          FilterPills<String?>(
            options: [(null, 'All'), for (final c in menu.categories) (c.id, c.name)],
            selected: _selCat,
            onSelected: (v) => setState(() {
              _selCat = v;
              _selSub = null;
            }),
          ),
          if (_selCat != null && menu.subcategoriesOf(_selCat!).isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            FilterPills<String?>(
              options: [(null, 'All'), for (final s in menu.subcategoriesOf(_selCat!)) (s.id, s.name)],
              selected: _selSub,
              onSelected: (v) => setState(() => _selSub = v),
            ),
          ],
          if (!widget.readOnly && _selCat != null) ...[
            const SizedBox(height: Space.sm),
            Row(children: [
              TextButton.icon(
                onPressed: () => _addSubcategory(menu.categories.firstWhere((c) => c.id == _selCat), menu),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Subcategory'),
              ),
              TextButton.icon(
                onPressed: () => _renameCategory(menu.categories.firstWhere((c) => c.id == _selCat)),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Rename'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: p.danger),
                onPressed: () => _deleteCategory(menu.categories.firstWhere((c) => c.id == _selCat)),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
              ),
            ]),
          ],
          const SizedBox(height: Space.sm),
        ],
        FilterPills<String>(
          options: const [('all', 'All'), ('available', 'Available'), ('soldout', 'Sold out')],
          selected: _avail,
          onSelected: (v) => setState(() => _avail = v),
        ),
        const SizedBox(height: Space.lg),
        if (menu.categories.isEmpty)
          EmptyState(
            icon: Icons.restaurant_menu,
            title: 'Your menu is empty',
            message: 'Start by adding a category, e.g. "Pizza" or "Beverages".',
            action: widget.readOnly ? null : FilledButton.icon(onPressed: () => _addCategory(menu), icon: const Icon(Icons.add), label: const Text('Add category')),
          )
        else if (items.isEmpty)
          const EmptyState(icon: Icons.search_off_rounded, title: 'No items here', message: 'Try another category or filter.')
        else
          SurfaceCard(
            child: Column(
              children: [
                if (wide)
                  Container(
                    color: p.surfaceAlt,
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 10),
                    child: Row(children: [
                      Expanded(flex: 5, child: _th('Item')),
                      Expanded(flex: 4, child: _th('Sizes & prices')),
                      Expanded(flex: 3, child: _th('Add-ons')),
                      SizedBox(width: 90, child: _th('Available')),
                      const SizedBox(width: 48),
                    ]),
                  ),
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.border),
                  wide ? _itemRowWide(menu, items, i) : _itemRowCompact(menu, items, i),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _th(String t) => Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.palette.inkSubtle));

  bool _canReorder(MenuItem item) => _search.isEmpty && (_selSub != null || (_selCat != null && item.subcategoryId == null));

  Widget _itemActions(MenuData menu, List<MenuItem> siblings, int index) {
    final item = siblings[index];
    final reorder = _canReorder(item);
    return PopupMenuButton<String>(
      tooltip: 'Item actions',
      onSelected: (v) {
        switch (v) {
          case 'edit':
            _openItemEditor(menu, item: item);
          case 'up':
            _move(siblings, index, -1, (x) => x.id, (x) => x.sortOrder, _repo.itemRef);
          case 'down':
            _move(siblings, index, 1, (x) => x.id, (x) => x.sortOrder, _repo.itemRef);
          case 'delete':
            _deleteItem(item);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (reorder && index > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
        if (reorder && index < siblings.length - 1) const PopupMenuItem(value: 'down', child: Text('Move down')),
        PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: context.palette.danger))),
      ],
    );
  }

  Widget _availabilitySwitch(MenuItem item) => Switch(
        value: item.isAvailable,
        onChanged: widget.readOnly ? null : (v) => _guard(() => _repo.setAvailability(item.id, v)),
      );

  Widget _priceChips(MenuItem item) {
    final p = context.palette;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final v in item.variants)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(6)),
            child: Text(item.variants.length == 1 && v.label == 'Standard' ? '₹${formatPrice(v.price)}' : '${v.label} ₹${formatPrice(v.price)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _nameCell(MenuItem item) {
    final p = context.palette;
    return Row(
      children: [
        _ItemThumb(url: item.imageUrl, name: item.name),
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
                      style: TextStyle(fontWeight: FontWeight.w600, color: item.isAvailable ? p.ink : p.inkSubtle)),
                ),
                if (item.isJain) _Badge('J', p.info, p.infoTint),
                if (item.spicyLevel > 0)
                  for (var i = 0; i < item.spicyLevel; i++) Icon(Icons.local_fire_department_rounded, size: 14, color: p.danger),
                if (!item.isAvailable) ...[const SizedBox(width: 6), const StatusChip('Sold out')],
              ]),
              if (item.description.isNotEmpty)
                Text(item.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.inkSubtle)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _itemRowWide(MenuData menu, List<MenuItem> siblings, int index) {
    final item = siblings[index];
    final p = context.palette;
    return InkWell(
      onTap: widget.readOnly ? null : () => _openItemEditor(menu, item: item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 10),
        child: Row(
          children: [
            Expanded(flex: 5, child: _nameCell(item)),
            Expanded(flex: 4, child: Padding(padding: const EdgeInsets.only(right: Space.sm), child: _priceChips(item))),
            Expanded(
              flex: 3,
              child: Text(
                item.addOns.isEmpty ? '—' : item.addOns.map((a) => '${a.name} +₹${formatPrice(a.price)}').join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.inkMuted),
              ),
            ),
            SizedBox(width: 90, child: Align(alignment: Alignment.centerLeft, child: _availabilitySwitch(item))),
            SizedBox(width: 48, child: widget.readOnly ? null : _itemActions(menu, siblings, index)),
          ],
        ),
      ),
    );
  }

  Widget _itemRowCompact(MenuData menu, List<MenuItem> siblings, int index) {
    final item = siblings[index];
    return InkWell(
      onTap: widget.readOnly ? null : () => _openItemEditor(menu, item: item),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, 0, Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: _nameCell(item)),
              _availabilitySwitch(item),
              if (!widget.readOnly) _itemActions(menu, siblings, index),
            ]),
            Padding(padding: const EdgeInsets.only(left: 56, top: 6, right: Space.md), child: _priceChips(item)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color, this.tint);
  final String text;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}

class _ItemThumb extends StatelessWidget {
  const _ItemThumb({this.url, required this.name});
  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ph = Container(
      color: p.primaryTint,
      alignment: Alignment.center,
      child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: TextStyle(color: p.primary.withValues(alpha: 0.6), fontWeight: FontWeight.w800)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: url == null ? ph : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => ph),
      ),
    );
  }
}

// =============================================================================
// Item editor
// =============================================================================

class MenuItemEditorScreen extends StatefulWidget {
  const MenuItemEditorScreen({
    super.key,
    required this.repo,
    required this.menu,
    this.item,
    this.initialCategoryId,
    this.initialSubcategoryId,
  });

  final MenuRepository repo;
  final MenuData menu;
  final MenuItem? item;
  final String? initialCategoryId;
  final String? initialSubcategoryId;

  @override
  State<MenuItemEditorScreen> createState() => _MenuItemEditorScreenState();
}

class _VariantRow {
  _VariantRow([MenuVariant? v])
      : label = TextEditingController(text: v?.label ?? ''),
        price = TextEditingController(text: v == null ? '' : formatPrice(v.price)),
        note = TextEditingController(text: v?.note ?? '');
  final TextEditingController label, price, note;
  void dispose() {
    label.dispose();
    price.dispose();
    note.dispose();
  }
}

class _AddOnRow {
  _AddOnRow([MenuAddOn? a])
      : name = TextEditingController(text: a?.name ?? ''),
        price = TextEditingController(text: a == null ? '' : formatPrice(a.price)),
        variantLabels = {...?a?.variantLabels};
  final TextEditingController name, price;
  final Set<String> variantLabels;
  void dispose() {
    name.dispose();
    price.dispose();
  }
}

class _MenuItemEditorScreenState extends State<MenuItemEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.item?.name ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.item?.description ?? '');
  late String? _categoryId = widget.item?.categoryId ?? widget.initialCategoryId ?? widget.menu.categories.firstOrNull?.id;
  late String? _subcategoryId = widget.item?.subcategoryId ?? widget.initialSubcategoryId;
  late bool _available = widget.item?.isAvailable ?? true;
  late bool _jain = widget.item?.isJain ?? false;
  late int _spicy = widget.item?.spicyLevel ?? 0;
  late String? _imageUrl = widget.item?.imageUrl;
  PlatformFile? _newImage;
  late final List<_VariantRow> _variants = (widget.item?.variants.isNotEmpty ?? false)
      ? widget.item!.variants.map(_VariantRow.new).toList()
      : [_VariantRow(const MenuVariant(label: 'Standard', price: 0))..price.text = ''];
  late final List<_AddOnRow> _addOns = widget.item?.addOns.map(_AddOnRow.new).toList() ?? [];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    for (final a in _addOns) {
      a.dispose();
    }
    super.dispose();
  }

  List<MenuSubcategory> get _subs => _categoryId == null ? const [] : widget.menu.subcategoriesOf(_categoryId!);

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = res?.files.single;
    if (f == null || f.bytes == null) return;
    if (f.size > 2 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please choose a photo under 2 MB.')),
        );
      }
      return;
    }
    setState(() => _newImage = f);
  }

  String _contentType(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final labels = _variants.map((v) => v.label.text.trim().toLowerCase()).toList();
    if (labels.toSet().length != labels.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Each size/variant needs a different name.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final variants = _variants
          .map((v) => MenuVariant(
                label: v.label.text.trim(),
                price: double.parse(v.price.text.trim()),
                note: v.note.text.trim(),
              ))
          .toList();
      final validLabels = variants.map((v) => v.label).toSet();
      final addOns = _addOns
          .map((a) => MenuAddOn(
                name: a.name.text.trim(),
                price: double.parse(a.price.text.trim()),
                variantLabels: a.variantLabels.where(validLabels.contains).toList(),
              ))
          .toList();

      final isNew = widget.item == null;
      final subValid = _subs.any((s) => s.id == _subcategoryId);
      var item = MenuItem(
        id: widget.item?.id ?? '',
        categoryId: _categoryId!,
        subcategoryId: subValid ? _subcategoryId : null,
        name: _name.text.trim(),
        description: _desc.text.trim(),
        imageUrl: _imageUrl,
        isAvailable: _available,
        isJain: _jain,
        spicyLevel: _spicy,
        sortOrder: widget.item?.sortOrder ??
            widget.menu.items.where((i) => i.categoryId == _categoryId).fold<int>(0, (m, i) => i.sortOrder > m ? i.sortOrder : m) + 1,
        variants: variants,
        addOns: addOns,
      );

      final id = await widget.repo.saveItem(item, isNew: isNew);
      if (_newImage != null) {
        final url = await widget.repo.uploadItemImage(id, _newImage!.bytes!, _contentType(_newImage!.name));
        await widget.repo.itemRef(id).update({'imageUrl': url});
      } else if (!isNew && _imageUrl == null && widget.item?.imageUrl != null) {
        await widget.repo.itemRef(id).update({'imageUrl': null});
      }
      if (mounted) Navigator.pop(context, true);
    } on MenuActionBlocked catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Could not save the item. Please check your connection and try again.');
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _priceValidator(String? v) {
    final p = double.tryParse((v ?? '').trim());
    if (p == null) return 'Enter a price';
    if (p < 0 || p > 100000) return 'Invalid price';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final variantLabels = _variants.map((v) => v.label.text.trim()).where((s) => s.isNotEmpty).toList();

    return Scaffold(
      backgroundColor: context.palette.canvas,
      appBar: AppBar(
        title: Text(widget.item == null ? 'Add item' : 'Edit item'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, size: 18),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _imagePicker(),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(labelText: 'Item name *', border: OutlineInputBorder()),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return 'Please enter the item name';
                              if (s.length > 80) return 'Name is too long';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _desc,
                            maxLines: 2,
                            maxLength: 300,
                            decoration: const InputDecoration(
                              labelText: 'Description / ingredients',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _categoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Category *', border: OutlineInputBorder()),
                        items: [
                          for (final c in widget.menu.categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                        ],
                        validator: (v) => v == null ? 'Choose a category' : null,
                        onChanged: (v) => setState(() {
                          _categoryId = v;
                          _subcategoryId = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey('sub-$_categoryId'),
                        initialValue: _subs.any((s) => s.id == _subcategoryId) ? _subcategoryId : null,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Subcategory', border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
                          for (final s in _subs) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                        ],
                        onChanged: _subs.isEmpty ? null : (v) => setState(() => _subcategoryId = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _sectionTitle('Sizes & prices',
                    'One row = one price. Use a single "Standard" row for items with one price.'),
                for (var i = 0; i < _variants.length; i++) _variantRow(i),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add size'),
                    onPressed: _variants.length >= 6 ? null : () => setState(() => _variants.add(_VariantRow())),
                  ),
                ),
                const SizedBox(height: 12),
                _sectionTitle('Add-ons (optional)', 'Extras charged on top, e.g. "Cheese burst" +₹120.'),
                for (var i = 0; i < _addOns.length; i++) _addOnRow(i, variantLabels),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add add-on'),
                    onPressed: _addOns.length >= 10 ? null : () => setState(() => _addOns.add(_AddOnRow())),
                  ),
                ),
                const SizedBox(height: 12),
                _sectionTitle('Details', null),
                SwitchListTile(
                  value: _available,
                  onChanged: (v) => setState(() => _available = v),
                  title: const Text('Available for ordering'),
                  subtitle: const Text('Turn off when sold out — the item stays in the menu.'),
                ),
                SwitchListTile(
                  value: _jain,
                  onChanged: (v) => setState(() => _jain = v),
                  title: const Text('Jain option (J)'),
                ),
                ListTile(
                  title: const Text('Spicy level'),
                  trailing: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('None')),
                      ButtonSegment(value: 1, label: Text('🌶')),
                      ButtonSegment(value: 2, label: Text('🌶🌶')),
                    ],
                    selected: {_spicy},
                    onSelectionChanged: (s) => setState(() => _spicy = s.first),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String? hint) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: context.palette.ink, fontSize: 15)),
            if (hint != null) Text(hint, style: TextStyle(color: context.palette.inkSubtle, fontSize: 12)),
          ],
        ),
      );

  Widget _variantRow(int i) {
    final v = _variants[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: v.label,
              decoration: const InputDecoration(labelText: 'Size name', hintText: 'e.g. 10 inch', border: OutlineInputBorder(), isDense: true),
              validator: (s) => (s ?? '').trim().isEmpty ? 'Required' : null,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: v.price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Price ₹', border: OutlineInputBorder(), isDense: true),
              validator: _priceValidator,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: v.note,
              decoration: const InputDecoration(labelText: 'Note', hintText: '6 pcs', border: OutlineInputBorder(), isDense: true),
            ),
          ),
          IconButton(
            tooltip: 'Remove size',
            icon: Icon(Icons.remove_circle_outline, color: context.palette.danger),
            onPressed: _variants.length <= 1
                ? null
                : () => setState(() {
                      _variants.removeAt(i).dispose();
                    }),
          ),
        ],
      ),
    );
  }

  Widget _addOnRow(int i, List<String> variantLabels) {
    final a = _addOns[i];
    return Card(
      color: context.palette.surfaceAlt,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: a.name,
                    decoration: const InputDecoration(labelText: 'Add-on name', border: OutlineInputBorder(), isDense: true),
                    validator: (s) => (s ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: a.price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Extra ₹', border: OutlineInputBorder(), isDense: true),
                    validator: _priceValidator,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove add-on',
                  icon: Icon(Icons.delete_outline, color: context.palette.danger),
                  onPressed: () => setState(() => _addOns.removeAt(i).dispose()),
                ),
              ],
            ),
            if (variantLabels.length > 1) ...[
              const SizedBox(height: 6),
              Text('Available on (none selected = all sizes):', style: TextStyle(color: context.palette.inkSubtle, fontSize: 12)),
              Wrap(
                spacing: 6,
                children: [
                  for (final l in variantLabels)
                    FilterChip(
                      label: Text(l),
                      selected: a.variantLabels.contains(l),
                      onSelected: (sel) => setState(() => sel ? a.variantLabels.add(l) : a.variantLabels.remove(l)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _imagePicker() {
    final hasImage = _newImage != null || _imageUrl != null;
    return Column(
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 110,
              height: 110,
              color: context.palette.surfaceAlt,
              child: _newImage != null
                  ? Image.memory(_newImage!.bytes!, fit: BoxFit.cover)
                  : _imageUrl != null
                      ? Image.network(_imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_outlined, color: context.palette.inkSubtle),
                            const SizedBox(height: 4),
                            Text('Add photo', style: TextStyle(color: context.palette.inkSubtle, fontSize: 12)),
                          ],
                        ),
            ),
          ),
        ),
        if (hasImage)
          TextButton(
            onPressed: () => setState(() {
              _newImage = null;
              _imageUrl = null;
            }),
            child: Text('Remove photo', style: TextStyle(color: context.palette.danger, fontSize: 12)),
          ),
      ],
    );
  }
}
