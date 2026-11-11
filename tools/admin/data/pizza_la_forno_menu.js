/**
 * Pizza La Forno — menu extracted from "PIZZA LA FORNO.pdf" (6 pages).
 *
 * Names, descriptions and prices are copied exactly as printed (including the
 * PDF's own spellings, e.g. "Chessy Veggie", "juccini", "Jelepion"), except
 * repeated spaces were collapsed. Review with:
 *     node import_menu.js --menu data/pizza_la_forno_menu.js --print
 *
 * ASSUMPTIONS (the PDF was ambiguous here — change below if needed):
 *  A1. "Open Garlic Bread" and "Stuffed Garlic Bread" headings share one list
 *      and one price column  -> each item has two sizes "Open" and "Stuffed"
 *      at the SAME price.
 *  A2. Garlic breads and pizzas are categories; the PDF's section headings
 *      (Classic, Veggie Delight, …) are subcategories.
 *  A3. Veggie Delight has no size header of its own; its prices sit under the
 *      Classic 8"/10" columns -> 8 inch ₹260, 10 inch ₹320 (no 12 inch).
 *  A4. "Cheese burst-style +₹120 (Only For 10 Inch Pizza)" is an add-on on the
 *      10 inch size of Classic, Veggie Delight, Speciality Veg and Exotic.
 *      Not offered on Neapolitan (12 inch only).
 *  A5. Toppings and Packing Charges are normal items in "Extras", flat price
 *      for any size, added manually by staff.
 *  A6. Blue circled "J" = Jain option (isJain). 🌶 = spicy level 1.
 *  A7. Slice counts kept as printed ("10 inch" = "6 pcs") and shown only as a
 *      note when choosing a size — they are not printed on bills.
 */

const CHEESE_BURST = { name: 'Cheese burst-style', price: 120, variantLabels: ['10 inch'] };

const size = (label, price, note = '') => ({ label, price, ...(note ? { note } : {}) });

// Size tables exactly as printed per section.
const SIZES = {
  classic: [size('8 inch', 240, '6 pcs'), size('10 inch', 300, '6 pcs')],
  veggieDelight: [size('8 inch', 260, '6 pcs'), size('10 inch', 320, '6 pcs')],
  speciality: [size('8 inch', 300, '6 pcs'), size('10 inch', 380, '6 pcs'), size('12 inch', 499, '8 pcs')],
  exotic: [size('8 inch', 320, '6 pcs'), size('10 inch', 420, '6 pcs'), size('12 inch', 540, '8 pcs')],
};

const J = true; // Jain marker for readability below

module.exports = {
  cafeName: 'Pizza La Forno',
  source: 'PIZZA LA FORNO.pdf (pages 2–6)',

  categories: [
    {
      key: 'garlic-bread',
      name: 'Garlic Bread',
      subcategories: [
        { key: 'overload-garlic-bread', name: 'Over Load Garlic Bread' },
        { key: 'open-stuffed-garlic-bread', name: 'Open / Stuffed Garlic Bread' },
      ],
    },
    {
      key: 'pizza',
      name: 'Pizza',
      subcategories: [
        { key: 'classic', name: 'Classic' },
        { key: 'veggie-delight', name: 'Veggie Delight' },
        { key: 'speciality-veg', name: 'Speciality Veg' },
        { key: 'exotic', name: 'Exotic' },
        { key: 'neapolitan', name: 'Neapolitan Pizza' },
      ],
    },
    { key: 'beverages', name: 'Beverages', subcategories: [] },
    { key: 'extras', name: 'Extras', subcategories: [] },
  ],

  sections: [
    // ---------------------------------------------------------------- page 2
    {
      category: 'garlic-bread',
      subcategory: 'overload-garlic-bread',
      items: [
        { name: 'Chili Thecha Paneer , Onion', price: 300 },
        { name: 'Thai Chili , paneer , Olive & Basil', price: 320 },
        { name: 'Arabic Chermoula Spice Paneer', price: 320 },
        { name: 'Green Garlic & Cheese Corn', price: 300 },
        { name: 'Creamy Corn & Spinach', price: 300 },
        { name: 'Mushroom & Jalapeno', price: 320 },
      ],
    },
    {
      category: 'garlic-bread',
      subcategory: 'open-stuffed-garlic-bread',
      variantsFromPrice: (p) => [size('Open', p), size('Stuffed', p)], // A1
      items: [
        { name: 'Green Garlic Paneer', price: 240 },
        { name: 'Cheese & Chili', price: 200 },
        { name: 'Onion & Paneer', price: 230 },
        { name: 'Olive , Jelepion With Curry Masala', price: 220 },
        { name: 'Paneer Corn Chilly', price: 230 },
        { name: 'Mac N Cheese', price: 240 },
        { name: 'Paneer ,Red Peprika & Chilly Thecha', price: 260 },
        { name: 'Mushroom & Onion', price: 230 },
      ],
    },

    // ---------------------------------------------------------------- page 3
    {
      category: 'pizza',
      subcategory: 'classic',
      variants: SIZES.classic,
      addOns: [CHEESE_BURST],
      items: [
        { name: 'Margherita', description: 'Tomato sauce, mozzarella and fresh basil' },
        { name: 'Say Cheese', description: 'Tomato sauce, mozzarella, Process cheese' },
        { name: 'Chili Cheese Corn', description: 'Sweet Corn , Paprika Spice' },
        { name: 'Onion Tomato Masala', description: 'Onion, Tomato With Curry Masala' },
      ],
    },
    {
      category: 'pizza',
      subcategory: 'veggie-delight',
      variants: SIZES.veggieDelight, // A3
      addOns: [CHEESE_BURST],
      items: [
        { name: 'O.T.C', description: 'Onion, Tomato, Capsicum' },
        { name: 'Veggie Supreme', description: 'Oinon , chili , Capsicum and Garlic' },
        { name: 'Masala Veggie', description: 'Onion , Tomato , Corn With Capsicum & Mozzarella', spicy: 1 },
        { name: 'Trio Surprise', description: 'Tomato , Basil and Onion' },
      ],
    },
    {
      category: 'pizza',
      subcategory: 'speciality-veg',
      variants: SIZES.speciality,
      addOns: [CHEESE_BURST],
      items: [
        { name: 'All Veg Exotica', description: 'Onion, Capsicum , Broccoli , juccini, Baby Corn, Sweet Corn , Mushroom' },
        { name: 'Veggie Heaven', jain: J, description: 'Broccoli , juccini, olives, jelepino, cheese spread ,Capsicum with babycorn with Hot Garlic sauce' },
        { name: 'Paprika Veggie', spicy: 1, description: 'Red paprika, olive , mushroom, capsicum with baby corn and broccoli' },
        { name: 'Mac & Cheese', spicy: 1, description: 'Creamy Macroni , peri peri ,cheese cubes , olive, onion &corn' },
        { name: 'Spicy Basil Pesto', spicy: 1, description: 'Basil Pesto onion , red paprika ,Olive , Chili , jalapeno and tomato' },
        { name: 'Mexican Fiesta', description: 'Jalapeno , olives , capsicum , orange spread corn and onion with Mexican Spread' },
        { name: 'Chessy Veggie', description: 'Olive , Red Paprika , Juccini , Cheese Sauce , Capsicum , Onion and Paneer' },
        { name: 'Green Garlic Magic', description: 'Corn , Liquid Cheese ,Green Garlic , Chili , Olive and Onion' },
        { name: 'Desi - Style', spicy: 1, description: 'Olive ,Mushroom , paneer , Onion , Tomato and Chili with Makhani Spread' },
        { name: 'Hot Garlic Paneer', spicy: 1, description: 'Hot Garlic Spread , Paneer , onion , Capsicum , olive , Mushroom' },
        { name: 'Cheesy Mustard Veggie', description: 'Onion , Capsicum , Juccini , Olive , Red Paprika and Mustard Spared' },
        { name: 'Smoky BBQ PANEER', description: 'Onion, Capsicum , paneer with BBQ sauce mozzarella olive and Chili' },
      ],
    },

    // ---------------------------------------------------------------- page 4
    {
      category: 'pizza',
      subcategory: 'exotic',
      variants: SIZES.exotic,
      addOns: [CHEESE_BURST],
      items: [
        { name: 'Pizza la Forno Special', jain: J, description: 'Red paprika, black olive, Jalapeno, paneer, corn, broccoli, juccini , liquid cheese' },
        { name: 'Makhan Singh', jain: J, description: 'Mozzarella, Paneer , Makhani spread , Olive Capsicum and onion' },
        { name: 'Habanero Chili Paneer', jain: J, spicy: 1, description: 'Habanero Chili Paneer , Onion , Capsicum Corn jalapeno with Chili' },
        { name: 'Chipotle Paneer', jain: J, description: 'Tomato sauce , Mexican spread, paneer, capsicum, jalapeno and onion With Chili Oil' },
        { name: '5 Cheese Master', jain: J, description: 'Mozzarella ,cheddar, cheese blend, cheese spread with Filler Cheese and jalapeno' },
        { name: 'Spicy Thecha Paneer', spicy: 1, description: 'Thecha spread , paneer , mozzarella ,onion , red paprika and capsicum' },
        { name: 'Tandoori Paneer Tikka', jain: J, description: 'Onion, Capsicum , paneer with tandoori spread mozzarella and , jalapeno' },
        { name: 'Paneer Peppe', description: 'Black pepper paneer tikka , onion , olive , mushroom , red paprika' },
        { name: 'Peri Peri Paneer', spicy: 1, description: 'Peri peri seasoning , black olive, paneer, capsicum , onion , Sweet Corn & Chili' },
        { name: 'Paprika Paneer', jain: J, description: 'Red paprika , Onion, Capsicum , paneer with tandoori spread and mozzarella' },
        { name: 'Cheese Lava', jain: J, description: 'Cheese Stuffed , Crust Topped With Melting Cheesy Lava In Middle With Chili' },
        { name: 'Hot Salsa Paneer', spicy: 1, description: 'Hot Salsa , Paneer , Onion , Jelepino With Four Cheese Blend' },
        { name: 'Jamaican Jerk Paneer', spicy: 1, description: 'Jerk Spice Paneer , Capsicum , Onion & Corn' },
        { name: 'Korean Spice Paneer', spicy: 1, description: 'Paneer , Korean Spread , Onion , Red Paprika' },
        { name: 'Green Garlic Cheesy Paneer', spicy: 1, description: 'Spicy Paneer , Green Garlic , Cheese Sauce , Oilves & Onion' },
        { name: 'Hot Mustard Paneer', spicy: 1, description: 'Mustard spread , paneer , onion , tomato , corn and capsicum' },
      ],
    },

    // ---------------------------------------------------------------- page 5
    {
      category: 'pizza',
      subcategory: 'neapolitan',
      variantsFromPrice: (p) => [size('12 inch', p)],
      items: [
        { name: 'Margherita', jain: J, price: 500, description: 'Tomato sauce, basil, Mozzarella and cherry Tomato' },
        { name: 'Basilica', spicy: 1, price: 620, description: 'Basil pesto , jalapeno , bell peppers ,green chili , cherry Tomato , onion , olive' },
        { name: 'Verdure Aglio Olio', jain: J, price: 600, description: 'Bell peppers, Broccoli , juccini, Baby Corn, olive , Mushroom garlic and herbs' },
        { name: 'Spicy Fiesta', jain: J, spicy: 1, price: 600, description: 'Bell peppers , Zucchini, olives ,red paprika , Black Olive , Jalapeno & hot garlic' },
        { name: 'Mango Chili Cheese', spicy: 1, price: 550, description: 'Mango Chili hot sauce , onion , bell peppers , Corn Jalapeno' },
        { name: 'Creamy Garlicky Spinach , Mushroom', price: 600, description: 'Creamy corn spinach with garlic Mushroom' },
        { name: 'Seven Cheese Wonder', jain: J, price: 650, description: 'Cheddar , Monterey Jack , Mozzarella colby Parmesan Cheese , Procced Cheese , Filler Cheese with Olive and Chili Oil' },
        { name: 'Siciliano', jain: J, price: 600, description: 'Bell peppers , basil crumbs , onion , olive , mushroom , red paprika and capers' },
      ],
    },

    // ---------------------------------------------------------------- page 6
    {
      category: 'beverages',
      items: [
        { name: 'Water bottle', price: 10 },
        { name: 'Thums Up', price: 20 },
        { name: 'Sosyo', price: 20 },
        { name: 'Sprite', price: 20 },
        { name: 'Maaza', price: 20 },
      ],
    },
    {
      category: 'extras',
      items: [
        { name: 'Vegetables {Topping}', price: 30 },
        { name: 'Cheese /Paneer {Topping}', price: 50 },
        { name: 'Pizza Packing Charges', price: 20 },
      ],
    },
  ],
};
