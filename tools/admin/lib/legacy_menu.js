/**
 * Pure conversion of the legacy menu (menu_categories docs with an `items`
 * array) into the new per-cafe model (categories + menuItems with variants).
 * No Firebase imports, so it can be unit-tested (test/legacy_menu.test.js).
 */

// Category order as in the original static menu file (lib/menu_data.dart).
const LEGACY_CATEGORY_ORDER = [
  'Signature Pizzas',
  'Exotic Veg / Paneer',
  'Speciality',
  'Classic Pizzas',
  'Garlic Bread & Sticks',
  'Stuffed Garlic Bread',
  'French Fries',
  'Pasta',
  'Cold Coffee & Shakes',
];

// Fallbacks that the old customer page hardcoded by name (lib/main.dart),
// used only when an item has no isJain/spicyLevel field of its own.
const LEGACY_JAIN = new Set([
  'simply margerita', 'sweet corn delight', 'spring fling', 'farm villa', 'flamy paneer', '7 cheese', 'spicy retreat',
]);
const LEGACY_SPICY = {
  'farm villa': 1, 'all veg pizza': 1, 'paneer tikka butter masala': 1, 'peri peri veg': 1, 'f/w veg special': 1,
  'flamy tounge': 2, 'spicy retreat': 2, 'f/w mushroom special': 2, 'garlic 2 pizza': 2,
};

function num(v) {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v))) return Number(v);
  return null;
}

/** Variants preserving the exact size labels old bills used. */
function legacyVariants(item) {
  const reg = num(item.regularPrice);
  const med = num(item.mediumPrice);
  const std = num(item.price);
  if (reg !== null && med !== null) {
    return [
      { label: 'Regular', price: reg },
      { label: 'Medium', price: med },
    ];
  }
  const single = std ?? reg ?? med ?? 0;
  return [{ label: 'Standard', price: single }];
}

/**
 * Prices the OLD manager POS could charge for this item (it guessed sizes
 * from the category name). Used only to report behaviour differences.
 */
function oldPosPrices(item, categoryName) {
  const lower = String(categoryName || '').toLowerCase();
  const multi = ['pizza', 'fries', 'signature', 'exotic', 'speciality'].some((k) => lower.includes(k));
  const reg = num(item.regularPrice ?? item.price) ?? 0;
  const med = num(item.mediumPrice ?? item.regularPrice ?? item.price) ?? 0;
  if (multi && ('regularPrice' in item || 'mediumPrice' in item)) {
    return [
      { label: 'Regular', price: reg },
      { label: 'Medium', price: med > 0 ? med : reg },
    ];
  }
  return [{ label: 'Standard', price: num(item.price) ?? reg }];
}

/**
 * @param legacyDocs [{id, data:{categoryName, items:[...]}}]
 * @returns {categories:[{id, data}], items:[{id, data}], warnings:[string]}
 */
function convertLegacyMenu(legacyDocs) {
  const warnings = [];
  const sorted = [...legacyDocs].sort((a, b) => {
    const ia = LEGACY_CATEGORY_ORDER.indexOf(a.data.categoryName);
    const ib = LEGACY_CATEGORY_ORDER.indexOf(b.data.categoryName);
    const ra = ia === -1 ? 1000 : ia;
    const rb = ib === -1 ? 1000 : ib;
    return ra !== rb ? ra - rb : String(a.data.categoryName).localeCompare(String(b.data.categoryName));
  });

  const categories = [];
  const items = [];

  sorted.forEach((doc, catIndex) => {
    const name = String(doc.data.categoryName ?? '').trim() || `Category ${catIndex + 1}`;
    categories.push({ id: doc.id, data: { name, sortOrder: catIndex + 1, isActive: true } });

    const list = Array.isArray(doc.data.items) ? doc.data.items : [];
    list.forEach((raw, idx) => {
      if (!raw || typeof raw !== 'object') {
        warnings.push(`Skipped a non-object item in "${name}" at position ${idx}.`);
        return;
      }
      const itemName = String(raw.name ?? '').trim();
      if (!itemName) {
        warnings.push(`Skipped an item without a name in "${name}" at position ${idx}.`);
        return;
      }
      const key = itemName.toLowerCase();
      const variants = legacyVariants(raw);

      const old = oldPosPrices(raw, name);
      const same = old.length === variants.length && old.every((o, i) => o.label === variants[i].label && o.price === variants[i].price);
      if (!same) {
        warnings.push(
          `"${itemName}" (${name}): old POS charged ${old.map((o) => `${o.label} ₹${o.price}`).join(' / ')}, ` +
            `new menu offers ${variants.map((v) => `${v.label} ₹${v.price}`).join(' / ')}. Please review.`,
        );
      }

      items.push({
        id: `${doc.id}_${String(idx).padStart(3, '0')}`,
        data: {
          categoryId: doc.id,
          subcategoryId: null,
          name: itemName,
          description: String(raw.desc ?? raw.description ?? '').trim(),
          imageUrl: null,
          isAvailable: raw.isAvailable !== false,
          isJain: typeof raw.isJain === 'boolean' ? raw.isJain : LEGACY_JAIN.has(key),
          spicyLevel: Math.max(0, Math.min(2, num(raw.spicyLevel) ?? LEGACY_SPICY[key] ?? 0)),
          sortOrder: idx + 1,
          variants,
          addOns: [],
        },
      });
    });
  });

  return { categories, items, warnings };
}

module.exports = { convertLegacyMenu, legacyVariants, oldPosPrices };
