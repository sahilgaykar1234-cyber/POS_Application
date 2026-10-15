import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

import 'captain_dashboard.dart';
import 'manager_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDMe-TEEFwzfx7H1bBVwq8QKuD_Zpabs8",
      appId: "1:696863288881:web:216140984c82a5c8a00f90",
      messagingSenderId: "696853288881",
      projectId: "suratpos",
      storageBucket: "suratpos.appspot.com",
      measurementId: "G-LC3416JZYD",
    ),
  );

  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flamy Wood - Woodfire Pizzas',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF141211),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE65C00),
          secondary: Color(0xFFF7B731),
          surface: Color(0xFF1E1A17),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: kIsWeb ? const CustomerCartScreen() : const StaffLoginHomeScreen(),
    );
  }
}

// --- FLAMY WOOD EXACT ORIGINAL LOGO ---
class FlamyWoodOvenLogo extends StatelessWidget {
  final double size;
  const FlamyWoodOvenLogo({super.key, this.size = 50});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF141211),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE65C00).withOpacity(0.2),
                border: Border.all(color: const Color(0xFFE65C00)),
              ),
              child: Icon(Icons.local_fire_department, color: const Color(0xFFE65C00), size: size * 0.6),
            );
          },
        ),
      ),
    );
  }
}

class StaffLoginHomeScreen extends StatelessWidget {
  const StaffLoginHomeScreen({super.key});

  static void showPasswordDialog(BuildContext context) {
    final TextEditingController passwordController = TextEditingController();
    String selectedRole = 'Captain';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF231E1B),
          title: const Text('🔥 Staff Portal Login', style: TextStyle(color: Color(0xFFF7B731))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select Role:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: selectedRole,
                dropdownColor: const Color(0xFF2C2622),
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: 'Captain', child: Text('Captain (Kitchen)')),
                  DropdownMenuItem(value: 'Manager', child: Text('Manager (Admin)')),
                ],
                onChanged: (val) {
                  setStateDialog(() => selectedRole = val!);
                },
              ),
              const SizedBox(height: 12),
              const Text('Enter Password:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 6),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter password',
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
              onPressed: () {
                String pass = passwordController.text.trim();
                if (selectedRole == 'Captain' && pass == '123') {
                  Navigator.pop(context);
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const CaptainDashboardScreen()));
                } else if (selectedRole == 'Manager' && pass == '456') {
                  Navigator.pop(context);
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ManagerDashboardScreen()));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Galat password hai!')),
                  );
                }
              },
              child: const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141211),
      appBar: AppBar(
        title: const Text('FLAMY WOOD - Staff Portal', style: TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1A17),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const FlamyWoodOvenLogo(size: 85),
              const SizedBox(height: 18),
              const Text('FLAMY WOOD', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFFF7B731), letterSpacing: 1.5)),
              const Text('WOODFIRE BAKED PIZZAS • MADE WITH FRESH DOUGH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.5)),
              const SizedBox(height: 36),
              SizedBox(
                width: 320,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                  onPressed: () => showPasswordDialog(context),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Staff Login (Captain / Manager)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerCartScreen extends StatefulWidget {
  const CustomerCartScreen({super.key});

  @override
  State<CustomerCartScreen> createState() => _CustomerCartScreenState();
}

class _CustomerCartScreenState extends State<CustomerCartScreen> {
  final TextEditingController nameController = TextEditingController();
  String? activeOrderId;
  String deviceId = '';
  String selectedCategory = 'All';
  bool hasExistingOrder = false;

  final ValueNotifier<List<Map<String, dynamic>>> cartNotifier = ValueNotifier([]);
  late Future<QuerySnapshot> _menuFuture;

  // Strict 7 Jain Pizzas (Blue J)
  static const Set<String> _jainPizzas = {
    'simply margerita',
    'sweet corn delight',
    'spring fling',
    'farm villa',
    'flamy paneer',
    '7 cheese',
    'spicy retreat',
  };

  // Strict Chilli mapping as per original menu
  static const Map<String, int> _spicyLevels = {
    'farm villa': 1,
    'all veg pizza': 1,
    'paneer tikka butter masala': 1,
    'peri peri veg': 1,
    'f/w veg special': 1,
    'flamy tounge': 2,
    'spicy retreat': 2,
    'f/w mushroom special': 2,
    'garlic 2 pizza': 2,
  };

  final Map<String, String> categoryBannerImages = {
    'Signature Pizzas': 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=600&q=80',
    'Exotic Veg / Paneer': 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=600&q=80',
    'Speciality': 'https://images.unsplash.com/photo-1574071318508-1cdbab80d002?w=600&q=80',
    'Classic Pizzas': 'https://images.unsplash.com/photo-1590947132387-155cc02f3212?w=600&q=80',
    'Garlic Bread & Sticks': 'https://images.unsplash.com/photo-1619895092538-128341789043?w=600&q=80',
    'Stuffed Garlic Bread': 'https://images.unsplash.com/photo-1541745537411-b8046dc6d66c?w=600&q=80',
    'French Fries': 'https://images.unsplash.com/photo-1576107232684-1279f3908594?w=600&q=80',
    'Pasta': 'https://images.unsplash.com/photo-1608897013039-887f21d8c804?w=600&q=80',
    'Cold Coffee & Shakes': 'https://images.unsplash.com/photo-1572490122747-3968b75cc699?w=600&q=80',
  };

  @override
  void initState() {
    super.initState();
    _initPersistentDeviceId();
    _menuFuture = FirebaseFirestore.instance.collection('menu_categories').get();
  }

  // Cross-platform Persistent Device ID (Android, iOS, Web sab jagah kaam karega)
  Future<void> _initPersistentDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedId = prefs.getString('flamy_wood_device_id');
    if (savedId == null || savedId.isEmpty) {
      savedId = 'device_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
      await prefs.setString('flamy_wood_device_id', savedId);
    }
    if (mounted) {
      setState(() {
        deviceId = savedId!;
      });
      _checkForActiveOrder();
    }
  }

  // Check karna ki kya aaj ka koi unsettled order chal raha hai
  Future<void> _checkForActiveOrder() async {
    if (deviceId.isEmpty) return;
    try {
      DateTime now = DateTime.now();
      DateTime startOfToday = DateTime(now.year, now.month, now.day);

      final querySnapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('deviceId', isEqualTo: deviceId)
          .where('status', whereIn: ['pending', 'preparing', 'ready'])
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        var doc = querySnapshot.docs.first;
        if (mounted) {
          setState(() {
            activeOrderId = doc.id;
            nameController.text = doc.get('customerName') ?? '';
            hasExistingOrder = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            activeOrderId = null;
            hasExistingOrder = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error checking active order: $e");
    }
  }

  double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  String _formatPrice(dynamic val) {
    double d = _toDouble(val);
    if (d == d.roundToDouble()) {
      return d.toInt().toString();
    }
    return d.toStringAsFixed(1);
  }

  void addToCart(Map<String, dynamic> item, String size, double price) {
    List<Map<String, dynamic>> updatedCart = List.from(cartNotifier.value);
    var existingIndex = updatedCart.indexWhere((element) => element['name'] == item['name'] && element['size'] == size);

    if (existingIndex != -1) {
      updatedCart[existingIndex] = {
        ...updatedCart[existingIndex],
        'qty': (updatedCart[existingIndex]['qty'] as int) + 1,
      };
    } else {
      updatedCart.add({
        'name': item['name']?.toString() ?? 'Item',
        'price': price,
        'size': size,
        'qty': 1,
        'isDone': false,
      });
    }
    cartNotifier.value = updatedCart;
  }

  void _handleItemTap(Map<String, dynamic> item) {
    var regP = item['regularPrice'];
    var medP = item['mediumPrice'];
    var stdP = item['price'];

    if (regP != null && medP != null) {
      double regPriceVal = _toDouble(regP);
      double medPriceVal = _toDouble(medP);

      showModalBottomSheet(
        backgroundColor: const Color(0xFF1E1A17),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        context: context,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select Size: ${item['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFF7B731))),
              const SizedBox(height: 12),
              ListTile(
                tileColor: const Color(0xFF26211D),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                title: const Text('Regular Size', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                trailing: Text('₹${_formatPrice(regPriceVal)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF7B731), fontSize: 16)),
                onTap: () {
                  Navigator.pop(context);
                  addToCart(item, 'Regular', regPriceVal);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                tileColor: const Color(0xFF26211D),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                title: const Text('Medium Size', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                trailing: Text('₹${_formatPrice(medPriceVal)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF7B731), fontSize: 16)),
                onTap: () {
                  Navigator.pop(context);
                  addToCart(item, 'Medium', medPriceVal);
                },
              ),
            ],
          ),
        ),
      );
    } else {
      double finalPrice = _toDouble(stdP ?? regP ?? 0.0);
      addToCart(item, 'Standard', finalPrice);
    }
  }

  void updateCartQty(int index, int change) {
    List<Map<String, dynamic>> updatedCart = List.from(cartNotifier.value);
    int newQty = (updatedCart[index]['qty'] as int) + change;
    if (newQty <= 0) {
      updatedCart.removeAt(index);
    } else {
      updatedCart[index]['qty'] = newQty;
    }
    cartNotifier.value = updatedCart;
  }

  void placeOrUpdateOrder() async {
    String customerName = nameController.text.trim();
    if (customerName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pehle apna Table No / Naam enter kijiye!')));
      return;
    }
    if (cartNotifier.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cart khali hai! Kam se kam ek item select kijiye.')));
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00))),
      );

      double totalCartPrice = 0;
      for (var item in cartNotifier.value) {
        totalCartPrice += (_toDouble(item['price']) * (item['qty'] as int));
      }

      DateTime now = DateTime.now();
      DateTime startOfToday = DateTime(now.year, now.month, now.day);

      final querySnapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('deviceId', isEqualTo: deviceId)
          .where('status', whereIn: ['pending', 'preparing', 'ready'])
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        var existingDoc = querySnapshot.docs.first;
        activeOrderId = existingDoc.id;

        List existingItems = List.from(existingDoc.get('items') ?? []);
        for (var exItem in existingItems) {
          exItem['isDone'] = true;
        }

        double existingTotal = _toDouble(existingDoc.get('totalPrice'));

        for (var newItem in cartNotifier.value) {
          var found = existingItems.firstWhere(
            (element) => element['name'] == newItem['name'] && element['size'] == newItem['size'],
            orElse: () => null,
          );
          if (found != null) {
            found['qty'] = (found['qty'] as int) + (newItem['qty'] as int);
            found['isDone'] = false;
          } else {
            newItem['isDone'] = false;
            existingItems.add(newItem);
          }
        }

        double updatedTotal = existingTotal + totalCartPrice;

        await FirebaseFirestore.instance.collection('orders').doc(activeOrderId).update({
          'customerName': customerName,
          'items': existingItems,
          'totalPrice': updatedTotal,
          'status': 'pending',
          'kitchenStatus': 'pending',
          'hasNewItemsAdded': true,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        List initialItems = cartNotifier.value.map((e) => {...e, 'isDone': false}).toList();
        DocumentReference docRef = await FirebaseFirestore.instance.collection('orders').add({
          'deviceId': deviceId,
          'customerName': customerName,
          'items': initialItems,
          'totalPrice': totalCartPrice,
          'status': 'pending',
          'kitchenStatus': 'pending',
          'paymentStatus': 'pending',
          'hasNewItemsAdded': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        activeOrderId = docRef.id;
      }

      if (!mounted) return;
      Navigator.pop(context);

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1A17),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FlamyWoodOvenLogo(size: 65),
              const SizedBox(height: 14),
              const Text('Order Sent To Kitchen! 🔥', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFF7B731))),
              const SizedBox(height: 8),
              Text('$customerName, aapka order kitchen queue me update ho gaya hai.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    cartNotifier.value = [];
                    _checkForActiveOrder();
                  });
                },
                child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildTopBrandHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF191614),
        border: Border(bottom: BorderSide(color: Color(0xFF2C2520))),
      ),
      child: Row(
        children: [
          const FlamyWoodOvenLogo(size: 46),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('FLAMY WOOD', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFFF7B731), letterSpacing: 1.5)),
              Text('WOODFIRE BAKED PIZZAS • MADE WITH FRESH DOUGH', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySelector(List<dynamic> categories) {
    List<String> catNames = ['All'];
    for (var c in categories) {
      String? name = c['categoryName']?.toString();
      if (name != null && name.isNotEmpty) {
        catNames.add(name);
      }
    }

    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: catNames.length,
        itemBuilder: (context, idx) {
          final cat = catNames[idx];
          final isSelected = cat == selectedCategory;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(cat),
              selected: isSelected,
              onSelected: (val) {
                if (val) setState(() => selectedCategory = cat);
              },
              selectedColor: const Color(0xFFE65C00),
              backgroundColor: const Color(0xFF231E1B),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFFF7B731),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF382F2A)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenuSection() {
    return FutureBuilder<QuerySnapshot>(
      future: _menuFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(40.0), child: CircularProgressIndicator(color: Color(0xFFE65C00))));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text('Menu upload nahi hua hai abhi.')));
        }

        var categoryDocs = snapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

        var filteredCategories = selectedCategory == 'All'
            ? categoryDocs
            : categoryDocs.where((c) => (c['categoryName']?.toString() ?? '') == selectedCategory).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCategorySelector(categoryDocs),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredCategories.length,
              itemBuilder: (context, catIndex) {
                var categoryData = filteredCategories[catIndex];
                String categoryName = categoryData['categoryName']?.toString() ?? '';
                List items = List.from(categoryData['items'] ?? []);
                String bannerImg = categoryBannerImages[categoryName] ?? '';

                if (items.isEmpty) return const SizedBox.shrink();

                return Container(
                  margin: const EdgeInsets.only(bottom: 22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1715),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2520)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (bannerImg.isNotEmpty)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          child: Stack(
                            children: [
                              Image.network(
                                bannerImg,
                                height: 110,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                              Container(
                                height: 110,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.transparent, const Color(0xFF1B1715).withOpacity(0.95)],
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 10,
                                left: 16,
                                child: Text(
                                  categoryName.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFF7B731),
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Text(
                            categoryName.toUpperCase(),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFF7B731)),
                          ),
                        ),

                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(color: Color(0xFF26211E), height: 1),
                        itemBuilder: (context, itemIndex) {
                          final item = Map<String, dynamic>.from(items[itemIndex]);
                          var regP = item['regularPrice'];
                          var medP = item['mediumPrice'];
                          var stdP = item['price'];
                          String itemName = item['name']?.toString().trim() ?? '';
                          String lowerItemName = itemName.toLowerCase();

                          bool isJain = _jainPizzas.contains(lowerItemName);
                          int spicyLevel = _spicyLevels[lowerItemName] ?? 0;

                          String priceDisplay = '';
                          if (regP != null && medP != null) {
                            priceDisplay = '₹${_formatPrice(regP)} / ₹${_formatPrice(medP)}';
                          } else if (stdP != null) {
                            priceDisplay = '₹${_formatPrice(stdP)}';
                          } else {
                            priceDisplay = '₹${_formatPrice(regP ?? 0)}';
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (isJain) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0091EA),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'J',
                                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              itemName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                            ),
                                          ),
                                          if (spicyLevel > 0) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              spicyLevel == 2 ? '🌶️🌶️' : '🌶️',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (item['desc'] != null && item['desc'].toString().isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          item['desc'].toString(),
                                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        priceDisplay,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFFF7B731)),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF28221D),
                                    foregroundColor: const Color(0xFFF7B731),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: const BorderSide(color: Color(0xFFE65C00), width: 1.2),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  onPressed: () => _handleItemTap(item),
                                  child: const Text('ADD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildCartSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1715),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2520)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.shopping_bag_outlined, color: Color(0xFFE65C00)),
                  SizedBox(width: 8),
                  Text('Your Order Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFF7B731))),
                ],
              ),
              if (hasExistingOrder)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Text('Active Order Running', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const Divider(color: Color(0xFF2C2520), height: 20),
          TextField(
            controller: nameController,
            enabled: !hasExistingOrder,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Table No / Customer Name',
              labelStyle: const TextStyle(color: Colors.white60),
              prefixIcon: const Icon(Icons.table_restaurant_outlined, color: Color(0xFFE65C00), size: 20),
              filled: true,
              fillColor: const Color(0xFF231E1B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              isDense: true,
            ),
          ),
          if (hasExistingOrder) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF26211D),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, color: Color(0xFFF7B731), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Aapka pehle se ek order chal raha hai. Naye items add karne par kitchen queue me sath jud jayenge.',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: cartNotifier,
            builder: (context, cart, child) {
              if (cart.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: Text('Cart is empty. Tap ADD to select items.', style: TextStyle(color: Colors.white38)),
                  ),
                );
              }

              double totalCartPrice = 0;
              for (var item in cart) {
                totalCartPrice += (_toDouble(item['price']) * (item['qty'] as int));
              }

              return Column(
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: cart.length,
                    separatorBuilder: (_, __) => const Divider(color: Color(0xFF26211E), height: 10),
                    itemBuilder: (context, index) {
                      final cartItem = cart[index];
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${cartItem['name']} (${cartItem['size']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                                Text('₹${_formatPrice(cartItem['price'])} x ${cartItem['qty']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF28221D),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF382F2A)),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 16, color: Color(0xFFE65C00)),
                                  onPressed: () => updateCartQty(index, -1),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                ),
                                Text('${cartItem['qty']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 16, color: Color(0xFFE65C00)),
                                  onPressed: () => updateCartQty(index, 1),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const Divider(color: Color(0xFF2C2520), height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(hasExistingOrder ? 'New Items Total:' : 'Total Bill:', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70)),
                      Text('₹${_formatPrice(totalCartPrice)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFF7B731))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasExistingOrder ? const Color(0xFF9C27B0) : const Color(0xFFE65C00),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: placeOrUpdateOrder,
                      child: Text(
                        hasExistingOrder ? 'Add To Current Order 🔥' : 'Send Order to Kitchen 🔥',
                        style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141211),
      appBar: AppBar(
        title: const Text('FLAMY WOOD', style: TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        backgroundColor: const Color(0xFF1E1A17),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_outlined, color: Color(0xFFF7B731)),
            tooltip: 'Staff Login',
            onPressed: () => StaffLoginHomeScreen.showPasswordDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTopBrandHeader(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                bool isMobile = constraints.maxWidth < 900;
                if (isMobile) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildMenuSection(),
                        const SizedBox(height: 20),
                        _buildCartSection(),
                      ],
                    ),
                  );
                } else {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: SingleChildScrollView(child: _buildMenuSection())),
                        const SizedBox(width: 20),
                        Expanded(flex: 2, child: SingleChildScrollView(child: _buildCartSection())),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}