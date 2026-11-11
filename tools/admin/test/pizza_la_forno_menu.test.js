/**
 * Cross-checks the Pizza La Forno data file against the PDF:
 * item counts per section, every price, and the flags.
 */
const test = require('node:test');
const assert = require('node:assert');
const menu = require('../data/pizza_la_forno_menu');
const { buildMenuDocs } = require('../lib/menu_import');

const docs = buildMenuDocs(menu);
const bySub = (sub) => docs.items.filter((i) => i.data.subcategoryId === `sub_${sub}`);
const byCat = (cat) => docs.items.filter((i) => i.data.categoryId === `cat_${cat}` && !i.data.subcategoryId);
const find = (sub, name) => bySub(sub).find((i) => i.data.name === name);
const prices = (i) => i.data.variants.map((v) => [v.label, v.price]);

test('no validation errors', () => assert.deepStrictEqual(docs.errors, []));

test('section counts match the PDF (66 items)', () => {
  assert.strictEqual(bySub('overload-garlic-bread').length, 6);
  assert.strictEqual(bySub('open-stuffed-garlic-bread').length, 8);
  assert.strictEqual(bySub('classic').length, 4);
  assert.strictEqual(bySub('veggie-delight').length, 4);
  assert.strictEqual(bySub('speciality-veg').length, 12);
  assert.strictEqual(bySub('exotic').length, 16);
  assert.strictEqual(bySub('neapolitan').length, 8);
  assert.strictEqual(byCat('beverages').length, 5);
  assert.strictEqual(byCat('extras').length, 3);
  assert.strictEqual(docs.items.length, 66);
  assert.strictEqual(docs.categories.length, 4);
  assert.strictEqual(docs.subcategories.length, 7);
});

test('page 2 garlic bread prices', () => {
  const ol = Object.fromEntries(bySub('overload-garlic-bread').map((i) => [i.data.name, i.data.variants[0].price]));
  assert.deepStrictEqual(ol, {
    'Chili Thecha Paneer , Onion': 300,
    'Thai Chili , paneer , Olive & Basil': 320,
    'Arabic Chermoula Spice Paneer': 320,
    'Green Garlic & Cheese Corn': 300,
    'Creamy Corn & Spinach': 300,
    'Mushroom & Jalapeno': 320,
  });
  const os = Object.fromEntries(bySub('open-stuffed-garlic-bread').map((i) => [i.data.name, prices(i)]));
  assert.deepStrictEqual(os['Green Garlic Paneer'], [['Open', 240], ['Stuffed', 240]]);
  assert.deepStrictEqual(os['Cheese & Chili'], [['Open', 200], ['Stuffed', 200]]);
  assert.deepStrictEqual(os['Mac N Cheese'], [['Open', 240], ['Stuffed', 240]]);
  assert.deepStrictEqual(os['Paneer ,Red Peprika & Chilly Thecha'], [['Open', 260], ['Stuffed', 260]]);
  assert.deepStrictEqual(os['Mushroom & Onion'], [['Open', 230], ['Stuffed', 230]]);
});

test('pizza size prices per section', () => {
  for (const i of bySub('classic')) assert.deepStrictEqual(prices(i), [['8 inch', 240], ['10 inch', 300]]);
  for (const i of bySub('veggie-delight')) assert.deepStrictEqual(prices(i), [['8 inch', 260], ['10 inch', 320]]);
  for (const i of bySub('speciality-veg')) assert.deepStrictEqual(prices(i), [['8 inch', 300], ['10 inch', 380], ['12 inch', 499]]);
  for (const i of bySub('exotic')) assert.deepStrictEqual(prices(i), [['8 inch', 320], ['10 inch', 420], ['12 inch', 540]]);
  const neo = Object.fromEntries(bySub('neapolitan').map((i) => [i.data.name, prices(i)]));
  assert.deepStrictEqual(neo, {
    Margherita: [['12 inch', 500]],
    Basilica: [['12 inch', 620]],
    'Verdure Aglio Olio': [['12 inch', 600]],
    'Spicy Fiesta': [['12 inch', 600]],
    'Mango Chili Cheese': [['12 inch', 550]],
    'Creamy Garlicky Spinach , Mushroom': [['12 inch', 600]],
    'Seven Cheese Wonder': [['12 inch', 650]],
    Siciliano: [['12 inch', 600]],
  });
});

test('cheese burst only on 10 inch of Classic/Veggie Delight/Speciality/Exotic', () => {
  for (const sub of ['classic', 'veggie-delight', 'speciality-veg', 'exotic']) {
    for (const i of bySub(sub)) {
      assert.deepStrictEqual(i.data.addOns, [{ name: 'Cheese burst-style', price: 120, variantLabels: ['10 inch'] }], i.data.name);
    }
  }
  for (const i of [...bySub('neapolitan'), ...bySub('overload-garlic-bread'), ...byCat('beverages')]) {
    assert.deepStrictEqual(i.data.addOns, [], i.data.name);
  }
});

test('Jain and spicy markers match the PDF', () => {
  const jain = docs.items.filter((i) => i.data.isJain).map((i) => i.data.name).sort();
  assert.deepStrictEqual(jain, [
    '5 Cheese Master', 'Cheese Lava', 'Chipotle Paneer', 'Habanero Chili Paneer', 'Makhan Singh', 'Margherita',
    'Paprika Paneer', 'Pizza la Forno Special', 'Seven Cheese Wonder', 'Siciliano', 'Spicy Fiesta',
    'Tandoori Paneer Tikka', 'Veggie Heaven', 'Verdure Aglio Olio',
  ]);
  assert.strictEqual(find('neapolitan', 'Margherita').data.isJain, true);
  assert.strictEqual(find('classic', 'Margherita').data.isJain, false);
  const spicy = docs.items.filter((i) => i.data.spicyLevel > 0).map((i) => i.data.name).sort();
  // Chili icons: p3 Veggie Delight 1 + Speciality 5, p4 Exotic 8, p5 Neapolitan 3 = 17
  assert.deepStrictEqual(spicy, [
    'Basilica', 'Desi - Style', 'Green Garlic Cheesy Paneer', 'Habanero Chili Paneer', 'Hot Garlic Paneer',
    'Hot Mustard Paneer', 'Hot Salsa Paneer', 'Jamaican Jerk Paneer', 'Korean Spice Paneer', 'Mac & Cheese',
    'Mango Chili Cheese', 'Masala Veggie', 'Paprika Veggie', 'Peri Peri Paneer', 'Spicy Basil Pesto',
    'Spicy Fiesta', 'Spicy Thecha Paneer',
  ]);
});

test('beverages and extras', () => {
  assert.deepStrictEqual(
    byCat('beverages').map((i) => [i.data.name, i.data.variants[0].price]),
    [['Water bottle', 10], ['Thums Up', 20], ['Sosyo', 20], ['Sprite', 20], ['Maaza', 20]],
  );
  assert.deepStrictEqual(
    byCat('extras').map((i) => [i.data.name, i.data.variants[0].price]),
    [['Vegetables {Topping}', 30], ['Cheese /Paneer {Topping}', 50], ['Pizza Packing Charges', 20]],
  );
});

test('the two Margheritas are distinct items', () => {
  const ids = docs.items.filter((i) => i.data.name === 'Margherita').map((i) => i.id);
  assert.strictEqual(new Set(ids).size, 2);
});
