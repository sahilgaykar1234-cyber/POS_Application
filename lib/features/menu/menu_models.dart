import 'package:cloud_firestore/cloud_firestore.dart';

double _toDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int _toInt(Object? v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

/// Formats a price without trailing ".0" (₹240 not ₹240.0).
String formatPrice(num value) {
  final d = value.toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(2);
}

/// One size/variant of an item, e.g. "10 inch" ₹300 (note: "6 pcs").
/// The label is what appears on bills as the item "size".
class MenuVariant {
  const MenuVariant({required this.label, required this.price, this.note = ''});

  final String label;
  final double price;

  /// Shown when choosing, not printed on the bill (e.g. "6 pcs").
  final String note;

  factory MenuVariant.fromMap(Map<String, dynamic> m) => MenuVariant(
        label: (m['label'] ?? 'Standard').toString(),
        price: _toDouble(m['price']),
        note: (m['note'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'label': label,
        'price': price,
        if (note.isNotEmpty) 'note': note,
      };
}

/// Optional extra charged on top of a variant, e.g. "Cheese burst-style" +₹120.
/// [variantLabels] empty = available for every variant.
class MenuAddOn {
  const MenuAddOn({required this.name, required this.price, this.variantLabels = const []});

  final String name;
  final double price;
  final List<String> variantLabels;

  bool appliesTo(String variantLabel) => variantLabels.isEmpty || variantLabels.contains(variantLabel);

  factory MenuAddOn.fromMap(Map<String, dynamic> m) => MenuAddOn(
        name: (m['name'] ?? '').toString(),
        price: _toDouble(m['price']),
        variantLabels: List<String>.from((m['variantLabels'] as List?)?.map((e) => e.toString()) ?? const []),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'price': price,
        'variantLabels': variantLabels,
      };
}

class MenuCategory {
  const MenuCategory({required this.id, required this.name, this.sortOrder = 0, this.isActive = true});

  final String id;
  final String name;
  final int sortOrder;
  final bool isActive;

  factory MenuCategory.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return MenuCategory(
      id: doc.id,
      name: (d['name'] ?? '').toString(),
      sortOrder: _toInt(d['sortOrder']),
      isActive: d['isActive'] != false,
    );
  }
}

class MenuSubcategory {
  const MenuSubcategory({required this.id, required this.categoryId, required this.name, this.sortOrder = 0});

  final String id;
  final String categoryId;
  final String name;
  final int sortOrder;

  factory MenuSubcategory.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return MenuSubcategory(
      id: doc.id,
      categoryId: (d['categoryId'] ?? '').toString(),
      name: (d['name'] ?? '').toString(),
      sortOrder: _toInt(d['sortOrder']),
    );
  }
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.categoryId,
    this.subcategoryId,
    required this.name,
    this.description = '',
    this.imageUrl,
    this.isAvailable = true,
    this.isJain = false,
    this.spicyLevel = 0,
    this.sortOrder = 0,
    this.variants = const [],
    this.addOns = const [],
  });

  final String id;
  final String categoryId;
  final String? subcategoryId;
  final String name;
  final String description;
  final String? imageUrl;
  final bool isAvailable;
  final bool isJain;

  /// 0 = not spicy, 1 = 🌶, 2 = 🌶🌶
  final int spicyLevel;
  final int sortOrder;
  final List<MenuVariant> variants;
  final List<MenuAddOn> addOns;

  bool get hasChoices => variants.length > 1 || addOns.isNotEmpty;

  /// "₹240 / ₹300" style summary of all variant prices.
  String get priceSummary => variants.isEmpty ? '₹0' : variants.map((v) => '₹${formatPrice(v.price)}').join(' / ');

  factory MenuItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final sub = d['subcategoryId'];
    final img = d['imageUrl'];
    return MenuItem(
      id: doc.id,
      categoryId: (d['categoryId'] ?? '').toString(),
      subcategoryId: sub is String && sub.isNotEmpty ? sub : null,
      name: (d['name'] ?? '').toString(),
      description: (d['description'] ?? '').toString(),
      imageUrl: img is String && img.isNotEmpty ? img : null,
      isAvailable: d['isAvailable'] != false,
      isJain: d['isJain'] == true,
      spicyLevel: _toInt(d['spicyLevel']).clamp(0, 2),
      sortOrder: _toInt(d['sortOrder']),
      variants: ((d['variants'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => MenuVariant.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
      addOns: ((d['addOns'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => MenuAddOn.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'categoryId': categoryId,
        'subcategoryId': subcategoryId,
        'name': name,
        'description': description,
        'imageUrl': imageUrl,
        'isAvailable': isAvailable,
        'isJain': isJain,
        'spicyLevel': spicyLevel,
        'sortOrder': sortOrder,
        'variants': variants.map((v) => v.toMap()).toList(),
        'addOns': addOns.map((a) => a.toMap()).toList(),
      };

  MenuItem copyWith({bool? isAvailable, int? sortOrder, String? imageUrl}) => MenuItem(
        id: id,
        categoryId: categoryId,
        subcategoryId: subcategoryId,
        name: name,
        description: description,
        imageUrl: imageUrl ?? this.imageUrl,
        isAvailable: isAvailable ?? this.isAvailable,
        isJain: isJain,
        spicyLevel: spicyLevel,
        sortOrder: sortOrder ?? this.sortOrder,
        variants: variants,
        addOns: addOns,
      );
}

/// A cart line built from a menu choice, in the exact shape existing orders
/// use: {name, price, size, qty, isDone}. Add-ons are folded into the line's
/// name and unit price so bill totals keep using price × qty unchanged.
class CartLine {
  const CartLine({required this.name, required this.size, required this.unitPrice});

  final String name;
  final String size;
  final double unitPrice;

  static CartLine build(MenuItem item, MenuVariant variant, List<MenuAddOn> addOns) {
    final extras = addOns.where((a) => a.appliesTo(variant.label)).toList();
    final name = extras.isEmpty ? item.name : '${item.name} + ${extras.map((a) => a.name).join(' + ')}';
    final price = variant.price + extras.fold<double>(0, (s, a) => s + a.price);
    return CartLine(name: name, size: variant.label, unitPrice: price);
  }
}

/// Whole menu of one cafe, sorted and grouped for display.
class MenuData {
  MenuData({required List<MenuCategory> categories, required List<MenuSubcategory> subcategories, required List<MenuItem> items})
      : categories = [...categories]..sort(_bySortThenName((c) => c.sortOrder, (c) => c.name)),
        subcategories = [...subcategories]..sort(_bySortThenName((s) => s.sortOrder, (s) => s.name)),
        items = [...items]..sort(_bySortThenName((i) => i.sortOrder, (i) => i.name));

  static const MenuData empty = MenuData._empty();
  const MenuData._empty()
      : categories = const [],
        subcategories = const [],
        items = const [];

  final List<MenuCategory> categories;
  final List<MenuSubcategory> subcategories;
  final List<MenuItem> items;

  bool get isEmpty => categories.isEmpty && items.isEmpty;

  List<MenuSubcategory> subcategoriesOf(String categoryId) =>
      subcategories.where((s) => s.categoryId == categoryId).toList();

  /// Items in a category. With [subcategoryId] = null returns only items not
  /// placed in any (existing) subcategory.
  List<MenuItem> itemsOf(String categoryId, {String? subcategoryId, bool directOnly = false}) {
    final subIds = subcategoriesOf(categoryId).map((s) => s.id).toSet();
    return items.where((i) {
      if (i.categoryId != categoryId) return false;
      if (subcategoryId != null) return i.subcategoryId == subcategoryId;
      if (directOnly) return i.subcategoryId == null || !subIds.contains(i.subcategoryId);
      return true;
    }).toList();
  }

  static int Function(T, T) _bySortThenName<T>(int Function(T) sort, String Function(T) name) {
    return (a, b) {
      final s = sort(a).compareTo(sort(b));
      return s != 0 ? s : name(a).toLowerCase().compareTo(name(b).toLowerCase());
    };
  }
}
