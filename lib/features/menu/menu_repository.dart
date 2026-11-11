import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../core/data/firestore_paths.dart';
import 'menu_models.dart';

/// Thrown for actions that would lose data (e.g. deleting a non-empty category).
class MenuActionBlocked implements Exception {
  MenuActionBlocked(this.message);
  final String message;
  @override
  String toString() => message;
}

/// All menu reads/writes for one cafe. Every path is under cafes/{cafeId}/,
/// so one cafe's menu can never touch another's.
class MenuRepository {
  MenuRepository(this.cafeId);

  final String cafeId;

  CollectionReference<Map<String, dynamic>> get _cats => FirestorePaths.categories(cafeId);
  CollectionReference<Map<String, dynamic>> get _subs => FirestorePaths.subcategories(cafeId);
  CollectionReference<Map<String, dynamic>> get _items => FirestorePaths.menuItems(cafeId);

  /// Live, combined menu. Emits once all three collections have loaded.
  Stream<MenuData> watchMenu() {
    late StreamController<MenuData> controller;
    final subs = <StreamSubscription>[];
    List<MenuCategory>? cats;
    List<MenuSubcategory>? subcats;
    List<MenuItem>? items;

    void emit() {
      if (cats != null && subcats != null && items != null) {
        controller.add(MenuData(categories: cats!, subcategories: subcats!, items: items!));
      }
    }

    controller = StreamController<MenuData>(
      onListen: () {
        subs.add(_cats.snapshots().listen((s) {
          cats = s.docs.map(MenuCategory.fromDoc).toList();
          emit();
        }, onError: controller.addError));
        subs.add(_subs.snapshots().listen((s) {
          subcats = s.docs.map(MenuSubcategory.fromDoc).toList();
          emit();
        }, onError: controller.addError));
        subs.add(_items.snapshots().listen((s) {
          items = s.docs.map(MenuItem.fromDoc).toList();
          emit();
        }, onError: controller.addError));
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  // ---- Categories ----

  Future<void> saveCategory({String? id, required String name, int? sortOrder, bool isActive = true}) async {
    final data = <String, dynamic>{
      'name': name.trim(),
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
      'sortOrder': ?sortOrder,
    };
    if (id == null) {
      data['createdAt'] = FieldValue.serverTimestamp();
      data['sortOrder'] = sortOrder ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _cats.add(data);
    } else {
      await _cats.doc(id).set(data, SetOptions(merge: true));
    }
  }

  /// Refuses to delete a category that still has items or subcategories.
  Future<void> deleteCategory(String id) async {
    final items = await _items.where('categoryId', isEqualTo: id).limit(1).get();
    final subs = await _subs.where('categoryId', isEqualTo: id).limit(1).get();
    if (items.docs.isNotEmpty || subs.docs.isNotEmpty) {
      throw MenuActionBlocked('This category still has items or subcategories. Move or delete them first.');
    }
    await _cats.doc(id).delete();
  }

  // ---- Subcategories ----

  Future<void> saveSubcategory({String? id, required String categoryId, required String name, int? sortOrder}) async {
    final data = <String, dynamic>{
      'categoryId': categoryId,
      'name': name.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'sortOrder': ?sortOrder,
    };
    if (id == null) {
      data['createdAt'] = FieldValue.serverTimestamp();
      data['sortOrder'] = sortOrder ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _subs.add(data);
    } else {
      await _subs.doc(id).set(data, SetOptions(merge: true));
    }
  }

  Future<void> deleteSubcategory(String id) async {
    final items = await _items.where('subcategoryId', isEqualTo: id).limit(1).get();
    if (items.docs.isNotEmpty) {
      throw MenuActionBlocked('This subcategory still has items. Move or delete them first.');
    }
    await _subs.doc(id).delete();
  }

  // ---- Items ----

  /// Creates (id == null) or updates an item. Returns the item id.
  Future<String> saveItem(MenuItem item, {bool isNew = false}) async {
    final data = {...item.toMap(), 'updatedAt': FieldValue.serverTimestamp()};
    if (isNew) {
      data['createdAt'] = FieldValue.serverTimestamp();
      final ref = await _items.add(data);
      return ref.id;
    }
    await _items.doc(item.id).set(data, SetOptions(merge: true));
    return item.id;
  }

  Future<void> setAvailability(String itemId, bool available) =>
      _items.doc(itemId).update({'isAvailable': available, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> deleteItem(MenuItem item) async {
    await _items.doc(item.id).delete();
    if (item.imageUrl != null) {
      try {
        await FirebaseStorage.instance.refFromURL(item.imageUrl!).delete();
      } catch (_) {
        // Image may already be gone; the item is deleted either way.
      }
    }
  }

  /// Swaps sortOrder of two neighbours (simple up/down reordering).
  Future<void> swapOrder(DocumentReference<Map<String, dynamic>> a, int aOrder,
      DocumentReference<Map<String, dynamic>> b, int bOrder) async {
    final batch = FirebaseFirestore.instance.batch();
    // If both share the same order value, spread them apart first.
    final newA = aOrder == bOrder ? bOrder + 1 : bOrder;
    batch.update(a, {'sortOrder': newA});
    batch.update(b, {'sortOrder': aOrder});
    await batch.commit();
  }

  DocumentReference<Map<String, dynamic>> categoryRef(String id) => _cats.doc(id);
  DocumentReference<Map<String, dynamic>> subcategoryRef(String id) => _subs.doc(id);
  DocumentReference<Map<String, dynamic>> itemRef(String id) => _items.doc(id);

  /// Uploads a food photo (max 2 MB, enforced by storage.rules too) and
  /// returns its download URL.
  Future<String> uploadItemImage(String itemId, Uint8List bytes, String contentType) async {
    if (bytes.lengthInBytes > 2 * 1024 * 1024) {
      throw MenuActionBlocked('Image is too large. Please use a photo under 2 MB.');
    }
    final ext = contentType.contains('png') ? 'png' : (contentType.contains('webp') ? 'webp' : 'jpg');
    final ref = FirebaseStorage.instance
        .ref('cafes/$cafeId/menuItems/$itemId-${DateTime.now().millisecondsSinceEpoch}.$ext');
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }
}
