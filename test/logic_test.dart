import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/core/subscription/cafe_access.dart';
import 'package:pos_app/core/utils/formatters.dart';
import 'package:pos_app/features/admin/admin_service.dart';
import 'package:pos_app/features/menu/menu_models.dart';

void main() {
  final now = DateTime(2026, 11, 11, 12);

  group('evaluateCafeAccess (mirrors firestore.rules cafeOperational)', () {
    CafeAccessState s(Map<String, dynamic> cafe) => evaluateCafeAccess(cafe, now).state;

    test('active cafe without subscription is allowed (e.g. Flamy Wood after migration)', () {
      expect(s({'status': 'active'}), CafeAccessState.allowed);
    });
    test('blocked statuses', () {
      expect(s({'status': 'suspended'}), CafeAccessState.blocked);
      expect(s({'status': 'inactive'}), CafeAccessState.blocked);
      expect(s({'status': 'deleted'}), CafeAccessState.blocked);
    });
    test('legacy data waits for migration', () {
      expect(s({'status': 'active', 'legacyData': true}), CafeAccessState.migrating);
    });
    test('expired by date or status blocks; data is not touched', () {
      expect(s({'status': 'active', 'subscription': {'status': 'active', 'expiryDate': now.subtract(const Duration(hours: 1))}}),
          CafeAccessState.blocked);
      expect(s({'status': 'active', 'subscription': {'status': 'expired'}}), CafeAccessState.blocked);
      expect(s({'status': 'active', 'subscription': {'status': 'suspended'}}), CafeAccessState.blocked);
    });
    test('expiring within 7 days warns but works', () {
      final a = evaluateCafeAccess({
        'status': 'active',
        'subscription': {'status': 'active', 'expiryDate': now.add(const Duration(days: 3))},
      }, now);
      expect(a.state, CafeAccessState.allowedWithWarning);
      expect(a.canUsePos, isTrue);
      expect(a.message, contains('3 days'));
    });
    test('pending payment within period warns but works; trial works', () {
      expect(s({'status': 'active', 'subscription': {'status': 'pending', 'expiryDate': now.add(const Duration(days: 20))}}),
          CafeAccessState.allowedWithWarning);
      expect(s({'status': 'active', 'subscription': {'status': 'trial', 'expiryDate': now.add(const Duration(days: 20))}}),
          CafeAccessState.allowed);
    });
  });

  group('Fmt', () {
    test('Indian money grouping', () {
      expect(Fmt.money(0), '₹0');
      expect(Fmt.money(999), '₹999');
      expect(Fmt.money(4999), '₹4,999');
      expect(Fmt.money(123456), '₹1,23,456');
      expect(Fmt.money(12345678.5), '₹1,23,45,678.50');
      expect(Fmt.money(499, symbol: 'Rs. '), 'Rs. 499');
    });
    test('dates', () {
      expect(Fmt.date(DateTime(2026, 3, 5)), '05 Mar 2026');
      expect(Fmt.date(null), '—');
    });
  });

  group('CartLine (bill format unchanged: name/size/price)', () {
    const pizza = MenuItem(
      id: 'm',
      categoryId: 'c',
      name: 'Margherita',
      variants: [
        MenuVariant(label: '8 inch', price: 240, note: '6 pcs'),
        MenuVariant(label: '10 inch', price: 300, note: '6 pcs'),
      ],
      addOns: [MenuAddOn(name: 'Cheese burst-style', price: 120, variantLabels: ['10 inch'])],
    );

    test('plain variant', () {
      final l = CartLine.build(pizza, pizza.variants[0], const []);
      expect(l.name, 'Margherita');
      expect(l.size, '8 inch');
      expect(l.unitPrice, 240);
    });
    test('add-on folded into unit price and name', () {
      final l = CartLine.build(pizza, pizza.variants[1], pizza.addOns);
      expect(l.name, 'Margherita + Cheese burst-style');
      expect(l.size, '10 inch');
      expect(l.unitPrice, 420);
    });
    test('add-on not allowed for this size is ignored', () {
      final l = CartLine.build(pizza, pizza.variants[0], pizza.addOns);
      expect(l.unitPrice, 240);
      expect(l.name, 'Margherita');
    });
    test('price summary and choice detection', () {
      expect(pizza.priceSummary, '₹240 / ₹300');
      expect(pizza.hasChoices, isTrue);
      const single = MenuItem(id: 's', categoryId: 'c', name: 'Water', variants: [MenuVariant(label: 'Standard', price: 10)]);
      expect(single.hasChoices, isFalse);
    });
  });

  group('MenuData grouping', () {
    final data = MenuData(
      categories: const [MenuCategory(id: 'b', name: 'Beverages', sortOrder: 2), MenuCategory(id: 'p', name: 'Pizza', sortOrder: 1)],
      subcategories: const [MenuSubcategory(id: 's1', categoryId: 'p', name: 'Classic')],
      items: const [
        MenuItem(id: '1', categoryId: 'p', subcategoryId: 's1', name: 'Margherita'),
        MenuItem(id: '2', categoryId: 'p', name: 'Garlic Bread'),
        MenuItem(id: '3', categoryId: 'p', subcategoryId: 'deleted-sub', name: 'Orphan'),
        MenuItem(id: '4', categoryId: 'b', name: 'Sprite'),
      ],
    );

    test('categories sorted by sortOrder', () {
      expect(data.categories.map((c) => c.name), ['Pizza', 'Beverages']);
    });
    test('direct items include orphans of deleted subcategories (never hidden)', () {
      expect(data.itemsOf('p', directOnly: true).map((i) => i.name), ['Garlic Bread', 'Orphan']);
      expect(data.itemsOf('p', subcategoryId: 's1').map((i) => i.name), ['Margherita']);
    });
  });

  group('CafeSummary subscription state', () {
    test('pending, expired, cancelled, none', () {
      final pending = CafeSummary('a', {
        'status': 'active',
        'subscription': {'status': 'pending', 'paymentStatus': 'pending', 'expiryDate': now.add(const Duration(days: 10))},
      });
      final overdue = CafeSummary('b', {
        'status': 'active',
        'subscription': {'status': 'active', 'paymentStatus': 'pending', 'expiryDate': now.subtract(const Duration(days: 1))},
      });
      expect(pending.subState(now), SubState.pending);
      expect(overdue.subState(now), SubState.expired);
      expect(CafeSummary('c', {'subscription': {'status': 'cancelled', 'expiryDate': now.add(const Duration(days: 3))}}).subState(now), SubState.cancelled);
      expect(CafeSummary('d', {'status': 'active'}).subState(now), SubState.none);
    });
  });
}
