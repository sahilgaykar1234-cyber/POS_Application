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
  String currentView = 'Dashboard';
  DocumentSnapshot? editingOrderDoc;

  String salesFilterMode = 'Today';
  DateTime selectedDate = DateTime.now();
  String selectedMonthYear = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

  final TextEditingController nameController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';

  List<Map<String, dynamic>> tempCart = [];
  String selectedSize = 'Medium';

  void confirmAndToggleItem(BuildContext context, String docId, List currentItems, int itemIndex) {
    var item = currentItems[itemIndex];
    bool currentVal = item['isDone'] ?? false;
    String actionText = currentVal ? "unmark" : "ready (done) mark";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Item Status Confirmation'),
        content: Text('Kya aap "${item['name']}" ko $actionText karna chahte hain?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: currentVal ? Colors.orange : Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _toggleItemDoneStatus(docId, currentItems, itemIndex);
            },
            child: const Text('Yes, Confirm'),
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
      print("Error toggling item: $e");
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Poora menu successfully Firestore me upload ho gaya!')),
      );
      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading menu: $e')),
      );
    }
  }

  void _openAddCategoryDialog(BuildContext context) {
    final TextEditingController categoryNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add New Menu Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Category Name:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: categoryNameController,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'e.g. Burgers, Starters', isDense: true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.brown[700], foregroundColor: Colors.white),
              onPressed: () async {
                String catName = categoryNameController.text.trim();
                if (catName.isEmpty) return;

                try {
                  var existing = await FirebaseFirestore.instance
                      .collection('menu_categories')
                      .where('categoryName', isEqualTo: catName)
                      .get();

                  if (existing.docs.isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yeh category pehle se exist karti hai!')));
                    return;
                  }

                  await FirebaseFirestore.instance.collection('menu_categories').add({
                    'categoryName': catName,
                    'items': [],
                  });

                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Category "$catName" successfully ban gayi!')));
                } catch (e) {
                  print("Error: $e");
                }
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
              title: const Text('Add New Menu Item'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Select Category:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _openAddCategoryDialog(context);
                          },
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('New Category', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      items: categories.map((cat) {
                        return DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(fontSize: 13)));
                      }).toList(),
                      onChanged: (val) {
                        setStateDialog(() {
                          selectedCategory = val!;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('Item Name:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    TextField(controller: newItemNameController, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Item Name', isDense: true)),
                    const SizedBox(height: 12),
                    const Text('Description:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    TextField(controller: newItemDescController, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Description', isDense: true)),
                    const SizedBox(height: 12),
                    if (isMultiPriceCat) ...[
                      const Text('Regular Price (₹):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      TextField(controller: newItemRegularPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 12),
                      const Text('Medium Price (₹):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      TextField(controller: newItemMediumPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                    ] else ...[
                      const Text('Price (₹):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      TextField(controller: newItemPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
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
                      Navigator.pop(context);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Item "$name" add ho gaya!')));
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
          title: Text('Edit / Delete: ${itemData['name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Item Name:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                TextField(controller: editNameController, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 12),
                const Text('Description:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                TextField(controller: editDescController, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Description', isDense: true)),
                const SizedBox(height: 12),
                if (isMultiPrice) ...[
                  const Text('Regular Price (₹):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(controller: editRegPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 12),
                  const Text('Medium Price (₹):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(controller: editMedPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                ] else ...[
                  const Text('Price (₹):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(controller: editPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                var query = await FirebaseFirestore.instance.collection('menu_categories').where('categoryName', isEqualTo: catName).get();
                if (query.docs.isNotEmpty) {
                  var docRef = query.docs.first.reference;
                  List existingItems = List.from(query.docs.first.get('items') ?? []);
                  existingItems.removeWhere((element) => element['name'] == itemData['name']);
                  await docRef.update({'items': existingItems});
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item delete ho gaya!')));
                }
              },
              child: const Text('Delete'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.brown[700], foregroundColor: Colors.white),
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
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item update ho gaya!')));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment status updated to $newPaymentStatus!')));
    } catch (e) {
      print("Error updating payment: $e");
    }
  }

  void deleteOrder(String docId) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Order'),
        content: const Text('Kya aap is order ko permanently delete karna chahte hain?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance.collection('orders').doc(docId).delete();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order successfully delete ho gaya!')));
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
        itemPrice = (item['price'] ?? regPrice ?? 0.0).toDouble();
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
    if (currentView == 'NewOrder') appBarTitle = 'New Counter Order';
    if (currentView == 'ManageMenu') appBarTitle = 'Manage Menu Items';
    if (currentView == 'SalesReports') appBarTitle = 'Sales Reports & History';

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(appBarTitle, style: const TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: Colors.brown[700],
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: Colors.brown[800]),
              accountName: const Text('Manager Portal'),
              accountEmail: const Text('Surat Pizza Shop'),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Live Dashboard'),
              onTap: () { Navigator.pop(context); setState(() => currentView = 'Dashboard'); },
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('New Counter Order'),
              onTap: () { Navigator.pop(context); prepareOrderForm(); },
            ),
            ListTile(
              leading: const Icon(Icons.restaurant_menu),
              title: const Text('Manage Menu (Edit/Delete)'),
              onTap: () { Navigator.pop(context); setState(() => currentView = 'ManageMenu'); },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart, color: Colors.blue),
              title: const Text('Sales Reports (Day/Month)'),
              onTap: () { Navigator.pop(context); setState(() => currentView = 'SalesReports'); },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: const Text('Upload Default Menu'),
              onTap: () { Navigator.pop(context); _uploadMenuToFirebase(context); },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout'),
              onTap: () { Navigator.pop(context); _logout(context); },
            ),
          ],
        ),
      ),
      body: currentView == 'Dashboard'
          ? _buildDashboardBody()
          : (currentView == 'ManageMenu'
              ? _buildManageMenuBody()
              : (currentView == 'SalesReports' ? _buildSalesReportsBody() : _buildOrderFormBody())),
    );
  }

  Widget _buildDashboardBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .orderBy('createdAt', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var allOrders = snapshot.data!.docs;

        DateTime now = DateTime.now();
        var todayOrders = allOrders.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          Timestamp? timestamp = data['createdAt'] as Timestamp?;
          if (timestamp == null) return false;
          DateTime orderDate = timestamp.toDate();
          return orderDate.year == now.year && orderDate.month == now.month && orderDate.day == now.day;
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
              const Text("Today's Overview:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.brown)),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.2,
                children: [
                  _buildMetricCard('Total Collected', '₹$totalCollected', Colors.green, Icons.account_balance_wallet),
                  _buildMetricCard('Cash Sales', '₹$cashSales', Colors.blue, Icons.money),
                  _buildMetricCard('UPI Sales', '₹$upiSales', Colors.purple, Icons.qr_code_scanner),
                  _buildMetricCard('Unpaid Bills', '$unpaidBillsCount', Colors.orange, Icons.warning_amber_rounded),
                ],
              ),
              const SizedBox(height: 24),
              
              const Text("Today's Live Orders History:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.brown)),
              const SizedBox(height: 12),
              todayOrders.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40.0),
                        child: Text('Aaj ke din me koi order nahi hai abhi! (Sales: ₹0)', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: todayOrders.length,
                      itemBuilder: (context, index) {
                        var orderDoc = todayOrders[index];
                        var orderData = orderDoc.data() as Map<String, dynamic>;
                        List items = orderData['items'] ?? [];
                        String paymentStatus = orderData['paymentStatus'] ?? 'pending';
                        String kitchenStatus = orderData['status'] ?? orderData['kitchenStatus'] ?? 'pending';

                        Color statusColor = Colors.orange;
                        if (kitchenStatus == 'preparing') statusColor = Colors.blue;
                        if (kitchenStatus == 'ready') statusColor = Colors.green;
                        if (kitchenStatus == 'completed') statusColor = Colors.grey;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.brown),
                                    ),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.1),
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
                                          icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                          onPressed: () => prepareOrderForm(doc: orderDoc),
                                          tooltip: 'Edit / Repeat Order',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                          onPressed: () => deleteOrder(orderDoc.id),
                                          tooltip: 'Delete Order',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                                const Text('Ordered Items (Tap to toggle ready):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 6),
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
                                                size: 20,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '${item['name']} (${item['size'] ?? 'Standard'})',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                                                  color: isDone ? Colors.green[800] : Colors.black,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text('₹${item['price']} x ${item['qty']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                                const Divider(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Text('Payment: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        paymentStatus == 'paid_cash'
                                            ? const Chip(label: Text('Paid (Cash)', style: TextStyle(fontSize: 11, color: Colors.white)), backgroundColor: Colors.green, visualDensity: VisualDensity.compact)
                                            : paymentStatus == 'paid_upi'
                                                ? const Chip(label: Text('Paid (UPI)', style: TextStyle(fontSize: 11, color: Colors.white)), backgroundColor: Colors.purple, visualDensity: VisualDensity.compact)
                                                : Row(
                                                    children: [
                                                      ElevatedButton(
                                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(60, 28)),
                                                        onPressed: () => updatePaymentStatus(orderDoc.id, 'paid_cash'),
                                                        child: const Text('Cash', style: TextStyle(fontSize: 11)),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      ElevatedButton(
                                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, minimumSize: const Size(60, 28)),
                                                        onPressed: () => updatePaymentStatus(orderDoc.id, 'paid_upi'),
                                                        child: const Text('UPI', style: TextStyle(fontSize: 11)),
                                                      ),
                                                    ],
                                                  ),
                                      ],
                                    ),
                                    Text('Total: ₹${orderData['totalPrice']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green)),
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

  Widget _buildSalesReportsBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').orderBy('createdAt', descending: false).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
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
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Select Sales Filter:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown, fontSize: 14)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: salesFilterMode,
                        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'Today', child: Text('Today Sales', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'Specific Date', child: Text('Day-wise (Pick Date)', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'Month-wise', child: Text('Month-wise Sales', style: TextStyle(fontSize: 13))),
                        ],
                        onChanged: (val) {
                          setState(() {
                            salesFilterMode = val!;
                          });
                        },
                      ),
                      if (salesFilterMode == 'Specific Date') ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Date: ${selectedDate.toLocal().toString().split(' ')[0]}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.brown[700], foregroundColor: Colors.white, minimumSize: const Size(100, 32)),
                              onPressed: () async {
                                DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2025),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setState(() {
                                    selectedDate = picked;
                                  });
                                }
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
                            Text('Month: $selectedMonthYear', style: const TextStyle(fontWeight: FontWeight.bold)),
                            DropdownButton<String>(
                              value: selectedMonthYear,
                              items: ['2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10', '2026-11', '2026-12']
                                  .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13))))
                                  .toList(),
                              onChanged: (val) {
                                setState(() {
                                  selectedMonthYear = val!;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Card(
                elevation: 3,
                color: Colors.brown[50],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Sales Summary:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.brown)),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Amount:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          Text('₹$totalCollected', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Cash Sales:', style: TextStyle(fontSize: 14)),
                          Text('₹$cashSales', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blue)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('UPI Sales:', style: TextStyle(fontSize: 14)),
                          Text('₹$upiSales', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.purple)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildManageMenuBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('menu_categories').snapshots(),
      builder: (context, menuSnapshot) {
        if (!menuSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        var categories = menuSnapshot.data!.docs;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
                      onPressed: () => _openAddMenuItemDialog(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add New Item'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.brown[700], foregroundColor: Colors.white),
                      onPressed: () => _openAddCategoryDialog(context),
                      icon: const Icon(Icons.create_new_folder),
                      label: const Text('Add Category'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: categories.isEmpty
                  ? const Center(child: Text('No menu items found. Upload default menu.'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: categories.length,
                      itemBuilder: (context, catIndex) {
                        var catDoc = categories[catIndex];
                        var catData = catDoc.data() as Map<String, dynamic>;
                        String catName = catData['categoryName'] ?? '';
                        List items = catData['items'] ?? [];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          child: ExpansionTile(
                            title: Text(catName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown, fontSize: 15)),
                            subtitle: Text('${items.length} items available', style: const TextStyle(fontSize: 12)),
                            children: items.map<Widget>((item) {
                              var regPrice = item['regularPrice'];
                              var medPrice = item['mediumPrice'];
                              var stdPrice = item['price'];

                              String priceStr = '';
                              if (regPrice != null && medPrice != null) {
                                priceStr = 'Reg: ₹$regPrice | Med: ₹$medPrice';
                              } else if (stdPrice != null) {
                                priceStr = 'Price: ₹$stdPrice';
                              } else {
                                priceStr = 'Price: ₹0';
                              }

                              return ListTile(
                                dense: true,
                                title: Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('$priceStr\n${item['desc'] ?? ''}', style: const TextStyle(fontSize: 11)),
                                isThreeLine: true,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                      onPressed: () => _openEditDeleteDialog(context, catName, item),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                      onPressed: () => _openEditDeleteDialog(context, catName, item),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
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
                decoration: const InputDecoration(labelText: 'Customer Name / Table No', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Size Option:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
                  ChoiceChip(
                    label: const Text('Regular', style: TextStyle(fontSize: 12)),
                    selected: selectedSize == 'Regular',
                    onSelected: (selected) => setState(() => selectedSize = 'Regular'),
                  ),
                  ChoiceChip(
                    label: const Text('Medium', style: TextStyle(fontSize: 12)),
                    selected: selectedSize == 'Medium',
                    onSelected: (selected) => setState(() => selectedSize = 'Medium'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              TextField(
                controller: searchController,
                decoration: const InputDecoration(labelText: 'Search Menu Item...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
                onChanged: (val) => setState(() => searchQuery = val.toLowerCase().trim()),
              ),
              const Divider(height: 18),
              const Text('Select Menu Items:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.brown)),
              const SizedBox(height: 4),
              
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
                        child: Text(catName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 14)),
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
                          } else if (regP != null) {
                            priceDisplay = '₹$regP';
                          } else {
                            priceDisplay = '₹0';
                          }

                          return ActionChip(
                            label: Text('${item['name']} ($priceDisplay)', style: const TextStyle(fontSize: 12)),
                            backgroundColor: isSelected ? Colors.orange.shade200 : Colors.orange.shade50,
                            onPressed: () => addToTempCart(item, catName),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 6),
                    ],
                  );
                },
              ),
              const Divider(thickness: 2),
              const Text('Current Cart:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.brown)),
              const SizedBox(height: 8),
              tempCart.isEmpty
                  ? const Center(child: Text('No items added yet.', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: tempCart.length,
                      itemBuilder: (context, idx) {
                        var cartItem = tempCart[idx];
                        return Card(
                          child: ListTile(
                            title: Text('${cartItem['name']} (${cartItem['size']})'),
                            subtitle: Text('₹${cartItem['price']} x ${cartItem['qty']}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => updateQty(idx, -1)),
                                Text('${cartItem['qty']}'),
                                IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.green), onPressed: () => updateQty(idx, 1)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 45)),
                onPressed: saveOrderToFirebase,
                child: const Text('Place / Update Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, spreadRadius: 1)],
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 14, backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color, size: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color), maxLines: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}