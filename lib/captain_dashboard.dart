import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';

class CaptainDashboardScreen extends StatelessWidget {
  const CaptainDashboardScreen({super.key});

  void updateOrderStatus(String docId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(docId).update({
        'status': newStatus,
        'kitchenStatus': newStatus,
      });
    } catch (e) {
      print("Error updating status: $e");
    }
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔒 Logout Confirmation'),
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
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: const Text('👨‍🍳 Captain Kitchen Dashboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text(
                  'Koi active order nahi hai abhi!',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              );
            }

            final orders = snapshot.data!.docs;

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

                Color statusColor = Colors.orange;
                if (status == 'preparing') statusColor = Colors.blue;
                if (status == 'ready') statusColor = Colors.green;
                if (status == 'completed') statusColor = Colors.grey;

                return Card(
                  elevation: 4,
                  shadowColor: Colors.black26,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                                const CircleAvatar(
                                  backgroundColor: Colors.deepOrange,
                                  child: Icon(Icons.fastfood, color: Colors.white),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Customer: $customerName',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                        const Text('Items Ordered:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 8),
                        ...items.map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('• ${item['name']} (${item['size']})', style: const TextStyle(fontSize: 15)),
                                Text('x ${item['qty']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
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
                                  ElevatedButton.icon(
                                    onPressed: () => updateOrderStatus(orderDoc.id, 'completed'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white),
                                    icon: const Icon(Icons.done_all, size: 16),
                                    label: const Text('Complete'),
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