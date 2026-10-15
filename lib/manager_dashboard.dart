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
  final TextEditingController specialRequestController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';

  List<Map<String, dynamic>> tempCart = [];
  String selectedSize = 'Medium';

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
                  const Text('Final Payable Amount (Editable):', style: TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold, fontSize: 12)),
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
                      SnackBar(content: Text('Bill updated! New Total: ₹${updatedPrice.toInt()}'), backgroundColor: Colors.green),
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
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const CustomerCartScreen()),
      (route) => false,
    );
  }

  void prepareOrderForm({DocumentSnapshot? doc}) {
    setState(() {
      editingOrderDoc = doc;
      searchQuery = '';
      searchController.clear();
      if (doc != null) {
        nameController.text = doc.get('customerName') ?? '';
        specialRequestController.text = doc.get('specialRequest') ?? '';
        List items = doc.get('items') ?? [];
        tempCart = items.map((e) {
          var m = Map<String, dynamic>.from(e);
          m['isDone'] = e['isDone'] ?? false;
          return m;
        }).toList();
        currentView = 'NewOrder';
      } else {
        nameController.clear();
        specialRequestController.clear();
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
        itemPrice = selectedSize == 'Regular' ? regPrice : (medPrice > 0 ? medPrice : regPrice);
      } else {
        itemPrice = (item['price'] ?? regPrice).toDouble();
        itemSize = 'Standard';
      }

      var existingIndex = tempCart.indexWhere((element) {
        return element['name'] == itemName && element['size'] == itemSize;
      });

      if (existingIndex != -1) {
        tempCart[existingIndex]['qty'] += 1;
      } else {
        tempCart.add({
          'name': itemName,
          'price': itemPrice,
          'size': itemSize,
          'qty': 1,
          'isDone': false
        });
      }
    });
  }

  void updateQty(int index, int change) {
    setState(() {
      tempCart[index]['qty'] += change;
      if (tempCart[index]['qty'] <= 0) tempCart.removeAt(index);
    });
  }

  void saveOrderToFirebase() async {
    String name = nameController.text.trim();
    String note = specialRequestController.text.trim();
    if (name.isEmpty || tempCart.isEmpty) return;

    if (editingOrderDoc == null) {
      List initialItems = tempCart.map((e) => {...e, 'isDone': false}).toList();
      await FirebaseFirestore.instance.collection('orders').add({
        'deviceId': 'counter_manager_${DateTime.now().millisecondsSinceEpoch}',
        'customerName': name,
        'specialRequest': note,
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
        'specialRequest': note,
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
      specialRequestController.clear();
      tempCart.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    String appBarTitle = 'Manager Dashboard';
    if (currentView == 'CompletedOrders') appBarTitle = 'Completed Orders History';
    if (currentView == 'NewOrder') appBarTitle = editingOrderDoc != null ? 'Edit Order' : 'New Counter Order';
    if (currentView == 'SalesReports') appBarTitle = 'Sales Reports';

    return PopScope(
      canPop: currentView == 'Dashboard',
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (currentView != 'Dashboard') {
          setState(() {
            currentView = 'Dashboard';
            editingOrderDoc = null;
          });
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF141211),
        appBar: AppBar(
          title: Text(appBarTitle, style: const TextStyle(color: Color(0xFFF7B731), fontSize: 18, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E1A17),
          iconTheme: const IconThemeData(color: Color(0xFFF7B731)),
          leading: currentView != 'Dashboard'
              ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFFF7B731)),
                  tooltip: 'Back to Dashboard',
                  onPressed: () {
                    setState(() {
                      currentView = 'Dashboard';
                      editingOrderDoc = null;
                    });
                  },
                )
              : null,
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
                : (currentView == 'SalesReports' ? _buildSalesReportsBody() : _buildOrderFormBody())),
      ),
    );
  }

  // --- 1. LIVE ACTIVE DASHBOARD BODY ---
  Widget _buildDashboardBody() {
    DateTime now = DateTime.now();
    DateTime startOfToday = DateTime(now.year, now.month, now.day);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)));
        }

        var allDocs = snapshot.data!.docs;

        var todayOrders = allDocs.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          Timestamp? t = data['createdAt'] as Timestamp?;
          if (t == null) return false;
          return t.toDate().isAfter(startOfToday);
        }).toList();

        var todayActiveOrders = todayOrders.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          return (data['status'] ?? 'pending') != 'completed';
        }).toList();

        todayActiveOrders.sort((a, b) {
          var dataA = a.data() as Map<String, dynamic>;
          var dataB = b.data() as Map<String, dynamic>;
          Timestamp? tA = dataA['createdAt'] as Timestamp?;
          Timestamp? tB = dataB['createdAt'] as Timestamp?;
          if (tA != null && tB != null) return tB.compareTo(tA);
          return 0;
        });

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
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Today's Overview", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFF7B731))),
                  Text(
                    '${todayOrders.length} orders total',
                    style: const TextStyle(fontSize: 12, color: Colors.white38, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 2.8,
                children: [
                  _buildMetricCard('Collected', '₹${totalCollected.toInt()}', Colors.green, Icons.account_balance_wallet_outlined),
                  _buildMetricCard('Cash', '₹${cashSales.toInt()}', const Color(0xFFF7B731), Icons.payments_outlined),
                  _buildMetricCard('UPI', '₹${upiSales.toInt()}', const Color(0xFFE65C00), Icons.qr_code_2),
                  _buildMetricCard('Unpaid Bills', '$unpaidBillsCount', unpaidBillsCount > 0 ? Colors.redAccent : Colors.grey, Icons.pending_actions),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text("Active Orders", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFF7B731))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65C00).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${todayActiveOrders.length}',
                          style: const TextStyle(color: Color(0xFFE65C00), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () => setState(() => currentView = 'CompletedOrders'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 6.0),
                      child: Row(
                        children: const [
                          Icon(Icons.history, color: Colors.green, size: 16),
                          SizedBox(width: 4),
                          Text('Done Orders', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              todayActiveOrders.isEmpty
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 40),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1A17),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF2C2520)),
                        ),
                        child: Column(
                          children: const [
                            Icon(Icons.check_circle_outline, color: Colors.green, size: 36),
                            SizedBox(height: 8),
                            Text('Sabhi orders ready / settle ho chuke hain! 🔥', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
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
                        String specialRequest = orderData['specialRequest'] ?? '';
                        double currentTotal = (orderData['totalPrice'] ?? 0.0).toDouble();
                        double? originalPrice = (orderData['originalPrice'] != null) ? (orderData['originalPrice']).toDouble() : null;

                        Color statusColor = const Color(0xFFE65C00);
                        if (kitchenStatus == 'preparing') statusColor = Colors.amber;
                        if (kitchenStatus == 'ready') statusColor = Colors.green;

                        bool isPaid = paymentStatus == 'paid_cash' || paymentStatus == 'paid_upi';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B1715),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF2C2520)),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          const Icon(Icons.person_pin, color: Color(0xFFF7B731), size: 18),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              orderData['customerName'] ?? 'Unknown',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: statusColor.withOpacity(0.8), width: 1),
                                          ),
                                          child: Text(
                                            kitchenStatus.toUpperCase(),
                                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 19),
                                          onPressed: () => prepareOrderForm(doc: orderDoc),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          tooltip: 'Edit Order',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 19),
                                          onPressed: () => deleteOrder(orderDoc.id),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          tooltip: 'Delete',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              if (specialRequest.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3B2A15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFF7B731).withOpacity(0.6)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.note_alt, color: Color(0xFFF7B731), size: 14),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Note: $specialRequest',
                                            style: const TextStyle(color: Color(0xFFF7B731), fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],

                              const Divider(color: Color(0xFF26211E), height: 1),

                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                child: Column(
                                  children: items.asMap().entries.map<Widget>((entry) {
                                    int itemIdx = entry.key;
                                    var item = entry.value;
                                    bool isDone = item['isDone'] ?? false;

                                    return InkWell(
                                      onTap: () => confirmAndToggleItem(context, orderDoc.id, items, itemIdx),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                                        child: Row(
                                          children: [
                                            Icon(
                                              isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                              color: isDone ? Colors.green : Colors.white38,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${item['name']} (${item['size'] ?? 'Standard'})',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                                                  color: isDone ? Colors.greenAccent : Colors.white,
                                                  decoration: isDone ? TextDecoration.lineThrough : null,
                                                  decorationColor: Colors.greenAccent,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '₹${item['price']} x ${item['qty']}',
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFF7B731)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),

                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF221D1A),
                                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const Text('Payment: ', style: TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.bold)),
                                            const SizedBox(width: 4),
                                            if (paymentStatus == 'paid_cash')
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green)),
                                                child: const Text('PAID (CASH)', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                                              )
                                            else if (paymentStatus == 'paid_upi')
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(color: const Color(0xFFE65C00).withOpacity(0.2), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE65C00))),
                                                child: const Text('PAID (UPI)', style: TextStyle(color: Color(0xFFE65C00), fontSize: 10, fontWeight: FontWeight.bold)),
                                              )
                                            else
                                              Row(
                                                children: [
                                                  InkWell(
                                                    onTap: () => updatePaymentStatus(orderDoc.id, 'paid_cash'),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(color: Colors.green.shade800, borderRadius: BorderRadius.circular(6)),
                                                      child: const Text('Cash', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  InkWell(
                                                    onTap: () => updatePaymentStatus(orderDoc.id, 'paid_upi'),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(color: const Color(0xFFE65C00), borderRadius: BorderRadius.circular(6)),
                                                      child: const Text('UPI', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                        InkWell(
                                          onTap: () => _openDiscountPriceDialog(context, orderDoc.id, currentTotal, orderData['customerName'] ?? 'Customer'),
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2C241F),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFFF7B731).withOpacity(0.7)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: const [
                                                Icon(Icons.discount_outlined, color: Color(0xFFF7B731), size: 13),
                                                SizedBox(width: 4),
                                                Text('Discount', style: TextStyle(color: Color(0xFFF7B731), fontSize: 11, fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Row(
                                          children: [
                                            const Text('Total: ', style: TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w600)),
                                            if (originalPrice != null && originalPrice > currentTotal) ...[
                                              Text(
                                                '₹${originalPrice.toInt()} ',
                                                style: const TextStyle(fontSize: 11, color: Colors.white38, decoration: TextDecoration.lineThrough),
                                              ),
                                            ],
                                            Text(
                                              '₹${currentTotal.toInt()}',
                                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFFF7B731)),
                                            ),
                                          ],
                                        ),
                                        if (isPaid)
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green.shade700,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                              minimumSize: const Size(0, 32),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              elevation: 1,
                                            ),
                                            onPressed: () => markOrderAsFinalDone(context, orderDoc.id, orderData['customerName'] ?? 'Customer'),
                                            icon: const Icon(Icons.check, size: 15),
                                            label: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                          )
                                        else
                                          const Text(
                                            'Payment Pending',
                                            style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
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
    );
  }

  // --- 2. COMPLETED ORDERS HISTORY ---
  Widget _buildCompletedOrdersBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)));
        var allDocs = snapshot.data!.docs;

        var completedOrders = allDocs.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          return (data['status'] ?? '') == 'completed';
        }).toList();

        completedOrders.sort((a, b) {
          var dataA = a.data() as Map<String, dynamic>;
          var dataB = b.data() as Map<String, dynamic>;
          Timestamp? tA = (dataA['completedAt'] ?? dataA['createdAt']) as Timestamp?;
          Timestamp? tB = (dataB['completedAt'] ?? dataB['createdAt']) as Timestamp?;
          if (tA != null && tB != null) return tB.compareTo(tA);
          return 0;
        });

        if (completedOrders.isEmpty) {
          return const Center(
            child: Text('Abhi tak koi order Final Done nahi hua hai!', style: TextStyle(color: Colors.white38, fontSize: 16)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(14.0),
          itemCount: completedOrders.length,
          itemBuilder: (context, index) {
            var orderDoc = completedOrders[index];
            var data = orderDoc.data() as Map<String, dynamic>;
            List items = data['items'] ?? [];
            String paymentStatus = data['paymentStatus'] ?? 'pending';

            double finalTotal = (data['totalPrice'] ?? 0.0).toDouble();
            double? originalPrice = (data['originalPrice'] != null) ? (data['originalPrice']).toDouble() : null;
            double discountGiven = (data['discountGiven'] != null)
                ? (data['discountGiven']).toDouble()
                : (originalPrice != null && originalPrice > finalTotal ? originalPrice - finalTotal : 0.0);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Card(
                color: const Color(0xFF1E1A17),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.green.withOpacity(0.3)),
                ),
                child: ExpansionTile(
                  collapsedIconColor: Colors.grey,
                  iconColor: Colors.green,
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green.withOpacity(0.15)),
                    child: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  ),
                  title: Text(
                    data['customerName'] ?? 'Customer',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 3.0),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        Text(
                          'Total: ₹${finalTotal.toInt()}',
                          style: const TextStyle(color: Color(0xFFF7B731), fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                        if (discountGiven > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.redAccent, width: 0.8),
                            ),
                            child: Text(
                              '₹${discountGiven.toInt()} OFF',
                              style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        Text(
                          '• ${paymentStatus.toUpperCase()}',
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
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
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF26211D),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF382F2A)),
                            ),
                            child: Column(
                              children: [
                                if (discountGiven > 0 && originalPrice != null) ...[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Items Subtotal:', style: TextStyle(color: Colors.white60, fontSize: 12)),
                                      Text('₹${originalPrice.toInt()}', style: const TextStyle(color: Colors.white70, fontSize: 12, decoration: TextDecoration.lineThrough)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Discount Given:', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                      Text('- ₹${discountGiven.toInt()}', style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const Divider(color: Color(0xFF382F2A), height: 12),
                                ],
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Net Paid (Tally):', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                    Text('₹${finalTotal.toInt()}', style: const TextStyle(color: Colors.greenAccent, fontSize: 15, fontWeight: FontWeight.w900)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Actions:', style: TextStyle(color: Colors.white38, fontSize: 12)),
                              TextButton.icon(
                                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                onPressed: () => deleteOrder(orderDoc.id),
                                icon: const Icon(Icons.delete, size: 15),
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
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
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
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(color: const Color(0xFF1E1A17), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF2C2520))),
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sales Filter Mode:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF7B731), fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: salesFilterMode,
                      dropdownColor: const Color(0xFF26211D),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'Today', child: Text('Today Sales')),
                        DropdownMenuItem(value: 'Specific Date', child: Text('Day-wise (Pick Date)')),
                        DropdownMenuItem(value: 'Month-wise', child: Text('Month-wise Sales')),
                      ],
                      onChanged: (val) => setState(() => salesFilterMode = val!),
                    ),
                    if (salesFilterMode == 'Specific Date') ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Date: ${selectedDate.toLocal().toString().split(' ')[0]}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
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
                            child: const Text('Pick Date', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ] else if (salesFilterMode == 'Month-wise') ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Month: $selectedMonthYear', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
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
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(color: const Color(0xFF1E1A17), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF2C2520))),
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Revenue Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFF7B731))),
                    const Divider(color: Color(0xFF2C2520), height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Collected:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('₹${totalCollected.toInt()}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Cash Sales:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Text('₹${cashSales.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF7B731), fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('UPI Sales:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Text('₹${upiSales.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65C00), fontSize: 13)),
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

  // --- 4. NEW COUNTER ORDER VIEW (ONLY SIZE + DESCRIPTION BOX) ---
  Widget _buildOrderFormBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('menu_categories').snapshots(),
      builder: (context, menuSnapshot) {
        List liveMenuCategories = restaurantMenuCategories;
        if (menuSnapshot.hasData && menuSnapshot.data!.docs.isNotEmpty) {
          liveMenuCategories = menuSnapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Customer Name / Table No', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 10),

              // Description / Cooking Notes Box
              TextField(
                controller: specialRequestController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Special Cooking Request / Notes (Optional)',
                  hintText: 'e.g., extra spicy, without onion, well done...',
                  prefixIcon: Icon(Icons.note_alt_outlined, color: Color(0xFFF7B731), size: 18),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),

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
              const SizedBox(height: 10),

              TextField(
                controller: searchController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Search Menu...', prefixIcon: Icon(Icons.search, color: Color(0xFFE65C00)), border: OutlineInputBorder(), isDense: true),
                onChanged: (val) => setState(() => searchQuery = val.toLowerCase().trim()),
              ),
              const Divider(color: Color(0xFF2C2520), height: 18),
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
                        child: Text(catName, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFF7B731), fontSize: 13)),
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
                            label: Text('${item['name']} ($priceDisplay)', style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : const Color(0xFFF7B731))),
                            backgroundColor: isSelected ? const Color(0xFFE65C00) : const Color(0xFF26211D),
                            side: BorderSide(color: isSelected ? const Color(0xFFE65C00) : const Color(0xFF382F2A)),
                            onPressed: () => addToTempCart(item, catName),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
              const Divider(color: Color(0xFF2C2520), height: 18),
              const Text('Current Cart:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFF7B731))),
              const SizedBox(height: 6),
              tempCart.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(12), child: Text('No items added yet.', style: TextStyle(color: Colors.white38, fontSize: 13))))
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
                              borderRadius: BorderRadius.circular(8),
                              side: const BorderSide(color: Color(0xFF2C2520)),
                            ),
                            child: ListTile(
                              dense: true,
                              title: Text('${cartItem['name']} (${cartItem['size']})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Text('₹${cartItem['price']} x ${cartItem['qty']}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(icon: const Icon(Icons.remove, color: Color(0xFFE65C00), size: 18), onPressed: () => updateQty(idx, -1)),
                                  Text('${cartItem['qty']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                  IconButton(icon: const Icon(Icons.add, color: Color(0xFFE65C00), size: 18), onPressed: () => updateQty(idx, 1)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                  onPressed: saveOrderToFirebase,
                  child: const Text('Place / Update Order 🔥', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1715),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.12),
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.w600), maxLines: 1),
                Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color), maxLines: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}