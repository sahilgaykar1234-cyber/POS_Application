import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CaptainDashboardScreen extends StatefulWidget {
  const CaptainDashboardScreen({super.key});

  @override
  State<CaptainDashboardScreen> createState() => _CaptainDashboardScreenState();
}

class _CaptainDashboardScreenState extends State<CaptainDashboardScreen> {
  Future<void> updateOrderStatus(String docId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(docId).update({
        'status': newStatus,
        'kitchenStatus': newStatus,
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

  @override
  Widget build(BuildContext context) {
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
            tooltip: 'Refresh Orders',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)));
          }

          var allDocs = snapshot.data!.docs;
          
          // Aaj ke wohi orders jo completed nahi hain
          var activeOrders = allDocs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            Timestamp? t = data['createdAt'] as Timestamp?;
            if (t == null) return false;
            if (!t.toDate().isAfter(startOfToday)) return false;
            
            String status = (data['status'] ?? 'pending').toString().toLowerCase();
            return status != 'completed';
          }).toList();

          // Latest order sabse upar dikhega
          activeOrders.sort((a, b) {
            Timestamp? tA = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            Timestamp? tB = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            if (tA == null && tB == null) return 0;
            if (tA == null) return 1;
            if (tB == null) return -1;
            return tB.compareTo(tA);
          });

          if (activeOrders.isEmpty) {
            return const Center(
              child: Text(
                'Koi active order running nahi hai.',
                style: TextStyle(color: Colors.white38, fontSize: 15),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: activeOrders.length,
            itemBuilder: (context, index) {
              var doc = activeOrders[index];
              var data = doc.data() as Map<String, dynamic>;
              String status = (data['status'] ?? 'pending').toString().toLowerCase();

              Color statusColor = Colors.redAccent;
              String statusText = 'Ordered';
              if (status == 'preparing') {
                statusColor = Colors.amber;
                statusText = 'Cooking';
              } else if (status == 'ready') {
                statusColor = Colors.blueAccent;
                statusText = 'Ready';
              }

              String customerName = data['customerName'] ?? 'Customer';
              String tableNo = data['tableNo'] ?? '';
              List items = data['items'] ?? [];

              Timestamp? t = data['createdAt'] as Timestamp?;
              DateTime orderDt = t?.toDate() ?? DateTime.now();
              String timeStr = '${orderDt.hour.toString().padLeft(2, '0')}:${orderDt.minute.toString().padLeft(2, '0')}';

              return Card(
                color: const Color(0xFF1E1A17),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: statusColor.withOpacity(0.6), width: 1.2),
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: statusColor.withOpacity(0.5)),
                                ),
                                child: Text(
                                  statusText.toUpperCase(),
                                  style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                tableNo.isNotEmpty ? 'Table: $tableNo' : 'Counter',
                                style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          Text(
                            timeStr,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        customerName,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Divider(color: Color(0xFF2C2520), height: 16),
                      
                      // Items list
                      ...items.map<Widget>((it) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${it['name']} (${it['size'] ?? 'Std'})', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                Text('x${it['qty']}', style: const TextStyle(color: Color(0xFFF7B731), fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )),
                      const SizedBox(height: 14),

                      // Status change buttons for captain
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (status == 'pending')
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              ),
                              onPressed: () => updateOrderStatus(doc.id, 'preparing'),
                              icon: const Icon(Icons.fireplace_rounded, size: 16),
                              label: const Text('Start Cooking', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          if (status == 'preparing')
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              ),
                              onPressed: () => updateOrderStatus(doc.id, 'ready'),
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                              label: const Text('Food Ready', style: TextStyle(fontWeight: FontWeight.bold)),
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