import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';

class CaptainDashboardScreen extends StatelessWidget {
  const CaptainDashboardScreen({super.key});

  void updateOrderStatus(String docId, String newStatus) async {
    try {
      Map<String, dynamic> updateData = {
        'status': newStatus,
        'kitchenStatus': newStatus,
      };
      if (newStatus == 'ready') {
        updateData['hasNewItemsAdded'] = false;
      }
      await FirebaseFirestore.instance.collection('orders').doc(docId).update(updateData);
    } catch (e) {
      print("Error updating status: $e");
    }
  }

  void confirmAndToggleCaptainItem(BuildContext context, String docId, List currentItems, int itemIndex) {
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
              _toggleCaptainItemDone(docId, currentItems, itemIndex);
            },
            child: const Text('Yes, Confirm'),
          ),
        ],
      ),
    );
  }

  void _toggleCaptainItemDone(String docId, List currentItems, int itemIndex) async {
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
      print("Error toggling captain item: $e");
    }
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout Confirmation'),
        content: const Text('Kya aap Captain dashboard se logout karna chahte hain?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const StaffLoginHomeScreen()),
                (route) => false,
              );
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Captain Kitchen Dashboard (Queue)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepOrange[800],
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Logout',
            onPressed: () => _logout(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'Koi active order nahi hai queue me!',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          final orders = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            String status = data['status'] ?? 'pending';
            return status != 'completed';
          }).toList();

          if (orders.isEmpty) {
            return const Center(
              child: Text(
                'Sabhi orders ready hain!',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          orders.sort((a, b) {
            var dataA = a.data() as Map<String, dynamic>;
            var dataB = b.data() as Map<String, dynamic>;

            int getPriority(Map<String, dynamic> data) {
              String s = data['status'] ?? 'pending';
              bool isRepeat = data['hasNewItemsAdded'] ?? false;

              if (s == 'preparing') return 1;
              if (s == 'pending' && !isRepeat) return 2;
              if (s == 'pending' && isRepeat) return 3;
              if (s == 'ready') return 4;
              return 5;
            }

            int pA = getPriority(dataA);
            int pB = getPriority(dataB);

            if (pA != pB) {
              return pA.compareTo(pB);
            }

            Timestamp? timeA = dataA['createdAt'] as Timestamp?;
            Timestamp? timeB = dataB['createdAt'] as Timestamp?;
            if (timeA != null && timeB != null) {
              return timeA.compareTo(timeB);
            }
            return 0;
          });

          return ListView.builder(
            padding: const EdgeInsets.all(20.0),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final orderDoc = orders[index];
              final orderData = orderDoc.data() as Map<String, dynamic>;
              
              final String customerName = orderData['customerName'] ?? 'Unknown';
              final double totalPrice = (orderData['totalPrice'] ?? 0.0).toDouble();
              final String status = orderData['status'] ?? 'pending';
              final List items = orderData['items'] ?? [];
              final bool hasNewItems = orderData['hasNewItemsAdded'] ?? false;

              bool hasAlreadyDoneItems = items.any((e) => (e['isDone'] ?? false) == true);

              Color statusColor = Colors.orange;
              if (status == 'preparing') statusColor = Colors.blue;
              if (status == 'ready') statusColor = Colors.green;

              return Card(
                elevation: 4,
                shadowColor: Colors.black26,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: hasNewItems ? const BorderSide(color: Colors.purple, width: 3) : BorderSide.none,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: hasNewItems ? Colors.purple : Colors.deepOrange,
                                child: Icon(hasNewItems ? Icons.notification_important : Icons.fastfood, color: Colors.white),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Queue #${index + 1} - $customerName',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  if (hasNewItems)
                                    const Text(
                                      'REPEAT ORDER / NEW ITEMS ADDED!',
                                      style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: statusColor),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      const Text('Items Ordered (Tap item to toggle ready):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 8),
                      ...items.asMap().entries.map((entry) {
                        int itemIdx = entry.key;
                        var item = entry.value;
                        bool isDone = item['isDone'] ?? false;
                        bool isNewInRepeat = !isDone && (hasAlreadyDoneItems || hasNewItems);

                        return InkWell(
                          onTap: () => confirmAndToggleCaptainItem(context, orderDoc.id, items, itemIdx),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    if (isDone) ...[
                                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                      const SizedBox(width: 6),
                                    ] else if (isNewInRepeat) ...[
                                      const Icon(Icons.fiber_new, color: Colors.purple, size: 20),
                                      const SizedBox(width: 6),
                                    ] else ...[
                                      const Icon(Icons.radio_button_unchecked, color: Colors.grey, size: 20),
                                      const SizedBox(width: 6),
                                    ],
                                    Text(
                                      '• ${item['name']} (${item['size']})',
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: isDone ? Colors.green[800] : (isNewInRepeat ? Colors.purple[900] : Colors.black),
                                        fontWeight: isDone || isNewInRepeat ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                                Text('x ${item['qty']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        );
                      }),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total: ₹$totalPrice',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                          ),
                          Row(
                            children: [
                              if (status == 'pending')
                                ElevatedButton.icon(
                                  onPressed: () => updateOrderStatus(orderDoc.id, 'preparing'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                                  icon: const Icon(Icons.fireplace, size: 16),
                                  label: const Text('Start Preparing'),
                                ),
                              if (status == 'preparing')
                                ElevatedButton.icon(
                                  onPressed: () => updateOrderStatus(orderDoc.id, 'ready'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                  icon: const Icon(Icons.check_circle, size: 16),
                                  label: const Text('Mark Ready'),
                                ),
                              if (status == 'ready')
                                const Text(
                                  'Order Ready',
                                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}