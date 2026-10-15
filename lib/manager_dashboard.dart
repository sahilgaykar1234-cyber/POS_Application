import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';
import 'menu_data.dart';

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  String currentView = 'Dashboard'; // 'Dashboard', 'CompletedOrders', 'NewOrder', 'ManageMenu', 'SalesReports'
  DocumentSnapshot? editingOrderDoc;

  String salesFilterMode = 'Today';
  DateTime selectedDate = DateTime.now();
  String selectedMonthYear = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

  final TextEditingController nameController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';

  List<Map<String, dynamic>> tempCart = [];
  String selectedSize = 'Medium';

  // --- DISCOUNT & FINAL PRICE EDIT DIALOG ---
  void _openDiscountPriceDialog(BuildContext context, String docId, double currentTotal, String customerName) {
    final TextEditingController discountController = TextEditingController();
    final TextEditingController finalPriceController = TextEditingController(text: currentTotal.toInt().toString());
    String discountType = '₹ Flat';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          void recalculateFromDiscount() {
            double val = double.tryParse(discountController.text.trim()) ?? 0.0;
            double calculated = currentTotal;
            if (discountType == '₹ Flat') {
              calculated = currentTotal - val;
            } else {
              calculated = currentTotal - (currentTotal * (val / 100.0));
            }
            if (calculated < 0) calculated = 0;
            finalPriceController.text = calculated.toInt().toString();
          }

          void applyQuickDiscount(double val, String type) {
            discountType = type;
            discountController.text = val.toInt().toString();
            recalculateFromDiscount();
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1A17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE65C00), width: 1.2),
            ),
            title: Row(
              children: [
                const Icon(Icons.percent_rounded, color: Color(0xFFF7B731), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bill Discount: $customerName',
                    style: const TextStyle(color: Color(0xFFF7B731), fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF26211D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF382F2A)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Original Bill Total:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('₹${currentTotal.toInt()}', style: const TextStyle(color: Color(0xFFF7B731), fontSize: 16, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Quick Discount:', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      ActionChip(
                        backgroundColor: const Color(0xFF26211D),
                        side: const BorderSide(color: Color(0xFF382F2A)),
                        label: const Text('₹50 Off', style: TextStyle(color: Color(0xFFF7B731), fontSize: 11)),
                        onPressed: () => setStateDialog(() => applyQuickDiscount(50, '₹ Flat')),
                      ),
                      ActionChip(
                        backgroundColor: const Color(0xFF26211D),
                        side: const BorderSide(color: Color(0xFF382F2A)),
                        label: const Text('₹100 Off', style: TextStyle(color: Color(0xFFF7B731), fontSize: 11)),
                        onPressed: () => setStateDialog(() => applyQuickDiscount(100, '₹ Flat')),
                      ),
                      ActionChip(
                        backgroundColor: const Color(0xFF26211D),
                        side: const BorderSide(color: Color(0xFF382F2A)),
                        label: const Text('5% Off', style: TextStyle(color: Color(0xFFF7B731), fontSize: 11)),
                        onPressed: () => setStateDialog(() => applyQuickDiscount(5, '% Percent')),
                      ),
                      ActionChip(
                        backgroundColor: const Color(0xFF26211D),
                        side: const BorderSide(color: Color(0xFF382F2A)),
                        label: const Text('10% Off', style: TextStyle(color: Color(0xFFF7B731), fontSize: 11)),
                        onPressed: () => setStateDialog(() => applyQuickDiscount(10, '% Percent')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: discountController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Discount Value',
                            labelStyle: TextStyle(color: Colors.white60, fontSize: 12),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setStateDialog(() => recalculateFromDiscount()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: discountType,
                          dropdownColor: const Color(0xFF26211D),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                          items: const [
                            DropdownMenuItem(value: '₹ Flat', child: Text('₹ Flat')),
                            DropdownMenuItem(value: '% Percent', child: Text('% Off')),
                          ],
                          onChanged: (val) {
                            setStateDialog(() {
                              discountType = val!;
                              recalculateFromDiscount();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Final Payable Amount (Can Edit Manually):', style: TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: finalPriceController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixText: '₹ ',
                      prefixStyle: TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                onPressed: () async {
                  double updatedPrice = double.tryParse(finalPriceController.text.trim()) ?? currentTotal;
                  try {
                    await FirebaseFirestore.instance.collection('orders').doc(docId).update({
                      'totalPrice': updatedPrice,
                      'originalPrice': currentTotal,
                      'discountGiven': (currentTotal - updatedPrice) > 0 ? (currentTotal - updatedPrice) : 0,
                    });
                    if (!context.mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Bill discount applied! New Total: ₹${updatedPrice.toInt()}'), backgroundColor: Colors.green),
                    );
                  } catch (e) {
                    debugPrint("Error updating price: $e");
                  }
                },
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Save Final Bill'),
              ),
            ],
          );
        },
      ),
    );
  }

  void markOrderAsFinalDone(BuildContext context, String docId, String customerName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Order Complete', style: TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold)),
        content: Text('Kya aap "$customerName" ka order finalize karke Completed History me move karna chahte hain?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFirestore.instance.collection('orders').doc(docId).update({
                  'status': 'completed',
                  'kitchenStatus': 'completed',
                  'completedAt': FieldValue.serverTimestamp(),
                });
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Order for "$customerName" completed ho gaya!'), backgroundColor: Colors.green),
                );
              } catch (e) {
                debugPrint("Error completing order: $e");
              }
            },
            child: const Text('Confirm Done ✔'),
          ),
        ],
      ),
    );
  }

  void confirmAndToggleItem(BuildContext context, String docId, List currentItems, int itemIndex) {
    var item = currentItems[itemIndex];
    bool currentVal = item['isDone'] ?? false;
    String actionText = currentVal ? "unmark" : "ready mark";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Item Status Confirmation', style: TextStyle(color: Color(0xFFF7B731))),
        content: Text('Kya aap "${item['name']}" ko $actionText karna chahte hain?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: currentVal ? Colors.orange : Colors.green, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _toggleItemDoneStatus(docId, currentItems, itemIndex);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _toggleItemDoneStatus(String docId, List currentItems, int itemIndex) async {
    try {
      List updatedItems = List.from(currentItems);
      bool currentVal = updatedItems[itemIndex]['isDone'] ?? false;
      updatedItems[itemIndex]['isDone'] = !currentVal;

      bool allDone = updatedItems.every((item) => (item['isDone'] ?? false) == true);
      String newStatus = allDone ? 'ready' : 'preparing';

      await FirebaseFirestore.instance.collection('orders').doc(docId).update({
        'items': updatedItems,
        'status': newStatus,
        'kitchenStatus': newStatus,
      });
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> _uploadMenuToFirebase(BuildContext context) async {
    try {
      var collection = FirebaseFirestore.instance.collection('menu_categories');
      var snapshots = await collection.get();
      for (var doc in snapshots.docs) {
        await doc.reference.delete();
      }

      for (var category in restaurantMenuCategories) {
        await collection.add(category);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Flamy Wood menu successfully updated!')));
      setState(() {});
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading: $e')));
    }
  }

  void _openAddCategoryDialog(BuildContext context) {
    final TextEditingController categoryNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1A17),
          title: const Text('Add Menu Category', style: TextStyle(color: Color(0xFFF7B731))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Category Name:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 6),
              TextField(
                controller: categoryNameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'e.g. Burgers, Starters', isDense: true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
              onPressed: () async {
                String catName = categoryNameController.text.trim();
                if (catName.isEmpty) return;

                var existing = await FirebaseFirestore.instance.collection('menu_categories').where('categoryName', isEqualTo: catName).get();
                if (existing.docs.isNotEmpty) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category pehle se exist karti hai!')));
                  return;
                }

                await FirebaseFirestore.instance.collection('menu_categories').add({'categoryName': catName, 'items': []});
                if (!context.mounted) return;
                Navigator.pop(context);
                setState(() {});
              },
              child: const Text('Add Category'),
            ),
          ],
        );
      },
    );
  }

  void _openAddMenuItemDialog(BuildContext context) async {
    var snapshot = await FirebaseFirestore.instance.collection('menu_categories').get();
    List<String> categories = [];
    for (var doc in snapshot.docs) {
      String name = doc.get('categoryName') ?? '';
      if (name.isNotEmpty) categories.add(name);
    }

    if (categories.isEmpty) {
      categories = ['Signature Pizzas', 'Classic Pizzas', 'French Fries', 'Speciality', 'Pasta'];
    }

    final TextEditingController newItemNameController = TextEditingController();
    final TextEditingController newItemDescController = TextEditingController();
    final TextEditingController newItemPriceController = TextEditingController();
    final TextEditingController newItemRegularPriceController = TextEditingController();
    final TextEditingController newItemMediumPriceController = TextEditingController();

    String selectedCategory = categories.first;

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            bool isMultiPriceCat = selectedCategory.toLowerCase().contains('pizza') ||
                selectedCategory.toLowerCase().contains('fries') ||
                selectedCategory.toLowerCase().contains('signature') ||
                selectedCategory.toLowerCase().contains('exotic') ||
                selectedCategory.toLowerCase().contains('speciality');

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1A17),
              title: const Text('Add New Item', style: TextStyle(color: Color(0xFFF7B731))),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Category:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white70)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      dropdownColor: const Color(0xFF26211D),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      items: categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                      onChanged: (val) => setStateDialog(() => selectedCategory = val!),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: newItemNameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 10),
                    TextField(controller: newItemDescController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 10),
                    if (isMultiPriceCat) ...[
                      TextField(controller: newItemRegularPriceController, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Regular Price (₹)', border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 10),
                      TextField(controller: newItemMediumPriceController, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Medium Price (₹)', border: OutlineInputBorder(), isDense: true)),
                    ] else ...[
                      TextField(controller: newItemPriceController, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Price (₹)', border: OutlineInputBorder(), isDense: true)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                  onPressed: () async {
                    String name = newItemNameController.text.trim();
                    if (name.isEmpty) return;

                    Map<String, dynamic> newItem = {
                      'name': name,
                      'desc': newItemDescController.text.trim(),
                    };

                    if (isMultiPriceCat) {
                      newItem['regularPrice'] = double.tryParse(newItemRegularPriceController.text.trim()) ?? 0.0;
                      newItem['mediumPrice'] = double.tryParse(newItemMediumPriceController.text.trim()) ?? 0.0;
                    } else {
                      newItem['price'] = double.tryParse(newItemPriceController.text.trim()) ?? 0.0;
                    }

                    var query = await FirebaseFirestore.instance.collection('menu_categories').where('categoryName', isEqualTo: selectedCategory).get();
                    if (query.docs.isNotEmpty) {
                      var docRef = query.docs.first.reference;
                      List existingItems = List.from(query.docs.first.get('items') ?? []);
                      existingItems.add(newItem);
                      await docRef.update({'items': existingItems});
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      setState(() {});
                    }
                  },
                  child: const Text('Add Item'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openEditDeleteDialog(BuildContext context, String catName, Map<String, dynamic> itemData) {
    final TextEditingController editNameController = TextEditingController(text: itemData['name']);
    final TextEditingController editDescController = TextEditingController(text: itemData['desc'] ?? '');
    final TextEditingController editPriceController = TextEditingController(text: itemData['price']?.toString() ?? '');
    final TextEditingController editRegPriceController = TextEditingController(text: itemData['regularPrice']?.toString() ?? '');
    final TextEditingController editMedPriceController = TextEditingController(text: itemData['mediumPrice']?.toString() ?? '');

    bool isMultiPrice = itemData.containsKey('regularPrice') || itemData.containsKey('mediumPrice') || catName.toLowerCase().contains('fries') || catName.toLowerCase().contains('pizza') || catName.toLowerCase().contains('speciality');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1A17),
          title: Text('Edit / Delete: ${itemData['name']}', style: const TextStyle(color: Color(0xFFF7B731))),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: editNameController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 10),
                TextField(controller: editDescController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 10),
                if (isMultiPrice) ...[
                  TextField(controller: editRegPriceController, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Regular Price (₹)', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 10),
                  TextField(controller: editMedPriceController, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Medium Price (₹)', border: OutlineInputBorder(), isDense: true)),
                ] else ...[
                  TextField(controller: editPriceController, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Price (₹)', border: OutlineInputBorder(), isDense: true)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              onPressed: () async {
                var query = await FirebaseFirestore.instance.collection('menu_categories').where('categoryName', isEqualTo: catName).get();
                if (query.docs.isNotEmpty) {
                  var docRef = query.docs.first.reference;
                  List existingItems = List.from(query.docs.first.get('items') ?? []);
                  existingItems.removeWhere((element) => element['name'] == itemData['name']);
                  await docRef.update({'items': existingItems});
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  setState(() {});
                }
              },
              child: const Text('Delete'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
              onPressed: () async {
                Map<String, dynamic> updatedItem = {
                  'name': editNameController.text.trim(),
                  'desc': editDescController.text.trim(),
                };
                if (isMultiPrice) {
                  updatedItem['regularPrice'] = double.tryParse(editRegPriceController.text.trim()) ?? 0.0;
                  updatedItem['mediumPrice'] = double.tryParse(editMedPriceController.text.trim()) ?? 0.0;
                } else {
                  updatedItem['price'] = double.tryParse(editPriceController.text.trim()) ?? 0.0;
                }

                var query = await FirebaseFirestore.instance.collection('menu_categories').where('categoryName', isEqualTo: catName).get();
                if (query.docs.isNotEmpty) {
                  var docRef = query.docs.first.reference;
                  List existingItems = List.from(query.docs.first.get('items') ?? []);
                  int index = existingItems.indexWhere((element) => element['name'] == itemData['name']);
                  if (index != -1) {
                    existingItems[index] = updatedItem;
                    await docRef.update({'items': existingItems});
                  }
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  setState(() {});
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void updatePaymentStatus(String docId, String newPaymentStatus) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(docId).update({'paymentStatus': newPaymentStatus});
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  void deleteOrder(String docId) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Order', style: TextStyle(color: Color(0xFFF7B731))),
        content: const Text('Kya aap is order ko permanently delete karna chahte hain?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance.collection('orders').doc(docId).delete();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _logout(BuildContext context) {
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const StaffLoginHomeScreen()), (route) => false);
  }

  void prepareOrderForm({DocumentSnapshot? doc}) {
    setState(() {
      editingOrderDoc = doc;
      searchQuery = '';
      searchController.clear();
      if (doc != null) {
        nameController.text = doc.get('customerName') ?? '';
        List items = doc.get('items') ?? [];
        tempCart = items.map((e) {
          var m = Map<String, dynamic>.from(e);
          m['isDone'] = true;
          return m;
        }).toList();
        currentView = 'NewOrder';
      } else {
        nameController.clear();
        tempCart.clear();
        currentView = 'NewOrder';
      }
    });
  }

  double get calcTempTotal {
    double t = 0;
    for (var item in tempCart) {
      t += ((item['price'] ?? 0.0) * (item['qty'] ?? 1));
    }
    return t;
  }

  bool _isMultiPriceCategory(String categoryName) {
    String lower = categoryName.toLowerCase();
    return lower.contains('pizza') || lower.contains('fries') || lower.contains('signature') || lower.contains('exotic') || lower.contains('speciality');
  }

  void addToTempCart(Map<String, dynamic> item, String categoryName) {
    setState(() {
      String itemName = item['name'];
      bool isMultiPrice = _isMultiPriceCategory(categoryName);
      double itemPrice = 0.0;
      String itemSize = 'Standard';

      double regPrice = (item['regularPrice'] ?? item['price'] ?? 0.0).toDouble();
      double medPrice = (item['mediumPrice'] ?? item['regularPrice'] ?? item['price'] ?? 0.0).toDouble();

      if (isMultiPrice && (item.containsKey('regularPrice') || item.containsKey('mediumPrice'))) {
        itemSize = selectedSize;
        if (selectedSize == 'Regular') {
          itemPrice = regPrice;
        } else {
          itemPrice = medPrice > 0 ? medPrice : regPrice;
        }
      } else {
        itemPrice = (item['price'] ?? regPrice).toDouble();
        itemSize = 'Standard';
      }

      var existingIndex = tempCart.indexWhere((element) => element['name'] == itemName && element['size'] == itemSize);
      if (existingIndex != -1) {
        tempCart[existingIndex]['qty'] += 1;
        tempCart[existingIndex]['isDone'] = false;
      } else {
        tempCart.add({'name': itemName, 'price': itemPrice, 'size': itemSize, 'qty': 1, 'isDone': false});
      }
    });
  }

  void updateQty(int index, int change) {
    setState(() {
      tempCart[index]['qty'] += change;
      tempCart[index]['isDone'] = false;
      if (tempCart[index]['qty'] <= 0) tempCart.removeAt(index);
    });
  }

  void saveOrderToFirebase() async {
    String name = nameController.text.trim();
    if (name.isEmpty || tempCart.isEmpty) return;

    if (editingOrderDoc == null) {
      List initialItems = tempCart.map((e) => {...e, 'isDone': false}).toList();
      await FirebaseFirestore.instance.collection('orders').add({
        'deviceId': 'counter_manager_${DateTime.now().millisecondsSinceEpoch}',
        'customerName': name,
        'items': initialItems,
        'totalPrice': calcTempTotal,
        'status': 'pending',
        'kitchenStatus': 'pending',
        'paymentStatus': 'pending',
        'hasNewItemsAdded': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      bool hasAnyNew = tempCart.any((e) => (e['isDone'] ?? false) == false);

      await FirebaseFirestore.instance.collection('orders').doc(editingOrderDoc!.id).update({
        'customerName': name,
        'items': tempCart,
        'totalPrice': calcTempTotal,
        'status': 'pending',
        'kitchenStatus': 'pending',
        'hasNewItemsAdded': hasAnyNew,
      });
    }

    setState(() {
      currentView = 'Dashboard';
      editingOrderDoc = null;
      nameController.clear();
      tempCart.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    String appBarTitle = 'Manager Dashboard';
    if (currentView == 'CompletedOrders') appBarTitle = 'Completed Orders History';
    if (currentView == 'NewOrder') appBarTitle = 'New Counter Order';
    if (currentView == 'ManageMenu') appBarTitle = 'Manage Menu';
    if (currentView == 'SalesReports') appBarTitle = 'Sales Reports';

    return Scaffold(
      backgroundColor: const Color(0xFF141211),
      appBar: AppBar(
        title: Text(appBarTitle, style: const TextStyle(color: Color(0xFFF7B731), fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1A17),
        iconTheme: const IconThemeData(color: Color(0xFFF7B731)),
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF1A1614),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
              color: const Color(0xFF26211D),
              child: Row(
                children: [
                  const FlamyWoodOvenLogo(size: 40),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('FLAMY WOOD', style: TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.w900, fontSize: 16)),
                      Text('Manager Portal', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined, color: Color(0xFFE65C00)),
              title: const Text('Live Active Orders', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); setState(() => currentView = 'Dashboard'); },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline, color: Colors.green),
              title: const Text('Completed Orders History', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onTap: () { Navigator.pop(context); setState(() => currentView = 'CompletedOrders'); },
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline, color: Color(0xFFE65C00)),
              title: const Text('New Counter Order', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); prepareOrderForm(); },
            ),
            ListTile(
              leading: const Icon(Icons.restaurant_menu, color: Color(0xFFE65C00)),
              title: const Text('Manage Menu (Edit/Delete)', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); setState(() => currentView = 'ManageMenu'); },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart, color: Color(0xFFF7B731)),
              title: const Text('Sales Reports', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); setState(() => currentView = 'SalesReports'); },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined, color: Colors.blueAccent),
              title: const Text('Upload Default Menu', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); _uploadMenuToFirebase(context); },
            ),
            const Divider(color: Color(0xFF2C2520)),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Logout', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(context); _logout(context); },
            ),
          ],
        ),
      ),
      body: currentView == 'Dashboard'
          ? _buildDashboardBody()
          : (currentView == 'CompletedOrders'
              ? _buildCompletedOrdersBody()
              : (currentView == 'ManageMenu'
                  ? _buildManageMenuBody()
                  : (currentView == 'SalesReports' ? _buildSalesReportsBody() : _buildOrderFormBody()))),
    );
  }

  // --- 1. LIVE ACTIVE DASHBOARD BODY (TODAY ONLY) ---
  Widget _buildDashboardBody() {
    DateTime now = DateTime.now();
    DateTime startOfToday = DateTime(now.year, now.month, now.day);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)));
        var todayOrders = snapshot.data!.docs;

        var todayActiveOrders = todayOrders.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          return (data['status'] ?? 'pending') != 'completed';
        }).toList();

        double totalCollected = 0.0;
        double cashSales = 0.0;
        double upiSales = 0.0;
        int unpaidBillsCount = 0;

        for (var doc in todayOrders) {
          var data = doc.data() as Map<String, dynamic>;
          double price = (data['totalPrice'] ?? 0.0).toDouble();
          String paymentStatus = data['paymentStatus'] ?? 'pending';

          if (paymentStatus == 'paid_cash') {
            totalCollected += price;
            cashSales += price;
          } else if (paymentStatus == 'paid_upi') {
            totalCollected += price;
            upiSales += price;
          } else {
            unpaidBillsCount++;
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Today's Overview:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFF7B731))),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.2,
                children: [
                  _buildMetricCard('Total Collected', '₹${totalCollected.toInt()}', Colors.green, Icons.account_balance_wallet),
                  _buildMetricCard('Cash Sales', '₹${cashSales.toInt()}', const Color(0xFFF7B731), Icons.money),
                  _buildMetricCard('UPI Sales', '₹${upiSales.toInt()}', const Color(0xFFE65C00), Icons.qr_code_scanner),
                  _buildMetricCard('Unpaid Bills', '$unpaidBillsCount', Colors.redAccent, Icons.warning_amber_rounded),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Today's Active Orders:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFF7B731))),
                  TextButton.icon(
                    onPressed: () => setState(() => currentView = 'CompletedOrders'),
                    icon: const Icon(Icons.history, color: Colors.green, size: 18),
                    label: const Text('View Done Orders', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              todayActiveOrders.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40.0),
                        child: Text('Aaj ke din me koi active order baki nahi hai! 🔥', style: TextStyle(color: Colors.white38, fontSize: 15)),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: todayActiveOrders.length,
                      itemBuilder: (context, index) {
                        var orderDoc = todayActiveOrders[index];
                        var orderData = orderDoc.data() as Map<String, dynamic>;
                        List items = orderData['items'] ?? [];
                        String paymentStatus = orderData['paymentStatus'] ?? 'pending';
                        String kitchenStatus = orderData['status'] ?? orderData['kitchenStatus'] ?? 'pending';
                        double currentTotal = (orderData['totalPrice'] ?? 0.0).toDouble();
                        double? originalPrice = (orderData['originalPrice'] != null) ? (orderData['originalPrice']).toDouble() : null;

                        Color statusColor = const Color(0xFFE65C00);
                        if (kitchenStatus == 'preparing') statusColor = Colors.amber;
                        if (kitchenStatus == 'ready') statusColor = Colors.green;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1A17),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF2C2520)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      orderData['customerName'] ?? 'Unknown',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                    ),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: statusColor),
                                          ),
                                          child: Text(
                                            'Status: ${kitchenStatus.toUpperCase()}',
                                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 20),
                                          onPressed: () => prepareOrderForm(doc: orderDoc),
                                          tooltip: 'Edit / Repeat',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                          onPressed: () => deleteOrder(orderDoc.id),
                                          tooltip: 'Delete',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const Divider(color: Color(0xFF2C2520), height: 16),
                                ...items.asMap().entries.map<Widget>((entry) {
                                  int itemIdx = entry.key;
                                  var item = entry.value;
                                  bool isDone = item['isDone'] ?? false;

                                  return InkWell(
                                    onTap: () => confirmAndToggleItem(context, orderDoc.id, items, itemIdx),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                isDone ? Icons.check_box : Icons.check_box_outline_blank,
                                                color: isDone ? Colors.green : Colors.grey,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '${item['name']} (${item['size'] ?? 'Standard'})',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                                                  color: isDone ? Colors.green : Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text('₹${item['price']} x ${item['qty']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFF7B731))),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                                const Divider(color: Color(0xFF2C2520), height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Payment Mode Options
                                    Row(
                                      children: [
                                        const Text('Payment: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                                        paymentStatus == 'paid_cash'
                                            ? const Chip(label: Text('Paid (Cash)', style: TextStyle(fontSize: 11, color: Colors.white)), backgroundColor: Colors.green, visualDensity: VisualDensity.compact)
                                            : paymentStatus == 'paid_upi'
                                                ? const Chip(label: Text('Paid (UPI)', style: TextStyle(fontSize: 11, color: Colors.white)), backgroundColor: Color(0xFFE65C00), visualDensity: VisualDensity.compact)
                                                : Row(
                                                    children: [
                                                      ElevatedButton(
                                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(55, 26)),
                                                        onPressed: () => updatePaymentStatus(orderDoc.id, 'paid_cash'),
                                                        child: const Text('Cash', style: TextStyle(fontSize: 10)),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      ElevatedButton(
                                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white, minimumSize: const Size(55, 26)),
                                                        onPressed: () => updatePaymentStatus(orderDoc.id, 'paid_upi'),
                                                        child: const Text('UPI', style: TextStyle(fontSize: 10)),
                                                      ),
                                                    ],
                                                  ),
                                      ],
                                    ),

                                    // Discount Button + Final Total + Compact Done Button
                                    Row(
                                      children: [
                                        // Dedicated Highlighted Discount & Edit Button
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF2B241F),
                                            foregroundColor: const Color(0xFFF7B731),
                                            side: const BorderSide(color: Color(0xFFF7B731), width: 1.2),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            minimumSize: const Size(0, 30),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            elevation: 0,
                                          ),
                                          onPressed: () => _openDiscountPriceDialog(context, orderDoc.id, currentTotal, orderData['customerName'] ?? 'Customer'),
                                          icon: const Icon(Icons.discount_outlined, size: 14, color: Color(0xFFF7B731)),
                                          label: const Text('Discount', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 10),

                                        // Total Price (Shows strikethrough if discounted)
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            if (originalPrice != null && originalPrice > currentTotal)
                                              Text(
                                                '₹${originalPrice.toInt()}',
                                                style: const TextStyle(fontSize: 11, color: Colors.white38, decoration: TextDecoration.lineThrough),
                                              ),
                                            Text(
                                              'Total: ₹${currentTotal.toInt()}',
                                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFFF7B731)),
                                            ),
                                          ],
                                        ),

                                        // Compact Done Button appears only after Payment is Paid
                                        if (paymentStatus == 'paid_cash' || paymentStatus == 'paid_upi') ...[
                                          const SizedBox(width: 10),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green.shade700,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              minimumSize: const Size(0, 30),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              elevation: 1,
                                            ),
                                            onPressed: () => markOrderAsFinalDone(context, orderDoc.id, orderData['customerName'] ?? 'Customer'),
                                            icon: const Icon(Icons.check, size: 15),
                                            label: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        );
      },
    );
  }

  // --- 2. COMPLETED ORDERS HISTORY (STABLE CARD WRAPPER) ---
  Widget _buildCompletedOrdersBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('status', isEqualTo: 'completed')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)));
        var completedOrders = snapshot.data!.docs;

        completedOrders.sort((a, b) {
          var dataA = a.data() as Map<String, dynamic>;
          var dataB = b.data() as Map<String, dynamic>;
          Timestamp? tA = (dataA['completedAt'] ?? dataA['createdAt']) as Timestamp?;
          Timestamp? tB = (dataB['completedAt'] ?? dataB['createdAt']) as Timestamp?;
          if (tA != null && tB != null) {
            return tB.compareTo(tA);
          }
          return 0;
        });

        if (completedOrders.isEmpty) {
          return const Center(
            child: Text('Abhi tak koi order Final Done nahi hua hai!', style: TextStyle(color: Colors.white38, fontSize: 16)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: completedOrders.length,
          itemBuilder: (context, index) {
            var orderDoc = completedOrders[index];
            var data = orderDoc.data() as Map<String, dynamic>;
            List items = data['items'] ?? [];
            String paymentStatus = data['paymentStatus'] ?? 'pending';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Card(
                color: const Color(0xFF1E1A17),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.green.withOpacity(0.3)),
                ),
                child: ExpansionTile(
                  collapsedIconColor: Colors.grey,
                  iconColor: Colors.green,
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green.withOpacity(0.15)),
                    child: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  ),
                  title: Text(data['customerName'] ?? 'Customer', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text('Total: ₹${data['totalPrice']} • Payment: ${paymentStatus.toUpperCase()}', style: const TextStyle(color: Color(0xFFF7B731), fontSize: 12, fontWeight: FontWeight.w600)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(color: Color(0xFF2C2520)),
                          ...items.map<Widget>((item) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('${item['name']} (${item['size'] ?? 'Standard'})', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                    Text('₹${item['price']} x ${item['qty']}', style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                              )),
                          const Divider(color: Color(0xFF2C2520)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Actions:', style: TextStyle(color: Colors.white38, fontSize: 12)),
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                onPressed: () => deleteOrder(orderDoc.id),
                                icon: const Icon(Icons.delete, size: 16),
                                label: const Text('Delete from History', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- 3. SALES REPORTS VIEW ---
  Widget _buildSalesReportsBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').orderBy('createdAt', descending: false).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)));
        var allOrders = snapshot.data!.docs;

        DateTime now = DateTime.now();
        var filteredOrders = allOrders.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          Timestamp? timestamp = data['createdAt'] as Timestamp?;
          if (timestamp == null) return false;
          DateTime orderDate = timestamp.toDate();

          if (salesFilterMode == 'Today') {
            return orderDate.year == now.year && orderDate.month == now.month && orderDate.day == now.day;
          } else if (salesFilterMode == 'Specific Date') {
            return orderDate.year == selectedDate.year && orderDate.month == selectedDate.month && orderDate.day == selectedDate.day;
          } else if (salesFilterMode == 'Month-wise') {
            String orderMonthYear = '${orderDate.year}-${orderDate.month.toString().padLeft(2, '0')}';
            return orderMonthYear == selectedMonthYear;
          }
          return false;
        }).toList();

        double totalCollected = 0.0;
        double cashSales = 0.0;
        double upiSales = 0.0;

        for (var doc in filteredOrders) {
          var data = doc.data() as Map<String, dynamic>;
          double price = (data['totalPrice'] ?? 0.0).toDouble();
          String paymentStatus = data['paymentStatus'] ?? 'pending';

          if (paymentStatus == 'paid_cash') {
            totalCollected += price;
            cashSales += price;
          } else if (paymentStatus == 'paid_upi') {
            totalCollected += price;
            upiSales += price;
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(color: const Color(0xFF1E1A17), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF2C2520))),
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sales Filter Mode:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF7B731), fontSize: 14)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: salesFilterMode,
                      dropdownColor: const Color(0xFF26211D),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'Today', child: Text('Today Sales')),
                        DropdownMenuItem(value: 'Specific Date', child: Text('Day-wise (Pick Date)')),
                        DropdownMenuItem(value: 'Month-wise', child: Text('Month-wise Sales')),
                      ],
                      onChanged: (val) => setState(() => salesFilterMode = val!),
                    ),
                    if (salesFilterMode == 'Specific Date') ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Date: ${selectedDate.toLocal().toString().split(' ')[0]}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                            onPressed: () async {
                              DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2025),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) setState(() => selectedDate = picked);
                            },
                            child: const Text('Pick Date', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ] else if (salesFilterMode == 'Month-wise') ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Month: $selectedMonthYear', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                          DropdownButton<String>(
                            value: selectedMonthYear,
                            dropdownColor: const Color(0xFF26211D),
                            style: const TextStyle(color: Colors.white),
                            items: ['2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10', '2026-11', '2026-12']
                                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                                .toList(),
                            onChanged: (val) => setState(() => selectedMonthYear = val!),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(color: const Color(0xFF1E1A17), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF2C2520))),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Revenue Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFF7B731))),
                    const Divider(color: Color(0xFF2C2520), height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Collected:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('₹${totalCollected.toInt()}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Cash Sales:', style: TextStyle(color: Colors.white70)),
                        Text('₹${cashSales.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF7B731))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('UPI Sales:', style: TextStyle(color: Colors.white70)),
                        Text('₹${upiSales.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65C00))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- 4. MANAGE MENU VIEW ---
  Widget _buildManageMenuBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('menu_categories').snapshots(),
      builder: (context, menuSnapshot) {
        if (!menuSnapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)));
        var categories = menuSnapshot.data!.docs;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                      onPressed: () => _openAddMenuItemDialog(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Item'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF26211D), foregroundColor: const Color(0xFFF7B731)),
                      onPressed: () => _openAddCategoryDialog(context),
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Add Category'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: categories.isEmpty
                  ? const Center(child: Text('No categories found.', style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: categories.length,
                      itemBuilder: (context, catIndex) {
                        var catDoc = categories[catIndex];
                        var catData = catDoc.data() as Map<String, dynamic>;
                        String catName = catData['categoryName'] ?? '';
                        List items = catData['items'] ?? [];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: Card(
                            color: const Color(0xFF1E1A17),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Color(0xFF2C2520)),
                            ),
                            child: ExpansionTile(
                              iconColor: const Color(0xFFF7B731),
                              collapsedIconColor: Colors.grey,
                              title: Text(catName, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF7B731), fontSize: 15)),
                              subtitle: Text('${items.length} items', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                              children: items.map<Widget>((item) {
                                var regPrice = item['regularPrice'];
                                var medPrice = item['mediumPrice'];
                                var stdPrice = item['price'];

                                String priceStr = '';
                                if (regPrice != null && medPrice != null) {
                                  priceStr = 'Reg: ₹$regPrice | Med: ₹$medPrice';
                                } else if (stdPrice != null) {
                                  priceStr = 'Price: ₹$stdPrice';
                                }

                                return ListTile(
                                  dense: true,
                                  title: Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                  subtitle: Text('$priceStr\n${item['desc'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                                  isThreeLine: true,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 20),
                                        onPressed: () => _openEditDeleteDialog(context, catName, item),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                        onPressed: () => _openEditDeleteDialog(context, catName, item),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  // --- 5. NEW COUNTER ORDER VIEW ---
  Widget _buildOrderFormBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('menu_categories').snapshots(),
      builder: (context, menuSnapshot) {
        List liveMenuCategories = restaurantMenuCategories;
        if (menuSnapshot.hasData && menuSnapshot.data!.docs.isNotEmpty) {
          liveMenuCategories = menuSnapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Customer Name / Table No', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Size:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF7B731))),
                  ChoiceChip(
                    label: const Text('Regular'),
                    selected: selectedSize == 'Regular',
                    selectedColor: const Color(0xFFE65C00),
                    backgroundColor: const Color(0xFF26211D),
                    onSelected: (selected) => setState(() => selectedSize = 'Regular'),
                  ),
                  ChoiceChip(
                    label: const Text('Medium'),
                    selected: selectedSize == 'Medium',
                    selectedColor: const Color(0xFFE65C00),
                    backgroundColor: const Color(0xFF26211D),
                    onSelected: (selected) => setState(() => selectedSize = 'Medium'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: searchController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Search Menu...', prefixIcon: Icon(Icons.search, color: Color(0xFFE65C00)), border: OutlineInputBorder(), isDense: true),
                onChanged: (val) => setState(() => searchQuery = val.toLowerCase().trim()),
              ),
              const Divider(color: Color(0xFF2C2520), height: 20),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: liveMenuCategories.length,
                itemBuilder: (context, catIndex) {
                  var category = liveMenuCategories[catIndex];
                  String catName = category['categoryName'] ?? '';
                  List items = category['items'] ?? [];

                  var filteredItems = items.where((item) {
                    if (searchQuery.isEmpty) return true;
                    return item['name'].toString().toLowerCase().contains(searchQuery);
                  }).toList();

                  if (filteredItems.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Text(catName, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF7B731), fontSize: 14)),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: filteredItems.map<Widget>((item) {
                          bool isSelected = tempCart.any((element) => element['name'] == item['name']);
                          var regP = item['regularPrice'];
                          var medP = item['mediumPrice'];
                          var stdP = item['price'];

                          String priceDisplay = '';
                          if (regP != null && medP != null) {
                            priceDisplay = '₹$regP/₹$medP';
                          } else if (stdP != null) {
                            priceDisplay = '₹$stdP';
                          }

                          return ActionChip(
                            label: Text('${item['name']} ($priceDisplay)', style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : const Color(0xFFF7B731))),
                            backgroundColor: isSelected ? const Color(0xFFE65C00) : const Color(0xFF26211D),
                            side: BorderSide(color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF382F2A)),
                            onPressed: () => addToTempCart(item, catName),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                    ],
                  );
                },
              ),
              const Divider(color: Color(0xFF2C2520), height: 20),
              const Text('Current Cart:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFF7B731))),
              const SizedBox(height: 8),
              tempCart.isEmpty
                  ? const Center(child: Text('No items added yet.', style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: tempCart.length,
                      itemBuilder: (context, idx) {
                        var cartItem = tempCart[idx];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: Card(
                            color: const Color(0xFF1E1A17),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: Color(0xFF2C2520)),
                            ),
                            child: ListTile(
                              title: Text('${cartItem['name']} (${cartItem['size']})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Text('₹${cartItem['price']} x ${cartItem['qty']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(icon: const Icon(Icons.remove, color: Color(0xFFE65C00)), onPressed: () => updateQty(idx, -1)),
                                  Text('${cartItem['qty']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  IconButton(icon: const Icon(Icons.add, color: Color(0xFFE65C00)), onPressed: () => updateQty(idx, 1)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                  onPressed: saveOrderToFirebase,
                  child: const Text('Place / Update Order 🔥', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1A17),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 14, backgroundColor: color.withOpacity(0.15), child: Icon(icon, color: color, size: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color), maxLines: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}