const test = require('node:test');
const assert = require('node:assert');
const { convertLegacyMenu, legacyVariants } = require('../lib/legacy_menu');

test('two-size items keep Regular/Medium labels and prices', () => {
  assert.deepStrictEqual(legacyVariants({ regularPrice: 130, mediumPrice: 240 }), [
    { label: 'Regular', price: 130 },
    { label: 'Medium', price: 240 },
  ]);
});

test('single-price items become one Standard variant', () => {
  assert.deepStrictEqual(legacyVariants({ price: 79 }), [{ label: 'Standard', price: 79 }]);
  assert.deepStrictEqual(legacyVariants({ price: '80' }), [{ label: 'Standard', price: 80 }]);
  assert.deepStrictEqual(legacyVariants({ regularPrice: 99 }), [{ label: 'Standard', price: 99 }]);
});

test('Flamy Wood style menu converts with order, flags and stable ids', () => {
  const docs = [
    { id: 'zzz', data: { categoryName: 'Pasta', items: [{ name: 'Red Sauce Pasta', price: 160, desc: 'Red sauce pasta' }] } },
    {
      id: 'aaa',
      data: {
        categoryName: 'Signature Pizzas',
        items: [
          { name: 'Simply Margerita', regularPrice: 130, mediumPrice: 240, desc: 'say cheese', isJain: true, spicyLevel: 0 },
          { name: 'Farm Villa', regularPrice: 240, mediumPrice: 350 }, // flags from legacy lists
        ],
      },
    },
  ];
  const { categories, items, warnings } = convertLegacyMenu(docs);

  assert.deepStrictEqual(categories.map((c) => c.data.name), ['Signature Pizzas', 'Pasta']);
  assert.deepStrictEqual(categories.map((c) => c.id), ['aaa', 'zzz'], 'category ids preserved');
  assert.strictEqual(items.length, 3);
  assert.strictEqual(items[0].id, 'aaa_000');
  assert.strictEqual(items[0].data.description, 'say cheese');
  assert.strictEqual(items[1].data.isJain, true);
  assert.strictEqual(items[1].data.spicyLevel, 1);
  assert.deepStrictEqual(items[2].data.variants, [{ label: 'Standard', price: 160 }]);
  assert.deepStrictEqual(warnings, [], 'no pricing behaviour change for normal Flamy Wood data');
});

test('flags items whose old POS price differed', () => {
  const docs = [{ id: 'c1', data: { categoryName: 'Garlic Bread & Sticks', items: [{ name: 'Odd', regularPrice: 100, mediumPrice: 150 }] } }];
  const { warnings } = convertLegacyMenu(docs);
  assert.strictEqual(warnings.length, 1);
  assert.match(warnings[0], /Odd/);
});

test('skips nameless items with a warning', () => {
  const { items, warnings } = convertLegacyMenu([{ id: 'c', data: { categoryName: 'X', items: [{ price: 5 }, null] } }]);
  assert.strictEqual(items.length, 0);
  assert.strictEqual(warnings.length, 2);
});
