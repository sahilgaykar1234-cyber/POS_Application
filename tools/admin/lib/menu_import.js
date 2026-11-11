/**
 * Pure helpers to turn a menu data file (see data/*.js) into Firestore
 * documents for cafes/{cafeId}/categories|subcategories|menuItems, with
 * strict validation. No Firebase imports (unit-tested).
 */

const slug = (s) =>
  String(s)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);

/**
 * @returns {{categories:[{id,data}], subcategories:[{id,data}], items:[{id,data}], errors:[string]}}
 */
function buildMenuDocs(menu) {
  const errors = [];
  const categories = [];
  const subcategories = [];
  const items = [];
  const catIds = new Map();
  const subIds = new Map();

  (menu.categories || []).forEach((c, ci) => {
    const id = `cat_${slug(c.key)}`;
    if (catIds.has(c.key)) errors.push(`Duplicate category key ${c.key}`);
    catIds.set(c.key, id);
    categories.push({ id, data: { name: c.name, sortOrder: ci + 1, isActive: true } });
    (c.subcategories || []).forEach((s, si) => {
      const sid = `sub_${slug(s.key)}`;
      if (subIds.has(s.key)) errors.push(`Duplicate subcategory key ${s.key}`);
      subIds.set(s.key, { id: sid, categoryKey: c.key });
      subcategories.push({ id: sid, data: { categoryId: id, name: s.name, sortOrder: si + 1 } });
    });
  });

  const seenItemIds = new Set();
  const order = new Map(); // per category/subcategory counter

  for (const section of menu.sections || []) {
    const catId = catIds.get(section.category);
    if (!catId) {
      errors.push(`Section refers to unknown category "${section.category}"`);
      continue;
    }
    let subId = null;
    if (section.subcategory) {
      const s = subIds.get(section.subcategory);
      if (!s || s.categoryKey !== section.category) {
        errors.push(`Section refers to unknown subcategory "${section.subcategory}" in "${section.category}"`);
        continue;
      }
      subId = s.id;
    }

    for (const it of section.items || []) {
      const name = String(it.name || '').replace(/\s+/g, ' ').trim();
      if (!name) {
        errors.push(`Item without name in ${section.category}/${section.subcategory || '-'}`);
        continue;
      }
      let variants;
      if (section.variants) variants = section.variants;
      else if (section.variantsFromPrice) variants = section.variantsFromPrice(it.price);
      else variants = [{ label: 'Standard', price: it.price }];

      variants = variants.map((v) => ({ ...v }));
      if (!variants.length) errors.push(`"${name}" has no price`);
      const labels = new Set();
      for (const v of variants) {
        if (typeof v.price !== 'number' || !(v.price > 0)) errors.push(`"${name}" has invalid price for ${v.label}: ${v.price}`);
        if (labels.has(v.label)) errors.push(`"${name}" has duplicate size ${v.label}`);
        labels.add(v.label);
      }
      const addOns = (it.addOns || section.addOns || []).map((a) => ({ ...a, variantLabels: [...(a.variantLabels || [])] }));
      for (const a of addOns) {
        for (const l of a.variantLabels) if (!labels.has(l)) errors.push(`"${name}": add-on ${a.name} refers to missing size ${l}`);
      }

      const groupKey = subId || catId;
      const n = (order.get(groupKey) || 0) + 1;
      order.set(groupKey, n);
      const id = `item_${slug(section.subcategory || section.category)}__${slug(name)}`;
      if (seenItemIds.has(id)) errors.push(`Duplicate item "${name}" in the same section`);
      seenItemIds.add(id);

      items.push({
        id,
        data: {
          categoryId: catId,
          subcategoryId: subId,
          name,
          description: String(it.description || '').replace(/\s+/g, ' ').trim(),
          imageUrl: null,
          isAvailable: true,
          isJain: it.jain === true,
          spicyLevel: Math.max(0, Math.min(2, Number(it.spicy || 0))),
          sortOrder: n,
          variants,
          addOns,
        },
      });
    }
  }
  return { categories, subcategories, items, errors };
}

/** Human-readable table for checking against the PDF. */
function formatMenu(menu, docs) {
  const lines = [];
  const catName = new Map(docs.categories.map((c) => [c.id, c.data.name]));
  const subName = new Map(docs.subcategories.map((s) => [s.id, s.data.name]));
  let lastGroup = '';
  for (const i of docs.items) {
    const group = `${catName.get(i.data.categoryId)}${i.data.subcategoryId ? ' › ' + subName.get(i.data.subcategoryId) : ''}`;
    if (group !== lastGroup) {
      lines.push('', `== ${group} ==`);
      lastGroup = group;
    }
    const flags = `${i.data.isJain ? ' [J]' : ''}${i.data.spicyLevel ? ' ' + '🌶'.repeat(i.data.spicyLevel) : ''}`;
    const prices = i.data.variants.map((v) => `${v.label} ₹${v.price}`).join(' | ');
    const add = i.data.addOns.length ? `   + ${i.data.addOns.map((a) => `${a.name} ₹${a.price} (${a.variantLabels.join('/') || 'all'})`).join(', ')}` : '';
    lines.push(`  ${i.data.name}${flags}  —  ${prices}${add}`);
  }
  lines.push('', `Total: ${docs.categories.length} categories, ${docs.subcategories.length} subcategories, ${docs.items.length} items`);
  return lines.join('\n');
}

module.exports = { buildMenuDocs, formatMenu, slug };
