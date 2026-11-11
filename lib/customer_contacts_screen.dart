import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/data/firestore_paths.dart';

class CustomerContactsScreen extends StatefulWidget {
  const CustomerContactsScreen({super.key});

  @override
  State<CustomerContactsScreen> createState() => _CustomerContactsScreenState();
}

class _CustomerContactsScreenState extends State<CustomerContactsScreen> {
  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141211),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7A431D),
        elevation: 0,
        title: const Text(
          'Customer Directory',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: const Color(0xFF221D1A),
            child: TextField(
              controller: searchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search customer by name or phone number...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: Color(0xFFF7B731), size: 18),
                filled: true,
                fillColor: const Color(0xFF181513),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => searchQuery = val.toLowerCase().trim()),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirestorePaths.orders().snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)));
                }

                // Client-side sort by createdAt descending (Index-free)
                var docs = snapshot.data!.docs.toList();
                docs.sort((a, b) {
                  var dataA = a.data() as Map<String, dynamic>;
                  var dataB = b.data() as Map<String, dynamic>;
                  Timestamp? tA = dataA['createdAt'] as Timestamp?;
                  Timestamp? tB = dataB['createdAt'] as Timestamp?;
                  if (tA == null && tB == null) return 0;
                  if (tA == null) return 1;
                  if (tB == null) return -1;
                  return tB.compareTo(tA);
                });

                // Customer Aggregation Map
                Map<String, Map<String, dynamic>> customersMap = {};

                for (var doc in docs) {
                  var data = doc.data() as Map<String, dynamic>;
                  String status = (data['status'] ?? '').toString().toLowerCase();

                  // Sirf Completed / Payment Done orders ko consider karein
                  if (status != 'completed') continue;

                  String rawName = (data['customerName'] ?? '').toString();
                  String phone = (data['customerPhone'] ?? '').toString().trim();

                  String cleanName = rawName
                      .replaceAll(r'$1', '')
                      .replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '')
                      .trim();

                  // Auto-correct any previously swapped records in database
                  if (RegExp(r'^[a-zA-Z\s]+$').hasMatch(phone) && RegExp(r'^\d{10}').hasMatch(cleanName)) {
                    String temp = cleanName;
                    cleanName = phone;
                    phone = temp;
                  }

                  if (cleanName.isEmpty) cleanName = 'Walk-in Guest';

                  String key = phone.isNotEmpty ? phone : cleanName.toLowerCase();
                  double price = (data['totalPrice'] ?? 0.0).toDouble();
                  List items = data['items'] ?? [];
                  Timestamp? createdAt = data['createdAt'] as Timestamp?;

                  if (!customersMap.containsKey(key)) {
                    // First time encountering = Most recent completed order (override items)
                    customersMap[key] = {
                      'name': cleanName,
                      'phone': phone,
                      'totalOrders': 1,
                      'totalSpent': price,
                      'latestOrder': {
                        'orderId': doc.id,
                        'date': createdAt?.toDate() ?? DateTime.now(),
                        'totalPrice': price,
                        'items': items,
                        'tableNo': data['tableNo'] ?? '',
                      },
                    };
                  } else {
                    // Repeat orders: total spend and orders increment, but latest items stay active
                    customersMap[key]!['totalOrders'] = (customersMap[key]!['totalOrders'] as int) + 1;
                    customersMap[key]!['totalSpent'] = (customersMap[key]!['totalSpent'] as double) + price;
                  }
                }

                var customerList = customersMap.values.toList();

                if (searchQuery.isNotEmpty) {
                  customerList = customerList.where((cust) {
                    String name = (cust['name'] ?? '').toString().toLowerCase();
                    String phone = (cust['phone'] ?? '').toString().toLowerCase();
                    return name.contains(searchQuery) || phone.contains(searchQuery);
                  }).toList();
                }

                if (customerList.isEmpty) {
                  return const Center(
                    child: Text('Koi completed customer data nahi mila!', style: TextStyle(color: Colors.white38)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: customerList.length,
                  itemBuilder: (context, index) {
                    var customer = customerList[index];
                    String name = customer['name'] ?? 'Guest';
                    String phone = customer['phone'] ?? '';
                    int totalOrders = customer['totalOrders'] ?? 0;
                    double totalSpent = customer['totalSpent'] ?? 0.0;
                    Map<String, dynamic> latestOrder = customer['latestOrder'] ?? {};
                    List items = latestOrder['items'] ?? [];
                    DateTime date = latestOrder['date'] ?? DateTime.now();
                    String dateStr = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                    String tableNo = latestOrder['tableNo'] ?? '';

                    return Card(
                      color: const Color(0xFF1E1A17),
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFF2C2520)),
                      ),
                      child: ExpansionTile(
                        collapsedIconColor: Colors.white54,
                        iconColor: const Color(0xFFF7B731),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF7A431D).withOpacity(0.4),
                          child: const Icon(Icons.person, color: Color(0xFFF7B731), size: 20),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$totalOrders Orders',
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            children: [
                              Icon(Icons.phone, size: 12, color: phone.isNotEmpty ? Colors.white60 : Colors.white24),
                              const SizedBox(width: 4),
                              Text(
                                phone.isNotEmpty ? phone : 'No phone number',
                                style: TextStyle(color: phone.isNotEmpty ? Colors.white70 : Colors.white24, fontSize: 12),
                              ),
                              const Spacer(),
                              Text(
                                'Spent: ₹${totalSpent.toInt()}',
                                style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.w900, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        children: [
                          const Divider(color: Color(0xFF2C2520), height: 1),
                          // Latest Order Items (Updated after payment)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Last Paid Order Items (Active):',
                                      style: TextStyle(color: Color(0xFFF7B731), fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      '₹${(latestOrder['totalPrice'] ?? 0).toInt()}',
                                      style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$dateStr ${tableNo.isNotEmpty ? '• $tableNo' : ''}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: items.map<Widget>((it) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF26211D),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF382F2A)),
                                      ),
                                      child: Text(
                                        '${it['name']} (${it['size'] ?? 'Std'}) x${it['qty']}',
                                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
