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
      debugPrint("Error updating status: $e");
    }
  }

  void confirmAndToggleCaptainItem(BuildContext context, String docId, List currentItems, int itemIndex) {
    var item = currentItems[itemIndex];
    bool currentVal = item['isDone'] ?? false;
    String actionText = currentVal ? "unmark" : "ready mark";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Item Status', style: TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold)),
        content: Text('Kya aap "${item['name']}" ko $actionText karna chahte hain?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
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
            child: const Text('Confirm'),
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
      debugPrint("Error toggling captain item: $e");
    }
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold)),
        content: const Text('Captain dashboard se logout karna hai?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE65C00), foregroundColor: Colors.white),
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
    // Aaj ke din ka exact midnight timestamp (00:00:00)
    DateTime now = DateTime.now();
    DateTime startOfToday = DateTime(now.year, now.month, now.day);

    return Scaffold(
      backgroundColor: const Color(0xFF141211),
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.local_fire_department, color: Color(0xFFE65C00), size: 24),
            SizedBox(width: 8),
            Text('FLAMY WOOD • Kitchen Queue', style: TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          ],
        ),
        backgroundColor: const Color(0xFF1E1A17),
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFE65C00)),
            tooltip: 'Logout',
            onPressed: () => _logout(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        color: const Color(0xFF141211),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text('Aaj ke din me koi active order nahi hai queue me!', style: TextStyle(fontSize: 16, color: Colors.white38)),
              );
            }

            // Sirf wahi orders jo aaj ke hain aur completed nahi hue hain
            final orders = snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              String status = data['status'] ?? 'pending';
              return status != 'completed';
            }).toList();

            if (orders.isEmpty) {
              return const Center(
                child: Text('Sabhi active orders ready / completed hain! 🔥', style: TextStyle(fontSize: 16, color: Colors.white38)),
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

              if (pA != pB) return pA.compareTo(pB);

              Timestamp? timeA = dataA['createdAt'] as Timestamp?;
              Timestamp? timeB = dataB['createdAt'] as Timestamp?;
              if (timeA != null && timeB != null) {
                return timeA.compareTo(timeB);
              }
              return 0;
            });

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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

                Color statusColor = const Color(0xFFE65C00);
                if (status == 'preparing') statusColor = Colors.amber;
                if (status == 'ready') statusColor = Colors.green;

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1816),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: hasNewItems ? Colors.purpleAccent : const Color(0xFF2E2621),
                      width: hasNewItems ? 2 : 1,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: hasNewItems ? Colors.purple.withOpacity(0.2) : const Color(0xFFE65C00).withOpacity(0.2),
                                    border: Border.all(color: hasNewItems ? Colors.purpleAccent : const Color(0xFFE65C00)),
                                  ),
                                  child: Icon(
                                    hasNewItems ? Icons.notification_important : Icons.local_fire_department,
                                    color: hasNewItems ? Colors.purpleAccent : const Color(0xFFE65C00),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Queue #${index + 1} • $customerName',
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    if (hasNewItems)
                                      const Text(
                                        'REPEAT ORDER / NEW ITEMS!',
                                        style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: statusColor),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1),
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Color(0xFF2E2621), height: 22),
                        const Text(
                          'ITEMS ORDERED (TAP ITEM TO MARK READY):',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white54, fontSize: 11, letterSpacing: 0.8),
                        ),
                        const SizedBox(height: 8),
                        ...items.asMap().entries.map((entry) {
                          int itemIdx = entry.key;
                          var item = entry.value;
                          bool isDone = item['isDone'] ?? false;
                          bool isNewInRepeat = !isDone && (hasAlreadyDoneItems || hasNewItems);

                          return InkWell(
                            onTap: () => confirmAndToggleCaptainItem(context, orderDoc.id, items, itemIdx),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: isDone ? Colors.green.withOpacity(0.08) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        isDone
                                            ? Icons.check_circle_rounded
                                            : (isNewInRepeat ? Icons.fiber_new_rounded : Icons.radio_button_unchecked_rounded),
                                        color: isDone ? Colors.greenAccent : (isNewInRepeat ? Colors.purpleAccent : Colors.white38),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '${item['name']} (${item['size']})',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: isDone ? Colors.greenAccent : (isNewInRepeat ? Colors.purpleAccent : Colors.white),
                                          fontWeight: isDone || isNewInRepeat ? FontWeight.bold : FontWeight.w600,
                                          decoration: isDone ? TextDecoration.lineThrough : null,
                                          decorationColor: Colors.greenAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    'x ${item['qty']}',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFFF7B731)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const Divider(color: Color(0xFF2E2621), height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total: ₹${totalPrice.toInt()}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFF7B731)),
                            ),
                            Row(
                              children: [
                                if (status == 'pending')
                                  ElevatedButton.icon(
                                    onPressed: () => updateOrderStatus(orderDoc.id, 'preparing'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE65C00),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.fireplace, size: 18),
                                    label: const Text('Start Preparing', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                if (status == 'preparing')
                                  ElevatedButton.icon(
                                    onPressed: () => updateOrderStatus(orderDoc.id, 'ready'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.check_circle, size: 18),
                                    label: const Text('Mark Ready', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                if (status == 'ready')
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.green),
                                    ),
                                    child: const Text(
                                      'Order Ready to Serve 🔥',
                                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
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
      ),
    );
  }
}