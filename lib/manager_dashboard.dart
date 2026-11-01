// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';
import 'menu_data.dart';
import 'receipt_screen.dart';
import 'customer_contacts_screen.dart';
import 'reports_analytics_screen.dart';

class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  String? shopLogoBase64;
  int currentNavIndex = 1; // 0: Dashboard, 1: Orders, 2: Reports, 3: Menu, 4: Settings
  String currentView = 'Orders'; // 'Orders', 'NewOrder'
  DocumentSnapshot? editingOrderDoc;

  String orderTypeTab = 'Dine-In'; // 'Dine-In' or 'Takeaway'
  String selectedStatusFilter = 'All'; // 'All', 'Preparing', 'Payment Pending', 'Completed'
  final TextEditingController searchFilterController = TextEditingController();
  String searchFilterText = '';

  String salesFilterMode = 'Today';
  DateTime selectedDate = DateTime.now();
  String selectedMonthYear = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

  // New Order Controllers
  final TextEditingController tableNoController = TextEditingController();
  final TextEditingController customerNameController = TextEditingController();
  final TextEditingController customerPhoneController = TextEditingController();
  final TextEditingController specialRequestController = TextEditingController();
  final TextEditingController menuSearchController = TextEditingController();
  String menuSearchQuery = '';

  // In-memory instant customer lookup cache
  final Map<String, String> _localCustomerCache = {};
  bool isSearchingCustomer = false;

  // Previous order items of the returning customer
  List previousOrderItems = [];
  String previousOrderDateStr = '';

  // Safe declaration (Fixed type definition)
  List tempCart = [];
  String selectedSize = 'Medium';
  int totalTablesCount = 12; // Dynamic table count

  // Settings Controllers
  final TextEditingController shopNameController = TextEditingController(text: 'Pizza La Forno');
  final TextEditingController taglineController = TextEditingController(text: 'Wood Fired Pizza');
  final TextEditingController ownerNameController = TextEditingController(text: 'manish');
  final TextEditingController mobileNumberController = TextEditingController(text: '857585758575');
  final TextEditingController emailController = TextEditingController(text: 'manish.patel881998@gmail.com');
  final TextEditingController gstNumberController = TextEditingController(text: '645746475656');
  final TextEditingController addressController = TextEditingController();

  final TextEditingController receiptHeaderController = TextEditingController(text: 'Thank you for your order!');
  final TextEditingController receiptFooterController = TextEditingController(text: 'Visit Again!');
  final TextEditingController thankYouMsgController = TextEditingController(text: 'Thank You!');
  bool showGstToggle = false;
  final TextEditingController gstPercentController = TextEditingController(text: '5');
  final TextEditingController currencySymbolController = TextEditingController(text: '₹');
  final TextEditingController currencyCodeController = TextEditingController(text: 'INR');

  String defaultOrderType = 'Dine-In';
  final TextEditingController defaultTaxController = TextEditingController(text: '5');
  bool autoGenBillNumber = true;
  bool autoGenTokenNumber = true;
  final TextEditingController numberOfTablesController = TextEditingController(text: '12');

  @override
  void initState() {
    super.initState();
    _loadSettingsFromFirestore();
  }

  Future<void> _loadSettingsFromFirestore() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('settings').doc('business_settings').get();
      if (doc.exists && doc.data() != null) {
        var d = doc.data()!;
        if (mounted) {
          setState(() {
            shopLogoBase64 = d['shopLogoBase64'];
            shopNameController.text = d['shopName'] ?? shopNameController.text;
            taglineController.text = d['tagline'] ?? taglineController.text;
            ownerNameController.text = d['ownerName'] ?? ownerNameController.text;
            mobileNumberController.text = d['mobileNumber'] ?? mobileNumberController.text;
            emailController.text = d['email'] ?? emailController.text;
            gstNumberController.text = d['gstNumber'] ?? gstNumberController.text;
            addressController.text = d['address'] ?? addressController.text;

            receiptHeaderController.text = d['receiptHeader'] ?? receiptHeaderController.text;
            receiptFooterController.text = d['receiptFooter'] ?? receiptFooterController.text;
            thankYouMsgController.text = d['thankYouMessage'] ?? thankYouMsgController.text;
            showGstToggle = d['showGst'] ?? false;
            gstPercentController.text = (d['gstPercentage'] ?? '5').toString();
            currencySymbolController.text = d['currencySymbol'] ?? '₹';
            currencyCodeController.text = d['currencyCode'] ?? 'INR';

            defaultOrderType = d['defaultOrderType'] ?? 'Dine-In';
            defaultTaxController.text = (d['defaultTax'] ?? '5').toString();
            autoGenBillNumber = d['autoGenBillNumber'] ?? true;
            autoGenTokenNumber = d['autoGenTokenNumber'] ?? true;

            numberOfTablesController.text = (d['numberOfTables'] ?? '12').toString();
            int parsedTables = int.tryParse(numberOfTablesController.text.trim()) ?? 12;
            totalTablesCount = parsedTables > 0 ? parsedTables : 12;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
    }
  }

  Future<void> _saveSettingsToFirestore() async {
    try {
      int parsedTables = int.tryParse(numberOfTablesController.text.trim()) ?? 12;
      if (parsedTables <= 0) parsedTables = 12;

      await FirebaseFirestore.instance.collection('settings').doc('business_settings').set({
        'shopLogoBase64': shopLogoBase64,
        'shopName': shopNameController.text.trim(),
        'tagline': taglineController.text.trim(),
        'ownerName': ownerNameController.text.trim(),
        'mobileNumber': mobileNumberController.text.trim(),
        'email': emailController.text.trim(),
        'gstNumber': gstNumberController.text.trim(),
        'address': addressController.text.trim(),

        'receiptHeader': receiptHeaderController.text.trim(),
        'receiptFooter': receiptFooterController.text.trim(),
        'thankYouMessage': thankYouMsgController.text.trim(),
        'showGst': showGstToggle,
        'gstPercentage': gstPercentController.text.trim(),
        'currencySymbol': currencySymbolController.text.trim(),
        'currencyCode': currencyCodeController.text.trim(),

        'defaultOrderType': defaultOrderType,
        'defaultTax': defaultTaxController.text.trim(),
        'autoGenBillNumber': autoGenBillNumber,
        'autoGenTokenNumber': autoGenTokenNumber,
        'numberOfTables': parsedTables,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        totalTablesCount = parsedTables;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settings saved! Total tables updated to $parsedTables.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving settings: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _fetchCustomerNameByPhone(String rawPhone) async {
    String phone = rawPhone.trim().replaceAll(RegExp(r'\D'), '');

    if (phone.length == 10) {
      setState(() => isSearchingCustomer = true);

      try {
        var querySnap = await FirebaseFirestore.instance
            .collection('orders')
            .where('customerPhone', isEqualTo: phone)
            .get();

        if (querySnap.docs.isNotEmpty) {
          var docs = querySnap.docs.toList();
          docs.sort((a, b) {
            Timestamp? tA = a.data()['createdAt'] as Timestamp?;
            Timestamp? tB = b.data()['createdAt'] as Timestamp?;
            if (tA == null && tB == null) return 0;
            if (tA == null) return 1;
            if (tB == null) return -1;
            return tB.compareTo(tA);
          });

          String validName = '';
          for (var doc in docs) {
            String r = (doc.data()['customerName'] ?? '').toString();
            String c = r
                .replaceAll(r'$1', '')
                .replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '')
                .trim();
            if (c.isNotEmpty &&
                !RegExp(r'^\d+$').hasMatch(c) &&
                c.toLowerCase() != 'guest' &&
                !c.toLowerCase().startsWith('table')) {
              validName = c;
              break;
            }
          }

          var lastOrder = docs.first.data();
          List rawItems = lastOrder['items'] ?? [];
          Timestamp? t = lastOrder['createdAt'] as Timestamp?;
          DateTime? d = t?.toDate();

          if (validName.isNotEmpty) {
            _localCustomerCache[phone] = validName;
            setState(() {
              customerNameController.text = validName;
              previousOrderItems = rawItems.map((e) => Map<String, dynamic>.from(e)).toList();
              if (d != null) {
                previousOrderDateStr = '${d.day}/${d.month}/${d.year}';
              }
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.verified, color: Colors.greenAccent, size: 18),
                      const SizedBox(width: 8),
                      Text('Welcome Back! $validName ke previous items mil gaye.'),
                    ],
                  ),
                  backgroundColor: const Color(0xFF1E1A17),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        } else {
          setState(() {
            previousOrderItems.clear();
            previousOrderDateStr = '';
          });
        }
      } catch (e) {
        debugPrint("Error fetching customer by phone: $e");
      } finally {
        if (mounted) setState(() => isSearchingCustomer = false);
      }
    }
  }

  String _formatCustomerDisplayName(String rawName, String? tableNo) {
    String clean = rawName
        .replaceAll(r'$1', '')
        .replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    String t = (tableNo ?? '').trim();
    if (t.isNotEmpty && !t.toLowerCase().startsWith('table')) {
      t = 'Table $t';
    }

    if (clean.isNotEmpty && t.isNotEmpty) {
      return '$clean ($t)';
    } else if (clean.isNotEmpty) {
      return clean;
    } else if (t.isNotEmpty) {
      return t;
    }
    return 'Counter Customer';
  }

  double get calcTempTotal {
    double subtotal = 0;
    for (var item in tempCart) {
      subtotal += ((item['price'] ?? 0.0) * (item['qty'] ?? 1));
    }

    if (showGstToggle) {
      double gstPercent = double.tryParse(gstPercentController.text.trim()) ?? 5.0;
      double gstAmount = subtotal * (gstPercent / 100.0);
      return subtotal + gstAmount;
    }
    return subtotal;
  }

  double get calcTempSubtotal {
    double subtotal = 0;
    for (var item in tempCart) {
      subtotal += ((item['price'] ?? 0.0) * (item['qty'] ?? 1));
    }
    return subtotal;
  }

  void markOrderAsFinalDone(BuildContext context, String docId, String customerName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Complete & Release Table', style: TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold)),
        content: Text('Kya aap "$customerName" ka bill close karke table ko Free mark karna chahte hain?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                var orderSnap = await FirebaseFirestore.instance.collection('orders').doc(docId).get();
                var oData = orderSnap.data() ?? {};

                await FirebaseFirestore.instance.collection('orders').doc(docId).update({
                  'status': 'completed',
                  'kitchenStatus': 'completed',
                  'completedAt': FieldValue.serverTimestamp(),
                });

                if (!context.mounted) return;

                Map<String, dynamic> bSettings = {
                  'shopLogoBase64': shopLogoBase64,
                  'shopName': shopNameController.text.trim(),
                  'tagline': taglineController.text.trim(),
                  'address': addressController.text.trim(),
                  'mobileNumber': mobileNumberController.text.trim(),
                  'gstNumber': gstNumberController.text.trim(),
                  'receiptHeader': receiptHeaderController.text.trim(),
                  'receiptFooter': receiptFooterController.text.trim(),
                  'thankYouMessage': thankYouMsgController.text.trim(),
                  'showGst': showGstToggle,
                  'gstPercentage': gstPercentController.text.trim(),
                };

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PaymentCompleteReceiptScreen(
                      orderData: oData,
                      orderId: docId,
                      businessSettings: bSettings,
                    ),
                  ),
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

  void updatePaymentStatus(String docId, String newPaymentStatus) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(docId).update({'paymentStatus': newPaymentStatus});
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  void _confirmDeleteOrder(BuildContext context, String docId, String customerName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A17),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        title: const Text(
          'Delete Order',
          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Kya aap "$customerName" ke is order ko permanently delete karna chahte hain?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFirestore.instance.collection('orders').doc(docId).delete();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Order successfully delete ho gaya!'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              } catch (e) {
                debugPrint("Error deleting order: $e");
              }
            },
            child: const Text('Delete 🗑️', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void updateOrderStatus(String docId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(docId).update({
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

  void _logout(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const CustomerCartScreen()),
      (route) => false,
    );
  }

  void prepareOrderForm({DocumentSnapshot? doc, String? prefilledTable}) {
    setState(() {
      editingOrderDoc = doc;
      menuSearchQuery = '';
      menuSearchController.clear();
      previousOrderItems.clear();
      previousOrderDateStr = '';
      if (doc != null) {
        var data = doc.data() as Map<String, dynamic>;
        String rawTable = data['tableNo'] ?? '';
        String rawName = data['customerName'] ?? '';

        String cleanName = rawName
            .replaceAll(r'$1', '')
            .replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '')
            .trim();

        tableNoController.text = rawTable.isNotEmpty
            ? rawTable
            : (rawName.toLowerCase().startsWith('table') ? rawName : '');
        customerNameController.text = cleanName.toLowerCase().startsWith('table') ? '' : cleanName;
        customerPhoneController.text = data['customerPhone'] ?? '';
        specialRequestController.text = data['specialRequest'] ?? '';
        List items = data['items'] ?? [];
        tempCart = items.map((e) {
          var m = Map<String, dynamic>.from(e);
          m['isDone'] = e['isDone'] ?? false;
          return m;
        }).toList();
      } else {
        tableNoController.text = prefilledTable != null ? 'Table $prefilledTable' : '';
        customerNameController.clear();
        customerPhoneController.clear();
        specialRequestController.clear();
        tempCart.clear();
      }
      currentView = 'NewOrder';
    });
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
    String tableText = tableNoController.text.trim();
    String rawName = customerNameController.text.trim();
    String rawPhone = customerPhoneController.text.trim();
    String note = specialRequestController.text.trim();

    String cleanDigitsInName = rawName.replaceAll(RegExp(r'\D'), '');
    String cleanDigitsInPhone = rawPhone.replaceAll(RegExp(r'\D'), '');

    String custName = rawName;
    String custPhone = rawPhone;

    if (cleanDigitsInName.length >= 10 && RegExp(r'[a-zA-Z]').hasMatch(rawPhone)) {
      custName = rawPhone;
      custPhone = cleanDigitsInName;
    } else if (cleanDigitsInPhone.length >= 10) {
      custPhone = cleanDigitsInPhone;
    }

    String finalDisplayName = _formatCustomerDisplayName(custName, tableText);

    if (tempCart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kam se kam ek item add karein!')));
      return;
    }

    if (editingOrderDoc == null) {
      List initialItems = tempCart.map((e) => {...e, 'isDone': false}).toList();
      await FirebaseFirestore.instance.collection('orders').add({
        'deviceId': 'counter_manager_${DateTime.now().millisecondsSinceEpoch}',
        'customerName': finalDisplayName,
        'tableNo': tableText,
        'customerPhone': custPhone,
        'orderType': orderTypeTab,
        'specialRequest': note,
        'items': initialItems,
        'totalPrice': calcTempTotal,
        'subtotal': calcTempSubtotal,
        'hasGst': showGstToggle,
        'gstPercentage': double.tryParse(gstPercentController.text.trim()) ?? 5.0,
        'status': 'pending',
        'kitchenStatus': 'pending',
        'paymentStatus': 'pending',
        'hasNewItemsAdded': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      bool hasAnyNew = tempCart.any((e) => (e['isDone'] ?? false) == false);

      await FirebaseFirestore.instance.collection('orders').doc(editingOrderDoc!.id).update({
        'customerName': finalDisplayName,
        'tableNo': tableText,
        'customerPhone': custPhone,
        'orderType': orderTypeTab,
        'specialRequest': note,
        'items': tempCart,
        'totalPrice': calcTempTotal,
        'subtotal': calcTempSubtotal,
        'hasGst': showGstToggle,
        'gstPercentage': double.tryParse(gstPercentController.text.trim()) ?? 5.0,
        'status': 'pending',
        'kitchenStatus': 'pending',
        'hasNewItemsAdded': hasAnyNew,
      });
    }

    setState(() {
      currentView = 'Orders';
      editingOrderDoc = null;
      tableNoController.clear();
      customerNameController.clear();
      customerPhoneController.clear();
      specialRequestController.clear();
      previousOrderItems.clear();
      previousOrderDateStr = '';
      tempCart.clear();
    });
  }

  void _showTableDetailsModal(BuildContext context, DocumentSnapshot orderDoc) {
    var data = orderDoc.data() as Map<String, dynamic>;
    List items = data['items'] ?? [];
    double currentTotal = (data['totalPrice'] ?? 0.0).toDouble();
    String status = (data['status'] ?? 'pending').toString().toLowerCase();
    String paymentStatus = (data['paymentStatus'] ?? 'pending').toString().toLowerCase();

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
                    Text('${item['name']} (${item['size'] ?? 'Standard'})', style: const TextStyle(color: Colors.white, fontSize: 13)),
                    Text('₹${item['price']} x ${item['qty']}', style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              )),
              const Divider(color: Color(0xFF2C2520)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Bill:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  Text('₹${currentTotal.toInt()}', style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 14),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (status == 'pending')
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white),
                      onPressed: () {
                        updateOrderStatus(orderDoc.id, 'preparing');
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.fireplace, size: 16),
                      label: const Text('Start Prep (Cooking)'),
                    ),

                  if (status == 'preparing')
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent.shade700, foregroundColor: Colors.white),
                      onPressed: () {
                        updateOrderStatus(orderDoc.id, 'ready');
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Food Ready / Table Pay'),
                    ),

                  if (paymentStatus != 'paid_cash' && paymentStatus != 'paid_upi') ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.green, side: const BorderSide(color: Colors.green)),
                      onPressed: () {
                        updatePaymentStatus(orderDoc.id, 'paid_cash');
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.money, size: 16),
                      label: const Text('Pay Cash'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE65C00), side: const BorderSide(color: Color(0xFFE65C00))),
                      onPressed: () {
                        updatePaymentStatus(orderDoc.id, 'paid_upi');
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.qr_code, size: 16),
                      label: const Text('Pay UPI'),
                    ),
                  ],

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                    onPressed: () {
                      Navigator.pop(ctx);
                      markOrderAsFinalDone(context, orderDoc.id, data['customerName'] ?? 'Table');
                    },
                    icon: const Icon(Icons.done_all, size: 16),
                    label: const Text('Done & Free Table'),
                  ),

                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFF7B731)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      prepareOrderForm(doc: orderDoc);
                    },
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit / Add Items'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentBody() {
    if (currentView == 'NewOrder') {
      return _buildOrderFormBody();
    }
    switch (currentNavIndex) {
      case 0:
        return _buildDashboardOverviewBody();
      case 1:
        return _buildOrdersTablesBody();
      case 2:
        return const ReportsAnalyticsScreen();
      case 3:
        return _buildMenuManagementBody();
      case 4:
        return _buildSettingsBody();
      default:
        return _buildOrdersTablesBody();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: currentView == 'Orders' && currentNavIndex == 1,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          currentView = 'Orders';
          currentNavIndex = 1;
        });
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF141211),
        appBar: AppBar(
          backgroundColor: const Color(0xFF7A431D),
          elevation: 0,
          titleSpacing: 12,
          title: Text(
            currentNavIndex == 4
                ? 'Settings'
                : (currentNavIndex == 1
                    ? 'Orders'
                    : (currentNavIndex == 0
                        ? 'Dashboard'
                        : (currentNavIndex == 2
                            ? 'Reports'
                            : 'Menu'))),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (currentNavIndex == 4)
              Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65C00),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: _saveSettingsToFirestore,
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.contacts_outlined, color: Colors.white),
                tooltip: 'Customer Directory',
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                padding: EdgeInsets.zero,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CustomerContactsScreen(),
                    ),
                  );
                },
              ),
            const SizedBox(width: 4),
          ],
          bottom: currentNavIndex == 1 && currentView == 'Orders'
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(45),
                  child: Container(
                    color: const Color(0xFF7A431D),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => orderTypeTab = 'Dine-In'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: orderTypeTab == 'Dine-In' ? Colors.white : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.restaurant, color: orderTypeTab == 'Dine-In' ? Colors.white : Colors.white60, size: 17),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Dine-In',
                                    style: TextStyle(
                                      color: orderTypeTab == 'Dine-In' ? Colors.white : Colors.white60,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => orderTypeTab = 'Takeaway'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: orderTypeTab == 'Takeaway' ? Colors.white : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.shopping_bag_outlined, color: orderTypeTab == 'Takeaway' ? Colors.white : Colors.white60, size: 17),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Takeaway',
                                    style: TextStyle(
                                      color: orderTypeTab == 'Takeaway' ? Colors.white : Colors.white60,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
        ),

        body: _buildCurrentBody(),

        bottomNavigationBar: Container(
          height: 60,
          decoration: const BoxDecoration(
            color: Color(0xFF1B1715),
            border: Border(top: BorderSide(color: Color(0xFF2E2621), width: 1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomNavItem(0, Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
              _buildBottomNavItem(1, Icons.receipt_long_outlined, Icons.receipt_long, 'Orders'),
              _buildBottomNavItem(2, Icons.bar_chart_outlined, Icons.bar_chart, 'Reports'),
              _buildBottomNavItem(3, Icons.restaurant_menu, Icons.restaurant_menu, 'Menu'),
              _buildBottomNavItem(4, Icons.settings_outlined, Icons.settings, 'Settings'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(int index, IconData unselectedIcon, IconData selectedIcon, String label) {
    bool isSelected = currentNavIndex == index;
    Color itemColor = isSelected ? const Color(0xFFF7B731) : Colors.white54;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            currentNavIndex = index;
            currentView = 'Orders';
          });
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isSelected ? selectedIcon : unselectedIcon, color: itemColor, size: 21),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: itemColor,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadLogo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // Web aur App dono ke liye bytes fetch karega
      );

      if (result != null && result.files.single.bytes != null) {
        Uint8List fileBytes = result.files.single.bytes!;
        String base64Data = base64Encode(fileBytes);

        setState(() {
          shopLogoBase64 = base64Data;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logo select ho gaya! "Save" button dabayein save karne ke liye.'),
            backgroundColor: Color(0xFFE65C00),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error picking logo: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking logo: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _removeLogo() {
    setState(() {
      shopLogoBase64 = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logo remove ho gaya! "Save" button dabayein update karne ke liye.'),
        backgroundColor: Colors.redAccent,
      ),
    );
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
              'Agar customer kisi doosri shop/spot par baitha hai toh waha ka reference naam dalein:',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: virtualNameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Shop / Virtual Spot Name',
                hintText: 'e.g. Sharma Tea, Salon, Shop 4, V-1',
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _buildOrdersTablesBody() {
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

        for (var doc in todayOrders) {
          var d = doc.data() as Map<String, dynamic>;
          String p = (d['customerPhone'] ?? '').toString().trim();
          String n = (d['customerName'] ?? '').toString().trim();
          if (p.length == 10 && n.isNotEmpty) {
            String clean = n.replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '').trim();
            if (clean.isNotEmpty && clean.toLowerCase() != 'guest') {
              _localCustomerCache[p] = clean;
            }
          }
        }

        var completedOrders = todayOrders.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          return (data['status'] ?? '') == 'completed';
        }).toList();

        Map<int, DocumentSnapshot> tableOrderMap = {};
        List<DocumentSnapshot> activeVirtualOrders = [];

        for (var doc in todayOrders) {
          var data = doc.data() as Map<String, dynamic>;
          String status = (data['status'] ?? 'pending').toString().toLowerCase();
          if (status != 'completed') {
            String customer = (data['customerName'] ?? '').toString().toLowerCase();
            String tNo = (data['tableNo'] ?? '').toString().trim();

            bool isExplicitVirtual = data['isVirtualTable'] == true ||
                tNo.toLowerCase().startsWith('v-') ||
                tNo.toLowerCase().startsWith('virtual');

            bool matchedPhysical = false;
            if (!isExplicitVirtual) {
              for (int i = 1; i <= totalTablesCount; i++) {
                if (customer.contains('table $i') ||
                    customer.contains('t$i') ||
                    tNo == '$i' ||
                    tNo.toLowerCase() == 'table $i') {
                  tableOrderMap[i] = doc;
                  matchedPhysical = true;
                  break;
                }
              }
            }

            if (!matchedPhysical && tNo.isNotEmpty) {
              activeVirtualOrders.add(doc);
            }
          }
        }

        return Stack(
          children: [
            Column(
              children: [
                // Segment Tabs (Search bar hata diya gaya hai)
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
                            _buildSegmentTab('All', Icons.all_inclusive),
                            _buildSegmentTab('Preparing', Icons.fireplace),
                            _buildSegmentTab('Payment Pending', Icons.credit_card),
                            _buildSegmentTab('Completed', Icons.check_circle_outline),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Clean Legend Row (Upar ka duplicate virtual button hata diya gaya hai)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: const Color(0xFF141211),
                  child: Row(
                    children: [
                      _buildLegendItem(Colors.green, 'Free'),
                      const SizedBox(width: 14),
                      _buildLegendItem(Colors.redAccent, 'Ordered'),
                      const SizedBox(width: 14),
                      _buildLegendItem(Colors.amber, 'Prep'),
                      const SizedBox(width: 14),
                      _buildLegendItem(Colors.blueAccent, 'Pay'),
                      const SizedBox(width: 14),
                      _buildLegendItem(Colors.purpleAccent, 'Virtual'),
                    ],
                  ),
                ),

                Expanded(
                  child: selectedStatusFilter == 'Completed'
                      ? _buildCompletedOrdersList(completedOrders)
                      : _buildFilteredTablesGrid(tableOrderMap, activeVirtualOrders),
                ),
              ],
            ),

            // Floating Action Button (Neeche wala single button rahega)
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton.extended(
                backgroundColor: Colors.purpleAccent.shade700,
                foregroundColor: Colors.white,
                elevation: 6,
                icon: const Icon(Icons.add_business_rounded, size: 20),
                label: const Text('Add Virtual Table', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () => _showAddVirtualTableDialog(context),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilteredTablesGrid(
    Map<int, DocumentSnapshot> tableOrderMap,
    List<DocumentSnapshot> activeVirtualOrders,
  ) {
    List<int> visibleTables = [];

    for (int i = 1; i <= totalTablesCount; i++) {
      DocumentSnapshot? orderDoc = tableOrderMap[i];
      bool isOccupied = orderDoc != null;

      if (selectedStatusFilter == 'All') {
        visibleTables.add(i);
      } else if (selectedStatusFilter == 'Preparing') {
        if (isOccupied && (orderDoc.get('status') == 'preparing')) {
          visibleTables.add(i);
        }
      } else if (selectedStatusFilter == 'Payment Pending') {
        if (isOccupied) {
          String kStatus = (orderDoc.data() as Map<String, dynamic>)['status'] ?? 'pending';
          if (kStatus == 'ready') {
            visibleTables.add(i);
          }
        }
      }
    }

    var visibleVirtuals = activeVirtualOrders.where((doc) {
      var d = doc.data() as Map<String, dynamic>;
      String st = (d['status'] ?? 'pending').toString().toLowerCase();
      if (selectedStatusFilter == 'All') return true;
      if (selectedStatusFilter == 'Preparing') return st == 'preparing';
      if (selectedStatusFilter == 'Payment Pending') return st == 'ready';
      return false;
    }).toList();

    int totalItems = visibleTables.length + visibleVirtuals.length;

    if (totalItems == 0) {
      return Center(
        child: Text(
          'Is category ($selectedStatusFilter) me koi table running nahi hai.',
          style: const TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int columns = constraints.maxWidth > 1100
            ? 6
            : (constraints.maxWidth > 700 ? 4 : (constraints.maxWidth > 450 ? 3 : 2));

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
                String kStatus = (oData['status'] ?? oData['kitchenStatus'] ?? 'pending').toString().toLowerCase();

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
                    _showTableDetailsModal(context, orderDoc);
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
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: statusDotColor),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$tableNumber',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: statusDotColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusDotColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isOccupied) ...[
                        const SizedBox(height: 4),
                        Text(
                          '₹${(orderDoc.get('totalPrice') ?? 0).toInt()}',
                          style: const TextStyle(
                            color: Color(0xFFF7B731),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }

            int virtualIndex = index - visibleTables.length;
            DocumentSnapshot vDoc = visibleVirtuals[virtualIndex];
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
              onTap: () => _showTableDetailsModal(context, vDoc),
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
                        Text('VIRTUAL', style: TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
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

  Widget _buildCompletedOrdersList(List<DocumentSnapshot> completedOrders) {
    if (completedOrders.isEmpty) {
      return const Center(child: Text('Aaj abhi tak koi order Done nahi hua.', style: TextStyle(color: Colors.white38)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: completedOrders.length,
      itemBuilder: (context, index) {
        var doc = completedOrders[index];
        var data = doc.data() as Map<String, dynamic>;

        String rawTitle = data['customerName'] ?? 'Order';
        String tableNo = data['tableNo'] ?? '';
        String displayTitle = _formatCustomerDisplayName(rawTitle, tableNo.isNotEmpty ? tableNo : null);

        return Card(
          color: const Color(0xFF1E1A17),
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.grey)),
          child: ListTile(
            leading: const Icon(Icons.done_all, color: Colors.green),
            title: Text(
              displayTitle,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Total: ₹${(data['totalPrice'] ?? 0).toInt()} • Paid Via: ${(data['paymentStatus'] ?? '').toString().toUpperCase()}',
              style: const TextStyle(color: Color(0xFFF7B731)),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
              child: const Text('DONE', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSegmentTab(String label, IconData icon) {
    bool isSelected = selectedStatusFilter == label;
    return InkWell(
      onTap: () => setState(() => selectedStatusFilter = label),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE65C00) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.white60),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color dotColor, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
      ],
    );
  }

  void _openReceiptForOrder(BuildContext context, String docId, Map<String, dynamic> oData) {
    Map<String, dynamic> bSettings = {
      'shopLogoBase64': shopLogoBase64,
      'shopName': shopNameController.text.trim(),
      'tagline': taglineController.text.trim(),
      'address': addressController.text.trim(),
      'mobileNumber': mobileNumberController.text.trim(),
      'gstNumber': gstNumberController.text.trim(),
      'receiptHeader': receiptHeaderController.text.trim(),
      'receiptFooter': receiptFooterController.text.trim(),
      'thankYouMessage': thankYouMsgController.text.trim(),
      'showGst': showGstToggle,
      'gstPercentage': gstPercentController.text.trim(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentCompleteReceiptScreen(
          orderData: oData,
          orderId: docId,
          businessSettings: bSettings,
        ),
      ),
    );
  }

  Widget _buildDashboardOverviewBody() {
    DateTime now = DateTime.now();
    DateTime startOfToday = DateTime(now.year, now.month, now.day);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)));

        var allDocs = snapshot.data!.docs;
        var todayOrders = allDocs.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          Timestamp? t = data['createdAt'] as Timestamp?;
          if (t == null) return false;
          return t.toDate().isAfter(startOfToday);
        }).toList();

        var activeOrders = todayOrders.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          return (data['status'] ?? 'pending').toString().toLowerCase() != 'completed';
        }).toList();

        var doneOrders = todayOrders.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          return (data['status'] ?? 'pending').toString().toLowerCase() == 'completed';
        }).toList();

        int compareDocs(DocumentSnapshot a, DocumentSnapshot b) {
          Timestamp? tA = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          Timestamp? tB = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          if (tA == null && tB == null) return 0;
          if (tA == null) return 1;
          if (tB == null) return -1;
          return tB.compareTo(tA);
        }

        activeOrders.sort(compareDocs);
        doneOrders.sort(compareDocs);

        var orderedList = [...activeOrders, ...doneOrders];

        double totalCollectedSales = 0.0;
        double cashSales = 0.0;
        double upiSales = 0.0;
        int pendingOrdersCount = 0;

        for (var doc in todayOrders) {
          var data = doc.data() as Map<String, dynamic>;
          double price = (data['totalPrice'] ?? 0.0).toDouble();
          String paymentStatus = (data['paymentStatus'] ?? 'pending').toString().toLowerCase();

          if (paymentStatus == 'paid_cash') {
            totalCollectedSales += price;
            cashSales += price;
          } else if (paymentStatus == 'paid_upi') {
            totalCollectedSales += price;
            upiSales += price;
          } else {
            pendingOrdersCount++;
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _buildDarkThemeMetricCard("Today's Sales", "₹${totalCollectedSales.toInt()}", Icons.trending_up, Colors.greenAccent)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildDarkThemeMetricCard("Today's Orders", "${todayOrders.length}", Icons.receipt_long_outlined, Colors.lightBlueAccent)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildDarkThemeMetricCard("Pending", "$pendingOrdersCount", Icons.assignment_late_outlined, Colors.deepOrangeAccent)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildDarkThemeMetricCard("Cash", "₹${cashSales.toInt()}", Icons.account_balance_wallet_outlined, const Color(0xFFF7B731))),
                  const SizedBox(width: 8),
                  Expanded(child: _buildDarkThemeMetricCard("UPI", "₹${upiSales.toInt()}", Icons.qr_code_2_outlined, const Color(0xFFE65C00))),
                ],
              ),
              const SizedBox(height: 22),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.list_alt_rounded, color: Color(0xFFF7B731), size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        "Today's Orders Queue",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFF7B731)),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF26201D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF382F2A)),
                    ),
                    child: Text(
                      '${activeOrders.length} Running • ${doneOrders.length} Done',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              orderedList.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Text('Aaj abhi tak koi order record nahi hua.', style: TextStyle(color: Colors.white38)),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: orderedList.length,
                      itemBuilder: (context, index) {
                        var doc = orderedList[index];
                        var data = doc.data() as Map<String, dynamic>;

                        String status = (data['status'] ?? 'pending').toString().toLowerCase();
                        bool isDone = status == 'completed';

                        Color statusColor = Colors.redAccent;
                        String statusText = 'Ordered';

                        if (isDone) {
                          statusColor = Colors.green;
                          statusText = 'Done';
                        } else if (status == 'preparing') {
                          statusColor = Colors.amber;
                          statusText = 'Cooking';
                        } else if (status == 'ready') {
                          statusColor = Colors.blueAccent;
                          statusText = 'Ready / Pay';
                        }

                        String rawName = (data['customerName'] ?? 'Walk-in Guest').toString();
                        String table = (data['tableNo'] ?? '').toString();
                        String displayName = _formatCustomerDisplayName(rawName, table.isNotEmpty ? table : null);
                        double total = (data['totalPrice'] ?? 0.0).toDouble();
                        List items = data['items'] ?? [];
                        
                        // Items ki summary list (e.g. Pizza x1, Coke x2)
                        String itemsSummary = items.map((it) => "${it['name']} (x${it['qty']})").join(', ');

                        Timestamp? t = data['createdAt'] as Timestamp?;
                        DateTime orderDt = t?.toDate() ?? DateTime.now();
                        String timeStr = '${orderDt.hour.toString().padLeft(2, '0')}:${orderDt.minute.toString().padLeft(2, '0')}';

                        return Card(
                          color: isDone ? const Color(0xFF191614) : const Color(0xFF1E1A17),
                          margin: const EdgeInsets.only(bottom: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isDone ? const Color(0xFF2C2520) : statusColor.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: statusColor.withOpacity(0.5)),
                                  ),
                                  child: Text(
                                    statusText.toUpperCase(),
                                    style: TextStyle(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName,
                                        style: TextStyle(
                                          color: isDone ? Colors.white70 : Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '$timeStr • ₹${total.toInt()}',
                                        style: const TextStyle(color: Color(0xFFF7B731), fontSize: 11.5, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Items: $itemsSummary',
                                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),

                                IconButton(
                                  icon: const Icon(Icons.print_rounded, color: Colors.greenAccent, size: 20),
                                  tooltip: 'Print Receipt',
                                  onPressed: () => _openReceiptForOrder(context, doc.id, data),
                                ),

                                if (!isDone)
                                  IconButton(
                                    icon: const Icon(Icons.edit_rounded, color: Colors.blueAccent, size: 18),
                                    tooltip: 'Edit Order',
                                    onPressed: () => prepareOrderForm(doc: doc),
                                  ),

                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                  tooltip: 'Delete Order',
                                  onPressed: () => _confirmDeleteOrder(context, doc.id, displayName),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuManagementBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('menu_categories').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)));
        }

        var categoryDocs = snapshot.data!.docs;

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: const Color(0xFFE65C00),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Add Category', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _showAddCategoryDialog(context),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1A17),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2C2520)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Default Menu Sync', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('Code ka default menu restore karein', style: TextStyle(color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF7B731),
                          side: const BorderSide(color: Color(0xFFF7B731)),
                        ),
                        onPressed: () => _uploadMenuToFirebase(context),
                        icon: const Icon(Icons.sync, size: 16),
                        label: const Text('Sync Default', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                if (categoryDocs.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Text('Menu khali hai! Sync dabayein ya nayi Category add karein.', style: TextStyle(color: Colors.white38)),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: categoryDocs.length,
                    itemBuilder: (context, catIndex) {
                      var catDoc = categoryDocs[catIndex];
                      var catData = catDoc.data() as Map<String, dynamic>;
                      String catName = catData['categoryName'] ?? 'Unnamed Category';
                      List items = List.from(catData['items'] ?? []);

                      return Card(
                        color: const Color(0xFF1E1A17),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFF2C2520)),
                        ),
                        child: ExpansionTile(
                          collapsedIconColor: Colors.white54,
                          iconColor: const Color(0xFFF7B731),
                          title: Row(
                            children: [
                              Text(
                                catName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFF7B731)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2C2520),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('${items.length} items', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 22),
                                tooltip: 'Add Item to $catName',
                                onPressed: () => _showAddItemDialog(context, catDoc.id, catName, items),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                tooltip: 'Delete Category',
                                onPressed: () => _deleteCategory(catDoc.id, catName),
                              ),
                            ],
                          ),
                          children: [
                            const Divider(color: Color(0xFF2C2520), height: 1),
                            if (items.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(14.0),
                                child: Text('Is category me koi item nahi hai. (+) dabakar add karein.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const Divider(color: Color(0xFF26211D), height: 1),
                                itemBuilder: (context, itemIdx) {
                                  var item = items[itemIdx];
                                  var regP = item['regularPrice'];
                                  var medP = item['mediumPrice'];
                                  var stdP = item['price'];

                                  String priceDisplay = '';
                                  if (regP != null && medP != null) {
                                    priceDisplay = '₹$regP / ₹$medP';
                                  } else {
                                    priceDisplay = '₹${stdP ?? regP ?? 0}';
                                  }

                                  return ListTile(
                                    dense: true,
                                    title: Text(item['name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                    subtitle: (item['desc'] != null && item['desc'].toString().isNotEmpty)
                                        ? Text(item['desc'].toString(), style: const TextStyle(color: Colors.white38, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)
                                        : null,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(priceDisplay, style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold, fontSize: 13)),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                          onPressed: () => _deleteMenuItem(catDoc.id, items, itemIdx),
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
            ),
          ),
        );
      },
    );
  }

  void _showAddCategoryDialog(BuildContext context) {
    final TextEditingController categoryController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE65C00))),
        title: const Text('Add New Category', style: TextStyle(color: Color(0xFFF7B731), fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: categoryController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Category Name',
            hintText: 'e.g. Cold Drinks, Dips, Desserts',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
            onPressed: () async {
              String catName = categoryController.text.trim();
              if (catName.isEmpty) return;
              Navigator.pop(ctx);

              await FirebaseFirestore.instance.collection('menu_categories').add({
                'categoryName': catName,
                'items': [],
              });
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Category "$catName" add ho gayi!'), backgroundColor: Colors.green));
            },
            child: const Text('Save Category'),
          ),
        ],
      ),
    );
  }

  void _showAddItemDialog(BuildContext context, String catDocId, String catName, List currentItems) {
    final TextEditingController itemNameController = TextEditingController();
    final TextEditingController itemDescController = TextEditingController();
    final TextEditingController regPriceController = TextEditingController();
    final TextEditingController medPriceController = TextEditingController();
    final TextEditingController singlePriceController = TextEditingController();

    bool isMultiPrice = catName.toLowerCase().contains('pizza') || catName.toLowerCase().contains('fries') || catName.toLowerCase().contains('bread');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1A17),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE65C00))),
          title: Text('Add Item in "$catName"', style: const TextStyle(color: Color(0xFFF7B731), fontSize: 15, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: itemNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: itemDescController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Description (Optional)', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Regular & Medium Size?', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const Spacer(),
                    Switch(
                      value: isMultiPrice,
                      activeColor: const Color(0xFFE65C00),
                      onChanged: (val) => setDialogState(() => isMultiPrice = val),
                    ),
                  ],
                ),
                if (isMultiPrice) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: regPriceController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(labelText: 'Regular ₹', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: medPriceController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(labelText: 'Medium ₹', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  TextField(
                    controller: singlePriceController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Price (₹)', border: OutlineInputBorder(), isDense: true),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
              onPressed: () async {
                String name = itemNameController.text.trim();
                if (name.isEmpty) return;

                Map<String, dynamic> newItem = {
                  'name': name,
                  'desc': itemDescController.text.trim(),
                };

                if (isMultiPrice) {
                  double regP = double.tryParse(regPriceController.text.trim()) ?? 0.0;
                  double medP = double.tryParse(medPriceController.text.trim()) ?? 0.0;
                  newItem['regularPrice'] = regP;
                  newItem['mediumPrice'] = medP;
                } else {
                  double p = double.tryParse(singlePriceController.text.trim()) ?? 0.0;
                  newItem['price'] = p;
                }

                Navigator.pop(ctx);
                List updated = List.from(currentItems)..add(newItem);
                await FirebaseFirestore.instance.collection('menu_categories').doc(catDocId).update({'items': updated});

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Item "$name" add ho gaya!'), backgroundColor: Colors.green));
              },
              child: const Text('Add Item'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteCategory(String catDocId, String catName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Category', style: TextStyle(color: Color(0xFFF7B731))),
        content: Text('Kya aap "$catName" category aur uske sabhi items ko delete karna chahte hain?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseFirestore.instance.collection('menu_categories').doc(catDocId).delete();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _deleteMenuItem(String catDocId, List currentItems, int itemIndex) async {
    List updated = List.from(currentItems)..removeAt(itemIndex);
    await FirebaseFirestore.instance.collection('menu_categories').doc(catDocId).update({'items': updated});
  }

  Widget _buildSettingsBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingsSectionHeader(Icons.badge_outlined, 'Business Information'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _settingsCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSettingsTextField(shopNameController, 'Shop Name *', Icons.storefront_outlined),
                const SizedBox(height: 12),
                _buildSettingsTextField(taglineController, 'Tagline', Icons.short_text_outlined),
                const SizedBox(height: 12),
                _buildSettingsTextField(ownerNameController, 'Owner Name', Icons.person_outline),
                const SizedBox(height: 12),
                _buildSettingsTextField(mobileNumberController, 'Mobile Number *', Icons.phone_outlined, keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                _buildSettingsTextField(emailController, 'Email', Icons.mail_outline, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 12),
                _buildSettingsTextField(gstNumberController, 'GST Number', Icons.receipt_outlined),
                const SizedBox(height: 12),
                _buildSettingsTextField(addressController, 'Address', Icons.location_on_outlined, maxLines: 2),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _buildSettingsSectionHeader(Icons.branding_watermark_outlined, 'Branding'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _settingsCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Shop Logo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                const Text(
                  'Shown on the dashboard, splash screen, and receipts. Stored with your shop settings so it syncs across all devices.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF382F2A)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: shopLogoBase64 != null && shopLogoBase64!.isNotEmpty
                            ? Image.memory(base64Decode(shopLogoBase64!), fit: BoxFit.contain)
                            : const FlamyWoodOvenLogo(size: 65),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFF7B731),
                                side: const BorderSide(color: Color(0xFF7A431D), width: 1.5),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: _pickAndUploadLogo,
                              icon: const Icon(Icons.file_upload_outlined, size: 18),
                              label: const Text('Upload Logo', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(foregroundColor: Colors.redAccent.shade100),
                              onPressed: _removeLogo,
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('Remove Logo', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _buildSettingsSectionHeader(Icons.print_outlined, 'Printer'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _settingsCardDecoration(),
            child: InkWell(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1A17),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    title: const Text('Connect Thermal Printer', style: TextStyle(color: Color(0xFFF7B731))),
                    content: const Text(
                      'Bluetooth / USB / COM port scanner scanning for available 58mm & 80mm thermal printers...',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: Color(0xFFE65C00)))),
                    ],
                  ),
                );
              },
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.print, color: Colors.tealAccent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Connect Thermal Printer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                        SizedBox(height: 3),
                        Text('Scan and select your Bluetooth / COM printer for receipts.', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white38),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _buildSettingsSectionHeader(Icons.receipt_long_outlined, 'Receipt Settings'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _settingsCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSettingsTextField(receiptHeaderController, 'Receipt Header', Icons.title_outlined),
                const SizedBox(height: 12),
                _buildSettingsTextField(receiptFooterController, 'Receipt Footer', Icons.subtitles_outlined),
                const SizedBox(height: 12),
                _buildSettingsTextField(thankYouMsgController, 'Thank You Message', Icons.favorite_border),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.calculate_outlined, color: Colors.blueAccent, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Text('Show GST', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const Spacer(),
                    Switch(
                      value: showGstToggle,
                      activeColor: const Color(0xFFE65C00),
                      onChanged: (val) => setState(() => showGstToggle = val),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                _buildSettingsTextField(gstPercentController, 'GST Percentage (%)', Icons.percent, keyboardType: TextInputType.number),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(child: _buildSettingsTextField(currencySymbolController, 'Currency Symbol', Icons.attach_money)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildSettingsTextField(currencyCodeController, 'Currency Code', Icons.code)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _buildSettingsSectionHeader(Icons.tune_outlined, 'Business Settings'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _settingsCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: const Color(0xFFE65C00).withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.restaurant, color: Color(0xFFE65C00), size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Text('Default Order Type', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const Spacer(),
                    DropdownButton<String>(
                      value: defaultOrderType,
                      dropdownColor: const Color(0xFF26211D),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'Dine-In', child: Text('Dine-In')),
                        DropdownMenuItem(value: 'Takeaway', child: Text('Takeaway')),
                      ],
                      onChanged: (val) => setState(() => defaultOrderType = val!),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                _buildSettingsTextField(defaultTaxController, 'Default Tax (%)', Icons.account_balance_outlined, keyboardType: TextInputType.number),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.cyan.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.tag, color: Colors.cyanAccent, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Text('Auto Generate Bill Number', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const Spacer(),
                    Switch(
                      value: autoGenBillNumber,
                      activeColor: const Color(0xFFE65C00),
                      onChanged: (val) => setState(() => autoGenBillNumber = val),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.purple.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.receipt, color: Colors.purpleAccent, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Text('Auto Generate Token Number', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const Spacer(),
                    Switch(
                      value: autoGenTokenNumber,
                      activeColor: const Color(0xFFE65C00),
                      onChanged: (val) => setState(() => autoGenTokenNumber = val),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                _buildSettingsTextField(
                  numberOfTablesController,
                  'Number of Tables',
                  Icons.table_restaurant_outlined,
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Logout Staff Portal', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildSettingsSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFF7A431D).withOpacity(0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: const Color(0xFFF7B731), size: 16),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }

  BoxDecoration _settingsCardDecoration() {
    return BoxDecoration(
      color: const Color(0xFF1B1715),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF2C2520)),
    );
  }

  Widget _buildSettingsTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        prefixIcon: Icon(icon, color: const Color(0xFFF7B731), size: 17),
        filled: true,
        fillColor: const Color(0xFF231E1B),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF382F2A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF382F2A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE65C00)),
        ),
      ),
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
              LayoutBuilder(
                builder: (context, constraints) {
                  bool isWide = constraints.maxWidth > 700;
                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: tableNoController,
                            style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              labelText: 'Table / Counter',
                              labelStyle: TextStyle(color: Color(0xFFF7B731)),
                              prefixIcon: Icon(Icons.table_restaurant, color: Color(0xFFF7B731)),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: customerPhoneController,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Mobile Number',
                              hintText: '10 digits mobile',
                              prefixIcon: const Icon(Icons.phone, color: Colors.green),
                              suffixIcon: isSearchingCustomer
                                  ? const Padding(
                                      padding: EdgeInsets.all(12.0),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE65C00)),
                                      ),
                                    )
                                  : null,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (val) {
                              if (val.trim().length >= 10) {
                                _fetchCustomerNameByPhone(val);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: customerNameController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Customer Name (Auto-fetched)',
                              prefixIcon: Icon(Icons.person, color: Color(0xFFE65C00)),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        TextField(
                          controller: tableNoController,
                          style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            labelText: 'Table / Counter',
                            labelStyle: TextStyle(color: Color(0xFFF7B731)),
                            prefixIcon: Icon(Icons.table_restaurant, color: Color(0xFFF7B731)),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: customerPhoneController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Mobile Number',
                            hintText: '10 digits mobile',
                            prefixIcon: const Icon(Icons.phone, color: Colors.green),
                            suffixIcon: isSearchingCustomer
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE65C00)),
                                    ),
                                  )
                                : null,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (val) {
                            if (val.trim().length >= 10) {
                              _fetchCustomerNameByPhone(val);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: customerNameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Customer Name (Auto-fetched)',
                            prefixIcon: Icon(Icons.person, color: Color(0xFFE65C00)),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    );
                  }
                },
              ),

              if (previousOrderItems.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF26201D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF7B731).withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.history_rounded, color: Color(0xFFF7B731), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Previous Order ($previousOrderDateStr):',
                                style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: () {
                              setState(() {
                                for (var item in previousOrderItems) {
                                  tempCart.add({
                                    'name': item['name'],
                                    'price': item['price'],
                                    'size': item['size'] ?? 'Standard',
                                    'qty': item['qty'] ?? 1,
                                    'isDone': false,
                                  });
                                }
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Previous items cart me add ho gaye!'), duration: Duration(seconds: 1)),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE65C00),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '+ Add Same Items',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: previousOrderItems.map<Widget>((item) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B1715),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF382F2A)),
                            ),
                            child: Text(
                              '${item['name']} (${item['size'] ?? 'Std'}) x${item['qty']}',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

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
              const SizedBox(height: 10),

              TextField(
                controller: menuSearchController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Search Menu...', prefixIcon: Icon(Icons.search, color: Color(0xFFE65C00)), border: OutlineInputBorder(), isDense: true),
                onChanged: (val) => setState(() => menuSearchQuery = val.toLowerCase().trim()),
              ),
              const Divider(color: Color(0xFF2C2520), height: 22),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: liveMenuCategories.length,
                itemBuilder: (context, catIndex) {
                  var category = liveMenuCategories[catIndex];
                  String catName = category['categoryName'] ?? '';
                  List items = category['items'] ?? [];

                  var filteredItems = items.where((item) {
                    if (menuSearchQuery.isEmpty) return true;
                    return item['name'].toString().toLowerCase().contains(menuSearchQuery);
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
              const Divider(color: Color(0xFF2C2520), height: 20),
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

              if (showGstToggle && tempCart.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1A17),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2C2520)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Subtotal:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text('₹${calcTempSubtotal.toInt()}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('GST (${gstPercentController.text}%):', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          Text('₹${(calcTempTotal - calcTempSubtotal).toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
                  onPressed: saveOrderToFirebase,
                  child: Text(
                    editingOrderDoc == null ? 'Place Order (₹${calcTempTotal.toInt()}) 🔥' : 'Update Order (₹${calcTempTotal.toInt()}) 🔥',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDarkThemeMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1715),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color), maxLines: 1),
          const SizedBox(height: 3),
          Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white70), maxLines: 1),
        ],
      ),
    );
  }
}