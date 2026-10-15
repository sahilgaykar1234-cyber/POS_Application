// lib/menu_data.dart
final List<Map<String, dynamic>> restaurantMenuCategories = [
  {
    'categoryName': 'Signature Pizzas',
    'items': [
      {'name': 'Simply Margerita', 'regularPrice': 130.0, 'mediumPrice': 240.0, 'desc': 'say cheese', 'isJain': true, 'spicyLevel': 0}, // J
      {'name': 'Double Cheese Margerita', 'regularPrice': 160.0, 'mediumPrice': 290.0, 'desc': 'Cheese with extra cheesy.', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Twist Onion', 'regularPrice': 140.0, 'mediumPrice': 250.0, 'desc': 'Onion & cheese', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Sweet Corn Delight', 'regularPrice': 140.0, 'mediumPrice': 250.0, 'desc': 'sweet corn & cheese', 'isJain': true, 'spicyLevel': 0}, // J
      {'name': 'Spring Fling', 'regularPrice': 180.0, 'mediumPrice': 280.0, 'desc': 'paneer, tomato, capsicum, corn', 'isJain': true, 'spicyLevel': 0}, // J
      {'name': 'Garden Special', 'regularPrice': 180.0, 'mediumPrice': 280.0, 'desc': 'capsicum, mushroom, Onion, tomato', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Ala Mexicana', 'regularPrice': 220.0, 'mediumPrice': 320.0, 'desc': 'onion, sweetcorn, baby corn, mushroom with Salsa dip', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Farm Villa', 'regularPrice': 240.0, 'mediumPrice': 350.0, 'desc': 'capsicum, tomato, paneer, broccoli, red peprica with korma dip', 'isJain': true, 'spicyLevel': 1}, // J + 🌶️
      {'name': 'All Veg Pizza', 'regularPrice': 280.0, 'mediumPrice': 420.0, 'desc': 'all vegies with cheese and peri peri dip', 'isJain': false, 'spicyLevel': 1}, // 🌶️
    ],
  },
  {
    'categoryName': 'Exotic Veg / Paneer',
    'items': [
      {'name': 'Paneer Tikka Butter Masala', 'regularPrice': 240.0, 'mediumPrice': 350.0, 'desc': 'marinated paneer, onion, capsicum, red peprica, cheeze', 'isJain': false, 'spicyLevel': 1}, // 🌶️
      {'name': 'Korma Paneer', 'regularPrice': 240.0, 'mediumPrice': 350.0, 'desc': 'onion, sweetcorn, jalepino, paneer in Korma dip', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Flamy Paneer', 'regularPrice': 240.0, 'mediumPrice': 350.0, 'desc': 'onion, capsicum, sweet corn, olives', 'isJain': true, 'spicyLevel': 0}, // J
      {'name': 'Double Paneer', 'regularPrice': 250.0, 'mediumPrice': 360.0, 'desc': 'capsicum, corn, red peprica, 2bl paneer in Korma dip', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Flamy tounge', 'regularPrice': 230.0, 'mediumPrice': 340.0, 'desc': 'jalepino, olives, mushroom, capsicum in hot and garlic dip', 'isJain': false, 'spicyLevel': 2}, // 🌶️🌶️
      {'name': '7 Cheese', 'regularPrice': 250.0, 'mediumPrice': 380.0, 'desc': 'white mozzarella, white cheese, montera, orange cheese, jack cheese', 'isJain': true, 'spicyLevel': 0}, // J
    ],
  },
  {
    'categoryName': 'Speciality',
    'items': [
      {'name': 'Pesto & Basil', 'regularPrice': 240.0, 'mediumPrice': 320.0, 'desc': 'capsicum, jalepino, paneer, basil leaves in pesto dip', 'isJain': false, 'spicyLevel': 1}, // 🌶️
      {'name': 'Peri Peri veg', 'regularPrice': 240.0, 'mediumPrice': 380.0, 'desc': 'onion, capsicum, mushroom, olives, paneer in peri peri dip', 'isJain': false, 'spicyLevel': 1}, // 🌶️
      {'name': 'Spicy Retreat', 'regularPrice': 260.0, 'mediumPrice': 400.0, 'desc': 'olives, red peprica, tomato, paneer, jalapino in jalepino dip', 'isJain': true, 'spicyLevel': 2}, // J + 🌶️🌶️
      {'name': 'F/W Veg Special', 'regularPrice': 260.0, 'mediumPrice': 420.0, 'desc': 'capsicum, broccoli, bell pepper onion, paneer, jalepino, olives in Korma & hot garlic dip', 'isJain': false, 'spicyLevel': 1}, // 🌶️
      {'name': 'F/W Mushroom Special', 'regularPrice': 250.0, 'mediumPrice': 390.0, 'desc': 'capsicum, tomato, onion, paneer, mushroom in salsa dip', 'isJain': false, 'spicyLevel': 2}, // 🌶️🌶️
      {'name': 'Garlic 2 Pizza', 'regularPrice': 250.0, 'mediumPrice': 380.0, 'desc': 'onion, capsicum, paneer, mushroom, jalepino in hot garlic dip', 'isJain': false, 'spicyLevel': 2}, // 🌶️🌶️
      {'name': 'Las Vegas Treat', 'regularPrice': 240.0, 'mediumPrice': 380.0, 'desc': 'mushroom, jalepino, babycorn, capsicum, tomato in peri peri dip', 'isJain': false, 'spicyLevel': 2}, // 🌶️🌶️
      {'name': 'Wild Garlic Pizza', 'regularPrice': 260.0, 'mediumPrice': 400.0, 'desc': 'onion, capsicum, paneer, broccoli, jalepino with a chopped burnt garlic with a hot & garlic dip.', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Schezwan Thunder', 'regularPrice': 240.0, 'mediumPrice': 380.0, 'desc': 'capsicum, onion, mushroom, red peprica, sweet corn with a Schezwan dip.', 'isJain': false, 'spicyLevel': 1}, // 🌶️
    ],
  },
  {
    'categoryName': 'Classic Pizzas',
    'items': [
      {'name': 'Tomato', 'price': 79.0, 'desc': 'Classic tomato pizza', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Onion', 'price': 89.0, 'desc': 'Classic onion pizza', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Capsicum', 'price': 99.0, 'desc': 'Classic capsicum pizza', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Sweet corn', 'price': 109.0, 'desc': 'Classic sweet corn pizza', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Onion & Capsicum', 'price': 120.0, 'desc': 'Onion & capsicum pizza', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Capsicum/ Onion Paneer', 'price': 120.0, 'desc': 'Capsicum, onion & paneer', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Jalepino & Olives', 'price': 120.0, 'desc': 'Jalepino & olives', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Jalepino, Sweet corn, Paneer', 'price': 150.0, 'desc': 'Jalepino, sweet corn, paneer', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Capsicum, Red Peprica, Paneer', 'price': 150.0, 'desc': 'Capsicum, red peprica, paneer', 'isJain': false, 'spicyLevel': 0},
    ],
  },
  {
    'categoryName': 'Garlic Bread & Sticks',
    'items': [
      {'name': 'Plain Garlic Bread', 'price': 80.0, 'desc': '4pcs garlic bread', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Cheesy Garlic Bread', 'price': 120.0, 'desc': '4pcs cheesy garlic bread', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Superme Garlic Bread', 'price': 140.0, 'desc': '4pcs supreme garlic bread', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Paneer Tikka Garlic Bread', 'price': 130.0, 'desc': '4pcs paneer tikka garlic bread', 'isJain': false, 'spicyLevel': 0},
      {'name': 'All in One Garlic Bread', 'price': 150.0, 'desc': '4pcs all in one garlic bread', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Plain Garlic Stick', 'price': 110.0, 'desc': 'Garlic stick', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Cheese Garlic Stick', 'price': 140.0, 'desc': 'Cheese garlic stick', 'isJain': false, 'spicyLevel': 0},
    ],
  },
  {
    'categoryName': 'Stuffed Garlic Bread',
    'items': [
      {'name': 'Volcano Cheese Stuffed', 'price': 200.0, 'desc': 'Cheesy & Spicy inside with a Lava Feel', 'isJain': false, 'spicyLevel': 1},
      {'name': 'Paneer Tikka Stuffed', 'price': 180.0, 'desc': 'Indian Taste with a Makhni flavour', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Creamy Corn & Cheese Bread', 'price': 160.0, 'desc': 'Kids & Family Favourite', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Jain Special Stuffed Bread', 'price': 160.0, 'desc': 'Tomato, capsicum, tomato and cheese', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Trpple Cheese Melt', 'price': 180.0, 'desc': 'Mozzarella, Cheddar, Processed Cheese', 'isJain': false, 'spicyLevel': 0},
    ],
  },
  {
    'categoryName': 'French Fries',
    'items': [
      {'name': 'Simple Salted Fries', 'regularPrice': 60.0, 'mediumPrice': 90.0, 'desc': 'French fries salted', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Peri Peri Fries', 'regularPrice': 70.0, 'mediumPrice': 100.0, 'desc': 'Peri peri spiced fries', 'isJain': false, 'spicyLevel': 1},
      {'name': 'Chipotle Cheesy Mix Fries', 'regularPrice': 100.0, 'mediumPrice': 140.0, 'desc': 'Chipotle cheesy mix fries', 'isJain': false, 'spicyLevel': 0},
    ],
  },
  {
    'categoryName': 'Pasta',
    'items': [
      {'name': 'Pink Sauce Pasta', 'price': 200.0, 'desc': 'Pink sauce pasta', 'isJain': false, 'spicyLevel': 0},
      {'name': 'White Sauce Pasta', 'price': 180.0, 'desc': 'White sauce pasta', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Red Sauce Pasta', 'price': 160.0, 'desc': 'Red sauce pasta', 'isJain': false, 'spicyLevel': 0},
    ],
  },
  {
    'categoryName': 'Cold Coffee & Shakes',
    'items': [
      {'name': 'Cold Coffee', 'price': 80.0, 'desc': 'Classic cold coffee', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Caramel Cold Coffee', 'price': 100.0, 'desc': 'Caramel flavored cold coffee', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Oreo Shake', 'price': 110.0, 'desc': 'Oreo milkshake', 'isJain': false, 'spicyLevel': 0},
      {'name': 'KitKat Shake', 'price': 110.0, 'desc': 'KitKat milkshake', 'isJain': false, 'spicyLevel': 0},
      {'name': 'Strawberry Shake', 'price': 110.0, 'desc': 'Strawberry milkshake', 'isJain': false, 'spicyLevel': 0},
    ],
  },
];