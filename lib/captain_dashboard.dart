import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'menu_data.dart';

class CaptainDashboardScreen extends StatefulWidget {
  const CaptainDashboardScreen({super.key});

  @override
  State<CaptainDashboardScreen> createState() => _CaptainDashboardScreenState();
}

class _CaptainDashboardScreenState extends State<CaptainDashboardScreen> {
  String selectedFilter = 'All'; // 'All', 'Ordered', 'Preparing', 'Ready / Pay'
  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';

  int totalTablesCount = 12;

  // New Order / Edit Order State
  DocumentSnapshot? editingOrderDoc;
  bool isTakingOrder = false;
  final TextEditingController tableNoController = TextEditingController();
  final TextEditingController customerNameController = TextEditingController();
  final TextEditingController customerPhoneController = TextEditingController();
  final TextEditingController specialRequestController = TextEditingController();
  final TextEditingController menuSearchController = TextEditingController();
  String menuSearchQuery = '';

  List tempCart = [];
  String selectedSize = 'Medium';

  @override
  void initState() {
    super.initState();
    _loadTableCount();
  }

  Future<void> _loadTableCount() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('settings').doc('business_settings').get();
      if (doc.exists && doc.data() != null) {
        var d = doc.data()!;
        if (mounted) {
          setState(() {
            int parsed = int.tryParse((d['numberOfTables'] ?? '12').toString()) ?? 12;
            totalTablesCount = parsed > 0 ? parsed : 12;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading table count: $e");
    }
  }

  Future<void> updateOrderStatus(String docId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(docId).update({
        'status': newStatus,
        'kitchenStatus': newStatus,
        if (newStatus == 'completed') 'completedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to: ${newStatus.toUpperCase()}'),
            backgroundColor: const Color(0xFFE65C00),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint("Status update error: $e");
    }
  }

  Future<void> updatePaymentStatus(String docId, String paymentMode) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(docId).update({
        'paymentStatus': paymentMode,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment marked as: ${paymentMode.replaceAll('paid_', '').toUpperCase()}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint("Payment update error: $e");
    }
  }

  String _formatCustomerDisplayName(String rawName, String? tableNo) {
    String clean = rawName.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    String t = (tableNo ?? '').trim();
    if (t.isNotEmpty && int.tryParse(t) != null) {
      t = 'Table $t';
    }
    if (clean.isNotEmpty && t.isNotEmpty) {
      return '$clean ($t)';
    } else if (clean.isNotEmpty) {
      return clean;
    } else if (t.isNotEmpty) {
      return t;
    }
    return 'Dine-In Customer';
  }

  void prepareOrderForm({DocumentSnapshot? doc, String? prefilledTable}) {
    setState(() {
      editingOrderDoc = doc;
      menuSearchQuery = '';
      menuSearchController.clear();

      if (doc != null) {
        var data = doc.data() as Map<String, dynamic>;
        String rawTable = data['tableNo'] ?? '';
        String rawName = data['customerName'] ?? '';
        String cleanName = rawName.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();

        tableNoController.text = rawTable.isNotEmpty ? rawTable : (rawName.toLowerCase().startsWith('table') ? rawName : '');
        customerNameController.text = cleanName.toLowerCase().startsWith('table') ? '' : cleanName;
        customerPhoneController.text = data['customerPhone'] ?? '';
        specialRequestController.text = data['specialRequest'] ?? '';
        List items = data['items'] ?? [];
        tempCart = items.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        tableNoController.text = prefilledTable ?? '';
        customerNameController.clear();
        customerPhoneController.clear();
        specialRequestController.clear();
        tempCart.clear();
      }
      isTakingOrder = true;
    });
  }

  void saveOrder() async {
    String tableText = tableNoController.text.trim();
    String custName = customerNameController.text.trim();
    String custPhone = customerPhoneController.text.trim();
    String note = specialRequestController.text.trim();

    if (tempCart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kam se kam ek item add karein!')));
      return;
    }

    String finalDisplayName = _formatCustomerDisplayName(custName, tableText);
    double subtotal = 0;
    for (var it in tempCart) {
      subtotal += ((it['price'] ?? 0.0) * (it['qty'] ?? 1));
    }

    if (editingOrderDoc == null) {
      await FirebaseFirestore.instance.collection('orders').add({
        'deviceId': 'captain_portal_${DateTime.now().millisecondsSinceEpoch}',
        'customerName': finalDisplayName,
        'tableNo': tableText,
        'customerPhone': custPhone,
        'orderType': 'Dine-In',
        'specialRequest': note,
        'items': tempCart.map((e) => {...e, 'isDone': false}).toList(),
        'totalPrice': subtotal,
        'subtotal': subtotal,
        'hasGst': false,
        'status': 'pending',
        'kitchenStatus': 'pending',
        'paymentStatus': 'pending',
        'hasNewItemsAdded': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await FirebaseFirestore.instance.collection('orders').doc(editingOrderDoc!.id).update({
        'customerName': finalDisplayName,
        'tableNo': tableText,
        'customerPhone': custPhone,
        'specialRequest': note,
        'items': tempCart,
        'totalPrice': subtotal,
        'subtotal': subtotal,
        'hasNewItemsAdded': true,
      });
    }

    setState(() {
      isTakingOrder = false;
      editingOrderDoc = null;
      tableNoController.clear();
      customerNameController.clear();
      customerPhoneController.clear();
      specialRequestController.clear();
      tempCart.clear();
    });
  }

  void addToCart(Map<String, dynamic> item, String catName) {
    setState(() {
      String name = item['name'];
      double regP = (item['regularPrice'] ?? item['price'] ?? 0.0).toDouble();
      double medP = (item['mediumPrice'] ?? regP).toDouble();

      bool isMulti = catName.toLowerCase().contains('pizza') || catName.toLowerCase().contains('fries');
      double price = isMulti ? (selectedSize == 'Regular' ? regP : medP) : regP;
      String size = isMulti ? selectedSize : 'Standard';

      int existing = tempCart.indexWhere((e) => e['name'] == name && e['size'] == size);
      if (existing != -1) {
        tempCart[existing]['qty'] += 1;
      } else {
        tempCart.add({
          'name': name,
          'price': price,
          'size': size,
          'qty': 1,
          'isDone': false,
        });
      }
    });
  }

  void _showAddVirtualTableDialog(BuildContext context) {
    final TextEditingController virtualNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A17),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.purpleAccent, width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(Icons.storefront_rounded, color: Colors.purpleAccent, size: 22),
            SizedBox(width: 8),
            Text('Add Virtual Table', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Customer doosri shop par baitha hai toh waha ka reference naam dalein:',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: virtualNameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Virtual Spot / Shop Name',
                hintText: 'e.g. Sharma Tea, Salon, Shop 4',
                prefixIcon: Icon(Icons.location_on_outlined, color: Colors.purpleAccent),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purpleAccent.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              String name = virtualNameController.text.trim();
              if (name.isEmpty) name = 'V-${DateTime.now().minute}';
              Navigator.pop(ctx);
              prepareOrderForm(prefilledTable: name);
            },
            icon: const Icon(Icons.add_shopping_cart, size: 16),
            label: const Text('Take Order', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCaptainTableModal(BuildContext context, DocumentSnapshot orderDoc) {
    var data = orderDoc.data() as Map<String, dynamic>;
    String docId = orderDoc.id;
    String status = (data['status'] ?? 'pending').toString().toLowerCase();
    String paymentStatus = (data['paymentStatus'] ?? 'pending').toString().toLowerCase();
    List items = data['items'] ?? [];
    double total = (data['totalPrice'] ?? 0.0).toDouble();

    showModalBottomSheet(
      backgroundColor: const Color(0xFF1E1A17),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['customerName'] ?? 'Table Order',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFF7B731)),
                        ),
                        if (data['customerPhone'] != null && data['customerPhone'].toString().isNotEmpty)
                          Text('Phone: ${data['customerPhone']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(color: Color(0xFF2C2520)),

              ...items.map<Widget>((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${item['name']} (${item['size'] ?? 'Std'})', style: const TextStyle(color: Colors.white, fontSize: 13)),
                    Text('₹${item['price']} x ${item['qty']}', style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              )),
              const Divider(color: Color(0xFF2C2520)),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Bill:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  Text('₹${total.toInt()}', style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (status == 'pending')
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white),
                      onPressed: () {
                        updateOrderStatus(docId, 'preparing');
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.fireplace_rounded, size: 16),
                      label: const Text('Start Prep (Cooking)'),
                    ),

                  if (status == 'preparing')
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent.shade700, foregroundColor: Colors.white),
                      onPressed: () {
                        updateOrderStatus(docId, 'ready');
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                      label: const Text('Food Ready / Table Pay'),
                    ),

                  if (paymentStatus != 'paid_cash' && paymentStatus != 'paid_upi') ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.green, side: const BorderSide(color: Colors.green)),
                      onPressed: () {
                        updatePaymentStatus(docId, 'paid_cash');
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.money_rounded, size: 16),
                      label: const Text('Cash Paid'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE65C00), side: const BorderSide(color: Color(0xFFE65C00))),
                      onPressed: () {
                        updatePaymentStatus(docId, 'paid_upi');
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.qr_code_rounded, size: 16),
                      label: const Text('UPI Paid'),
                    ),
                  ],

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                    onPressed: () {
                      Navigator.pop(ctx);
                      updateOrderStatus(docId, 'completed');
                    },
                    icon: const Icon(Icons.done_all_rounded, size: 16),
                    label: const Text('Done & Free Table'),
                  ),

                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFF7B731)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      prepareOrderForm(doc: orderDoc);
                    },
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('Add Items'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isTakingOrder) {
      return _buildCaptainOrderTakingView();
    }

    DateTime now = DateTime.now();
    DateTime startOfToday = DateTime(now.year, now.month, now.day);

    return Scaffold(
      backgroundColor: const Color(0xFF141211),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7A431D),
        elevation: 0,
        title: const Text('Captain Service Portal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh Tables',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.purpleAccent.shade700,
        foregroundColor: Colors.white,
        elevation: 6,
        icon: const Icon(Icons.add_business_rounded, size: 20),
        label: const Text('Add Virtual Table', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        onPressed: () => _showAddVirtualTableDialog(context),
      ),
      body: StreamBuilder<QuerySnapshot>(
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

          Map<int, DocumentSnapshot> tableOrderMap = {};
          List<DocumentSnapshot> activeVirtualOrders = [];

          for (var doc in todayOrders) {
            var data = doc.data() as Map<String, dynamic>;
            String status = (data['status'] ?? 'pending').toString().toLowerCase();

            if (status != 'completed') {
              String customer = (data['customerName'] ?? '').toString().toLowerCase();
              String tNo = (data['tableNo'] ?? '').toString().trim();

              bool matched = false;
              for (int i = 1; i <= totalTablesCount; i++) {
                if (customer.contains('table $i') || tNo == '$i' || tNo.toLowerCase() == 'table $i') {
                  tableOrderMap[i] = doc;
                  matched = true;
                  break;
                }
              }

              if (!matched && tNo.isNotEmpty) {
                activeVirtualOrders.add(doc);
              }
            }
          }

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: const Color(0xFF221D1A),
                child: TextField(
                  controller: searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search table, spot, item, phone...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                    filled: true,
                    fillColor: const Color(0xFF181513),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) => setState(() => searchQuery = val.toLowerCase().trim()),
                ),
              ),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: const Color(0xFF1A1614),
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF26201D),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF382F2A)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFilterTab('All', Icons.all_inclusive),
                          _buildFilterTab('Ordered', Icons.assignment_outlined),
                          _buildFilterTab('Preparing', Icons.fireplace_rounded),
                          _buildFilterTab('Ready / Pay', Icons.check_circle_outline_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: const Color(0xFF141211),
                child: Row(
                  children: [
                    _buildLegendItem(Colors.green, 'Free'),
                    const SizedBox(width: 12),
                    _buildLegendItem(Colors.redAccent, 'Ordered'),
                    const SizedBox(width: 12),
                    _buildLegendItem(Colors.amber, 'Prep'),
                    const SizedBox(width: 12),
                    _buildLegendItem(Colors.blueAccent, 'Pay'),
                    const SizedBox(width: 12),
                    _buildLegendItem(Colors.purpleAccent, 'Virtual'),
                  ],
                ),
              ),

              Expanded(
                child: _buildCaptainTablesGrid(tableOrderMap, activeVirtualOrders),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterTab(String label, IconData icon) {
    bool isSelected = selectedFilter == label;
    return InkWell(
      onTap: () => setState(() => selectedFilter = label),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE65C00) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.white60),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
      ],
    );
  }

  Widget _buildCaptainTablesGrid(Map<int, DocumentSnapshot> tableOrderMap, List<DocumentSnapshot> activeVirtualOrders) {
    List<int> visibleTables = [];

    for (int i = 1; i <= totalTablesCount; i++) {
      DocumentSnapshot? orderDoc = tableOrderMap[i];
      bool isOccupied = orderDoc != null;

      if (selectedFilter == 'All') {
        visibleTables.add(i);
      } else if (selectedFilter == 'Ordered') {
        if (isOccupied && (orderDoc.get(['status']) == 'pending')) visibleTables.add(i);
      } else if (selectedFilter == 'Preparing') {
        if (isOccupied && (orderDoc.get(['status']) == 'preparing')) visibleTables.add(i);
      } else if (selectedFilter == 'Ready / Pay') {
        if (isOccupied && (orderDoc.get(['status']) == 'ready')) visibleTables.add(i);
      }
    }

    var visibleVirtuals = activeVirtualOrders.where((doc) {
      var d = doc.data() as Map<String, dynamic>;
      String st = (d['status'] ?? 'pending').toString().toLowerCase();
      if (selectedFilter == 'All') return true;
      if (selectedFilter == 'Ordered') return st == 'pending';
      if (selectedFilter == 'Preparing') return st == 'preparing';
      if (selectedFilter == 'Ready / Pay') return st == 'ready';
      return false;
    }).toList();

    int totalItems = visibleTables.length + visibleVirtuals.length;

    if (totalItems == 0) {
      return Center(
        child: Text('Is filter ($selectedFilter) me koi active table nahi hai.', style: const TextStyle(color: Colors.white38, fontSize: 14)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int columns = constraints.maxWidth > 1100 ? 6 : (constraints.maxWidth > 700 ? 4 : (constraints.maxWidth > 450 ? 3 : 2));

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.05,
          ),
          itemCount: totalItems,
          itemBuilder: (context, index) {
            if (index < visibleTables.length) {
              int tableNumber = visibleTables[index];
              DocumentSnapshot? orderDoc = tableOrderMap[tableNumber];
              bool isOccupied = orderDoc != null;

              Color statusDotColor = Colors.green;
              String statusLabel = 'Available';

              if (isOccupied) {
                var oData = orderDoc.data() as Map<String, dynamic>;
                String kStatus = (oData['status'] ?? 'pending').toString().toLowerCase();
                if (kStatus == 'preparing') {
                  statusDotColor = Colors.amber;
                  statusLabel = 'Prep';
                } else if (kStatus == 'ready') {
                  statusDotColor = Colors.blueAccent;
                  statusLabel = 'Pay';
                } else {
                  statusDotColor = Colors.redAccent;
                  statusLabel = 'Ordered';
                }
              }

              return InkWell(
                onTap: () {
                  if (isOccupied) {
                    _showCaptainTableModal(context, orderDoc);
                  } else {
                    prepareOrderForm(prefilledTable: '$tableNumber');
                  }
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D1917),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isOccupied ? statusDotColor : Colors.green.withOpacity(0.4),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: statusDotColor)),
                          const SizedBox(width: 6),
                          Text('$tableNumber', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(color: statusDotColor.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                        child: Text(statusLabel, style: TextStyle(color: statusDotColor, fontSize: 10.5, fontWeight: FontWeight.bold)),
                      ),
                      if (isOccupied) ...[
                        const SizedBox(height: 4),
                        Text('₹${(orderDoc.get('totalPrice') ?? 0).toInt()}', style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.w900, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              );
            }

            int vIndex = index - visibleTables.length;
            DocumentSnapshot vDoc = visibleVirtuals[vIndex];
            var vData = vDoc.data() as Map<String, dynamic>;
            String vTableName = (vData['tableNo'] ?? 'Virtual').toString();
            double vTotal = (vData['totalPrice'] ?? 0.0).toDouble();

            String vStatus = (vData['status'] ?? 'pending').toString().toLowerCase();
            Color vStatusColor = Colors.redAccent;
            String vStatusLabel = 'Ordered';
            if (vStatus == 'preparing') {
              vStatusColor = Colors.amber;
              vStatusLabel = 'Prep';
            } else if (vStatus == 'ready') {
              vStatusColor = Colors.blueAccent;
              vStatusLabel = 'Pay';
            }

            return InkWell(
              onTap: () => _showCaptainTableModal(context, vDoc),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF221626),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.purpleAccent.withOpacity(0.85), width: 1.5),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.storefront_rounded, color: Colors.purpleAccent, size: 14),
                        SizedBox(width: 4),
                        Text('VIRTUAL', style: TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: Text(
                        vTableName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: vStatusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                      child: Text(vStatusLabel, style: TextStyle(color: vStatusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 3),
                    Text('₹${vTotal.toInt()}', style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.w900, fontSize: 12)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCaptainOrderTakingView() {
    return Scaffold(
      backgroundColor: const Color(0xFF141211),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7A431D),
        elevation: 0,
        title: Text(
          editingOrderDoc == null ? 'New Order (${tableNoController.text})' : 'Add Items (${tableNoController.text})',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => setState(() => isTakingOrder = false),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('menu_categories').snapshots(),
        builder: (context, menuSnapshot) {
          List liveCategories = restaurantMenuCategories;
          if (menuSnapshot.hasData && menuSnapshot.data!.docs.isNotEmpty) {
            liveCategories = menuSnapshot.data!.docs.map((d) => d.data() as Map<String, dynamic>).toList();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: tableNoController,
                        style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(labelText: 'Table / Spot', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: customerNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Customer (Opt)', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                TextField(
                  controller: specialRequestController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Cooking Instructions (Optional)',
                    hintText: 'e.g. less spicy, extra crispy',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    const Text('Size:', style: TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Regular'),
                      selected: selectedSize == 'Regular',
                      selectedColor: const Color(0xFFE65C00),
                      onSelected: (val) => setState(() => selectedSize = 'Regular'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Medium'),
                      selected: selectedSize == 'Medium',
                      selectedColor: const Color(0xFFE65C00),
                      onSelected: (val) => setState(() => selectedSize = 'Medium'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                TextField(
                  controller: menuSearchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Search Dish...',
                    prefixIcon: Icon(Icons.search, color: Color(0xFFE65C00)),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) => setState(() => menuSearchQuery = val.toLowerCase().trim()),
                ),
                const Divider(color: Color(0xFF2C2520), height: 24),

                ...liveCategories.map((cat) {
                  String catName = cat['categoryName'] ?? '';
                  List items = cat['items'] ?? [];
                  var filtered = items.where((it) {
                    if (menuSearchQuery.isEmpty) return true;
                    return it['name'].toString().toLowerCase().contains(menuSearchQuery);
                  }).toList();

                  if (filtered.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Text(catName, style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: filtered.map<Widget>((it) {
                          bool inCart = tempCart.any((c) => c['name'] == it['name']);
                          var regP = it['regularPrice'];
                          var medP = it['mediumPrice'];
                          var stdP = it['price'];
                          String pStr = (regP != null && medP != null) ? '₹$regP/₹$medP' : '₹${stdP ?? regP ?? 0}';

                          return ActionChip(
                            label: Text('${it['name']} ($pStr)', style: TextStyle(fontSize: 11, color: inCart ? Colors.white : const Color(0xFFF7B731))),
                            backgroundColor: inCart ? const Color(0xFFE65C00) : const Color(0xFF26211D),
                            onPressed: () => addToCart(it, catName),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                    ],
                  );
                }),

                const Divider(color: Color(0xFF2C2520), height: 24),

                const Text('Selected Items in Order:', style: TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 6),
                tempCart.isEmpty
                    ? const Padding(padding: EdgeInsets.all(12), child: Text('No items added yet.', style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: tempCart.length,
                        itemBuilder: (context, idx) {
                          var c = tempCart[idx];
                          return Card(
                            color: const Color(0xFF1E1A17),
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              title: Text('${c['name']} (${c['size']})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: Text('₹${c['price']} x ${c['qty']}', style: const TextStyle(color: Colors.white54)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, color: Color(0xFFE65C00), size: 18),
                                    onPressed: () {
                                      setState(() {
                                        c['qty'] -= 1;
                                        if (c['qty'] <= 0) tempCart.removeAt(idx);
                                      });
                                    },
                                  ),
                                  Text('${c['qty']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.add, color: Color(0xFFE65C00), size: 18),
                                    onPressed: () => setState(() => c['qty'] += 1),
                                  ),
                                ],
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
                    onPressed: saveOrder,
                    child: Text(
                      editingOrderDoc == null ? 'Send to Kitchen 🔥' : 'Update & Send 🔥',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }
}