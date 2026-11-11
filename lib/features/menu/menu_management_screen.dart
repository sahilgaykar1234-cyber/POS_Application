import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/confirm_dialog.dart';
import 'menu_models.dart';
import 'menu_repository.dart';

/// Manager's menu editor: categories → subcategories → items (with sizes,
/// add-ons, photo, availability). Everything is stored per cafe in Firestore.
class MenuManagementScreen extends StatefulWidget {
  const MenuManagementScreen({super.key, required this.cafeId, this.readOnly = false});

  final String cafeId;

  /// Super Admin viewing a cafe's menu.
  final bool readOnly;

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  late final MenuRepository _repo = MenuRepository(widget.cafeId);
  late final Stream<MenuData> _menu = _repo.watchMenu();
  String _search = '';

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? AppColors.danger : AppColors.success),
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
        backgroundColor: AppColors.surface,
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MenuData>(
      stream: _menu,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(
            child: Text('Could not load the menu. Please check your connection.', style: TextStyle(color: Colors.white60)),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        final menu = snap.data!;

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: widget.readOnly
              ? null
              : FloatingActionButton.extended(
                  heroTag: 'menu-add-item',
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add),
                  label: const Text('Add item', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: menu.categories.isEmpty
                      ? () => _toast('Add a category first.', error: true)
                      : () => _openItemEditor(menu),
                ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search items…',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                    ),
                  ),
                  if (!widget.readOnly) ...[
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                      label: const Text('Category'),
                      onPressed: () => _addCategory(menu),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${menu.categories.length} categories · ${menu.items.length} items · '
                '${menu.items.where((i) => !i.isAvailable).length} unavailable',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 10),
              if (menu.categories.isEmpty)
                const _EmptyMenu()
              else
                for (var i = 0; i < menu.categories.length; i++) _buildCategory(menu, i),
            ],
          ),
        );
      },
    );
  }

  bool _matches(MenuItem i) =>
      _search.isEmpty || i.name.toLowerCase().contains(_search) || i.description.toLowerCase().contains(_search);

  Widget _buildCategory(MenuData menu, int index) {
    final c = menu.categories[index];
    final direct = menu.itemsOf(c.id, directOnly: true).where(_matches).toList();
    final subs = menu.subcategoriesOf(c.id);
    final total = menu.itemsOf(c.id).length;
    final visible = direct.length + subs.fold<int>(0, (n, s) => n + menu.itemsOf(c.id, subcategoryId: s.id).where(_matches).length);
    if (_search.isNotEmpty && visible == 0) return const SizedBox.shrink();

    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('cat-${c.id}'),
        initiallyExpanded: _search.isNotEmpty || menu.categories.length <= 3,
        shape: const Border(),
        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent, fontSize: 16)),
        subtitle: Text('$total items${subs.isNotEmpty ? ' · ${subs.length} subcategories' : ''}',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        trailing: widget.readOnly
            ? null
            : PopupMenuButton<String>(
                tooltip: 'Category actions',
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
                  const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.danger))),
                ],
              ),
        children: [
          for (var k = 0; k < direct.length; k++) _buildItem(menu, direct, k),
          for (final s in subs) _buildSubcategory(menu, c, s),
          if (total == 0)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No items yet. Use ⋮ → "Add item here".', style: TextStyle(color: Colors.white38)),
            ),
        ],
      ),
    );
  }

  Widget _buildSubcategory(MenuData menu, MenuCategory c, MenuSubcategory s) {
    final items = menu.itemsOf(c.id, subcategoryId: s.id).where(_matches).toList();
    if (_search.isNotEmpty && items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AppColors.surfaceAlt,
          padding: const EdgeInsets.only(left: 16),
          child: Row(
            children: [
              const Icon(Icons.subdirectory_arrow_right, size: 16, color: Colors.white38),
              const SizedBox(width: 6),
              Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white))),
              Text('${items.length}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              if (!widget.readOnly)
                PopupMenuButton<String>(
                  tooltip: 'Subcategory actions',
                  onSelected: (v) {
                    if (v == 'item') _openItemEditor(menu, categoryId: c.id, subcategoryId: s.id);
                    if (v == 'rename') _renameSubcategory(s);
                    if (v == 'delete') _deleteSubcategory(s);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'item', child: Text('Add item here')),
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.danger))),
                  ],
                )
              else
                const SizedBox(height: 40),
            ],
          ),
        ),
        for (var k = 0; k < items.length; k++) _buildItem(menu, items, k),
      ],
    );
  }

  Widget _buildItem(MenuData menu, List<MenuItem> siblings, int index) {
    final item = siblings[index];
    return Opacity(
      opacity: item.isAvailable ? 1 : 0.55,
      child: ListTile(
        leading: _ItemThumb(url: item.imageUrl),
        title: Row(
          children: [
            Flexible(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (item.isJain) const _Badge('J', Color(0xFF0091EA)),
            if (item.spicyLevel > 0) Text(' ${'🌶' * item.spicyLevel}', style: const TextStyle(fontSize: 12)),
          ],
        ),
        subtitle: Text(
          [
            item.variants.length > 1
                ? item.variants.map((v) => '${v.label} ₹${formatPrice(v.price)}').join(' · ')
                : item.priceSummary,
            if (item.addOns.isNotEmpty) '+ ${item.addOns.length} add-on${item.addOns.length > 1 ? 's' : ''}',
            if (!item.isAvailable) 'UNAVAILABLE',
          ].join('   '),
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: widget.readOnly
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: item.isAvailable ? 'Available — tap to mark sold out' : 'Unavailable — tap to make available',
                    child: Switch(
                      value: item.isAvailable,
                      activeThumbColor: AppColors.success,
                      onChanged: (v) => _guard(() => _repo.setAvailability(item.id, v)),
                    ),
                  ),
                  PopupMenuButton<String>(
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
                      if (index > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
                      if (index < siblings.length - 1) const PopupMenuItem(value: 'down', child: Text('Move down')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.danger))),
                    ],
                  ),
                ],
              ),
        onTap: widget.readOnly ? null : () => _openItemEditor(menu, item: item),
      ),
    );
  }
}

class _EmptyMenu extends StatelessWidget {
  const _EmptyMenu();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.restaurant_menu, size: 52, color: Colors.white24),
          SizedBox(height: 12),
          Text('Your menu is empty', style: TextStyle(fontSize: 16, color: Colors.white70)),
          SizedBox(height: 4),
          Text('Start by adding a category, e.g. "Pizza" or "Beverages".', style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }
}

class _ItemThumb extends StatelessWidget {
  const _ItemThumb({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: url == null
            ? Container(color: AppColors.surfaceAlt, child: const Icon(Icons.fastfood_outlined, color: Colors.white24))
            : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
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
          const SnackBar(content: Text('Please choose a photo under 2 MB.'), backgroundColor: AppColors.danger),
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
        const SnackBar(content: Text('Each size/variant needs a different name.'), backgroundColor: AppColors.danger),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.danger));
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(widget.item == null ? 'Add item' : 'Edit item'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent, fontSize: 15)),
            if (hint != null) Text(hint, style: const TextStyle(color: Colors.white38, fontSize: 12)),
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
            icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
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
      color: AppColors.surface,
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
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  onPressed: () => setState(() => _addOns.removeAt(i).dispose()),
                ),
              ],
            ),
            if (variantLabels.length > 1) ...[
              const SizedBox(height: 6),
              const Text('Available on (none selected = all sizes):', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
              color: AppColors.surfaceAlt,
              child: _newImage != null
                  ? Image.memory(_newImage!.bytes!, fit: BoxFit.cover)
                  : _imageUrl != null
                      ? Image.network(_imageUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image))
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_outlined, color: Colors.white38),
                            SizedBox(height: 4),
                            Text('Add photo', style: TextStyle(color: Colors.white38, fontSize: 12)),
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
            child: const Text('Remove photo', style: TextStyle(color: AppColors.danger, fontSize: 12)),
          ),
      ],
    );
  }
}
