import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'captain_dashboard.dart';
import 'manager_dashboard.dart';
import 'dart:math';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDMe-TEEFwzfx7H1bBVwq8QKuD_Zpabs8",
      appId: "1:696863288881:web:216140984c82a5c8a00f90",
      messagingSenderId: "696853288881",
      projectId: "suratpos",
      authDomain: "suratpos.firebaseapp.com",
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
      title: 'Surat Pizza Shop - POS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: kIsWeb ? const CustomerCartScreen() : const StaffLoginHomeScreen(),
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
          title: const Text('🔑 Staff Portal Login'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select Role:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: 'Captain', child: Text('Captain (Kitchen)')),
                  DropdownMenuItem(value: 'Manager', child: Text('Manager (Admin)')),
                ],
                onChanged: (val) {
                  setStateDialog(() {
                    selectedRole = val!;
                  });
                },
              ),
              const SizedBox(height: 12),
              const Text('Enter Password:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
              onPressed: () {
                String pass = passwordController.text.trim();
                if (selectedRole == 'Captain' && pass == '123') {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const CaptainDashboardScreen()),
                  );
                } else if (selectedRole == 'Manager' && pass == '456') {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const ManagerDashboardScreen()),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Galat password hai bhai!')),
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
      appBar: AppBar(
        title: const Text('🍕 Surat Pizza Shop - Staff Portal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange[800],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.restaurant_menu, size: 80, color: Colors.orange),
              const SizedBox(height: 16),
              const Text('Welcome to Surat POS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Select your portal to login:', style: TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                  onPressed: () => showPasswordDialog(context),
                  icon: const Icon(Icons.lock),
                  label: const Text('Staff Login (Captain / Manager)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
  late String deviceId;
  
  final ValueNotifier<List<Map<String, dynamic>>> cartNotifier = ValueNotifier([]);
  late Future<QuerySnapshot> _menuFuture;

  @override
  void initState() {
    super.initState();
    deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    _menuFuture = FirebaseFirestore.instance.collection('menu_categories').get();
    _checkForActiveOrder();
  }

  Future<void> _checkForActiveOrder() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('deviceId', isEqualTo: deviceId)
          .where('status', whereIn: ['pending', 'preparing', 'ready'])
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        var doc = querySnapshot.docs.first;
        setState(() {
          activeOrderId = doc.id;
          nameController.text = doc.get('customerName') ?? '';
        });
      }
    } catch (e) {
      print("Error checking active order: $e");
    }
  }

  void addToCart(Map<String, dynamic> item, String size, double price) {
    List<Map<String, dynamic>> updatedCart = List.from(cartNotifier.value);
    var existingIndex = updatedCart.indexWhere((element) => element['name'] == item['name'] && element['size'] == size);
    
    if (existingIndex != -1) {
      updatedCart[existingIndex] = {
        ...updatedCart[existingIndex],
        'qty': updatedCart[existingIndex]['qty'] + 1,
      };
    } else {
      updatedCart.add({
        'name': item['name'],
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
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select Size: ${item['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Regular Size'),
                trailing: Text('₹$regP', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                onTap: () {
                  Navigator.pop(context);
                  addToCart(item, 'Regular', (regP).toDouble());
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('Medium Size'),
                trailing: Text('₹$medP', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                onTap: () {
                  Navigator.pop(context);
                  addToCart(item, 'Medium', (medP).toDouble());
                },
              ),
            ],
          ),
        ),
      );
    } else {
      double finalPrice = (stdP ?? regP ?? 0.0).toDouble();
      addToCart(item, 'Standard', finalPrice);
    }
  }

  void updateCartQty(int index, int change) {
    List<Map<String, dynamic>> updatedCart = List.from(cartNotifier.value);
    updatedCart[index]['qty'] += change;
    if (updatedCart[index]['qty'] <= 0) {
      updatedCart.removeAt(index);
    }
    cartNotifier.value = updatedCart;
  }

  void placeOrUpdateOrder() async {
    String customerName = nameController.text.trim();
    if (customerName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pehle apna naam toh likhiye bhai!')));
      return;
    }
    if (cartNotifier.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cart khali hai! Kam se kam ek item toh add karo.')));
      return;
    }

    try {
      double totalCartPrice = 0;
      for (var item in cartNotifier.value) {
        totalCartPrice += (item['price'] * item['qty']);
      }

      final querySnapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('deviceId', isEqualTo: deviceId)
          .where('status', whereIn: ['pending', 'preparing', 'ready'])
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        var existingDoc = querySnapshot.docs.first;
        activeOrderId = existingDoc.id;
        
        List existingItems = List.from(existingDoc.get('items') ?? []);
        
        for (var exItem in existingItems) {
          exItem['isDone'] = true;
        }

        double existingTotal = (existingDoc.get('totalPrice') ?? 0.0).toDouble();

        for (var newItem in cartNotifier.value) {
          var found = existingItems.firstWhere((element) => element['name'] == newItem['name'] && element['size'] == newItem['size'], orElse: () => null);
          if (found != null) {
            found['qty'] += newItem['qty'];
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
          'lastUpdatedAt': FieldValue.serverTimestamp(), // Re-order hone par queue me peeche chala jayega
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

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Order Placed / Updated! 🍕'),
          content: Text('$customerName, aapka order successfully queue me update ho gaya hai.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                cartNotifier.value = [];
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildMenuSection() {
    return FutureBuilder<QuerySnapshot>(
      future: _menuFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(40.0), child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text('Menu upload nahi hua hai abhi.', style: TextStyle(color: Colors.grey)),
          );
        }

        var categoryDocs = snapshot.data!.docs;

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: categoryDocs.length,
          itemBuilder: (context, catIndex) {
            var categoryData = categoryDocs[catIndex].data() as Map<String, dynamic>;
            String categoryName = categoryData['categoryName'] ?? '';
            List items = categoryData['items'] ?? [];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  child: Text(
                    categoryName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange),
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, itemIndex) {
                    final item = items[itemIndex];
                    var regP = item['regularPrice'];
                    var medP = item['mediumPrice'];
                    var stdP = item['price'];

                    String priceDisplay = '';
                    if (regP != null && medP != null) {
                      priceDisplay = 'Reg: ₹$regP | Med: ₹$medP';
                    } else if (stdP != null) {
                      priceDisplay = '₹$stdP';
                    } else {
                      priceDisplay = '₹${regP ?? 0}';
                    }

                    return InkWell(
                      onTap: () => _handleItemTap(item),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.orange.shade200),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item['name'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(priceDisplay, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                            const Spacer(),
                            const Align(
                              alignment: Alignment.bottomRight,
                              child: Icon(Icons.add_shopping_cart, size: 18, color: Colors.orange),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCartSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your Cart / Repeat Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Divider(),
          const SizedBox(height: 6),
          const Text('Enter Your Name:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'e.g. Sahil',
              filled: true,
              fillColor: Colors.white,
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          const Text('Selected Items:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: cartNotifier,
            builder: (context, cart, child) {
              if (cart.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: Center(child: Text('Cart is empty.', style: TextStyle(color: Colors.grey))),
                );
              }
              double totalCartPrice = 0;
              for (var item in cart) {
                totalCartPrice += (item['price'] * item['qty']);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: cart.length,
                    itemBuilder: (context, index) {
                      final cartItem = cart[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          dense: true,
                          title: Text('${cartItem['name']} (${cartItem['size']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text('₹${cartItem['price']} x ${cartItem['qty']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 18),
                                onPressed: () => updateCartQty(index, -1),
                              ),
                              Text('${cartItem['qty']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 18),
                                onPressed: () => updateCartQty(index, 1),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Bill:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('₹$totalCartPrice', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: placeOrUpdateOrder,
                      child: const Text('Place Order / Add to Running 🚀', style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
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
      appBar: AppBar(
        title: const Text('🍕 Surat Pizza Menu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
            tooltip: 'Staff Login',
            onPressed: () => StaffLoginHomeScreen.showPasswordDialog(context),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isMobile = constraints.maxWidth < 1000;
          if (isMobile) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMenuSection(),
                  const SizedBox(height: 20),
                  const Divider(thickness: 2),
                  const SizedBox(height: 10),
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
    );
  }
}