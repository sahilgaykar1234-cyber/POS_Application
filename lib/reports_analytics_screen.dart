// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/data/firestore_paths.dart';

// Conditional import for dart:html to prevent Android compilation errors
import 'reports_stub.dart'
    if (dart.library.html) 'reports_web.dart';

class ReportsAnalyticsScreen extends StatefulWidget {
  const ReportsAnalyticsScreen({super.key});

  @override
  State<ReportsAnalyticsScreen> createState() => _ReportsAnalyticsScreenState();
}

class _ReportsAnalyticsScreenState extends State<ReportsAnalyticsScreen> {
  String selectedPeriod = 'This Month';
  DateTime fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1, 0, 0, 0);
  DateTime toDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59);

  final TextEditingController fromDateController = TextEditingController();
  final TextEditingController toDateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _applyPresetPeriod('This Month');
  }

  void _applyPresetPeriod(String period) {
    DateTime now = DateTime.now();
    setState(() {
      selectedPeriod = period;
      if (period == 'Today') {
        fromDate = DateTime(now.year, now.month, now.day, 0, 0, 0);
        toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (period == 'This Week') {
        DateTime startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        fromDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day, 0, 0, 0);
        toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (period == 'This Month') {
        fromDate = DateTime(now.year, now.month, 1, 0, 0, 0);
        toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      }
      fromDateController.text = _formatDate(fromDate);
      toDateController.text = _formatDate(toDate);
    });
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // =========================================================================
  // MODERN POS COMPACT POPUP DATE PICKER
  // =========================================================================
  Future<void> _openModernRangeDialog(BuildContext context) async {
    DateTime tempStart = fromDate;
    DateTime tempEnd = toDate;
    DateTime activeMonth = DateTime(tempStart.year, tempStart.month, 1);
    String selectingTarget = 'start';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          int daysInMonth = DateUtils.getDaysInMonth(activeMonth.year, activeMonth.month);
          int firstWeekday = DateTime(activeMonth.year, activeMonth.month, 1).weekday % 7;

          const monthNames = [
            'January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December'
          ];

          return Dialog(
            backgroundColor: const Color(0xFF1E1A17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF382F2A), width: 1.2),
            ),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              width: 520,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.date_range_rounded, color: Color(0xFFE65C00), size: 20),
                          SizedBox(width: 8),
                          Text('Select Date Range', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildQuickChip('Today', () {
                          DateTime n = DateTime.now();
                          setDialogState(() {
                            tempStart = DateTime(n.year, n.month, n.day, 0, 0, 0);
                            tempEnd = DateTime(n.year, n.month, n.day, 23, 59, 59);
                            activeMonth = DateTime(n.year, n.month, 1);
                            selectingTarget = 'start';
                          });
                        }),
                        const SizedBox(width: 6),
                        _buildQuickChip('This Week', () {
                          DateTime n = DateTime.now();
                          DateTime s = n.subtract(Duration(days: n.weekday - 1));
                          setDialogState(() {
                            tempStart = DateTime(s.year, s.month, s.day, 0, 0, 0);
                            tempEnd = DateTime(n.year, n.month, n.day, 23, 59, 59);
                            activeMonth = DateTime(n.year, n.month, 1);
                            selectingTarget = 'start';
                          });
                        }),
                        const SizedBox(width: 6),
                        _buildQuickChip('This Month', () {
                          DateTime n = DateTime.now();
                          setDialogState(() {
                            tempStart = DateTime(n.year, n.month, 1, 0, 0, 0);
                            tempEnd = DateTime(n.year, n.month, n.day, 23, 59, 59);
                            activeMonth = DateTime(n.year, n.month, 1);
                            selectingTarget = 'start';
                          });
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => selectingTarget = 'start'),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF26211D),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectingTarget == 'start' ? const Color(0xFFE65C00) : const Color(0xFF382F2A),
                                width: selectingTarget == 'start' ? 1.8 : 1.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('START DATE', style: TextStyle(color: selectingTarget == 'start' ? const Color(0xFFE65C00) : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(_formatDate(tempStart), style: TextStyle(color: selectingTarget == 'start' ? Colors.white : const Color(0xFFF7B731), fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: Icon(Icons.arrow_forward_rounded, color: Colors.white38, size: 16),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => selectingTarget = 'end'),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF26211D),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectingTarget == 'end' ? const Color(0xFFE65C00) : const Color(0xFF382F2A),
                                width: selectingTarget == 'end' ? 1.8 : 1.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('END DATE', style: TextStyle(color: selectingTarget == 'end' ? const Color(0xFFE65C00) : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(_formatDate(tempEnd), style: TextStyle(color: selectingTarget == 'end' ? Colors.white : const Color(0xFFF7B731), fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${monthNames[activeMonth.month - 1]} ${activeMonth.year}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left, color: Colors.white70),
                            onPressed: () => setDialogState(() => activeMonth = DateTime(activeMonth.year, activeMonth.month - 1, 1)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right, color: Colors.white70),
                            onPressed: () => setDialogState(() => activeMonth = DateTime(activeMonth.year, activeMonth.month + 1, 1)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
                        .map((w) => SizedBox(width: 38, child: Text(w, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold))))
                        .toList(),
                  ),
                  const SizedBox(height: 6),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 42,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 1.15,
                    ),
                    itemBuilder: (context, index) {
                      int dayNumber = index - firstWeekday + 1;
                      if (dayNumber < 1 || dayNumber > daysInMonth) return const SizedBox.shrink();

                      DateTime cellDate = DateTime(activeMonth.year, activeMonth.month, dayNumber);
                      bool isStart = cellDate.year == tempStart.year && cellDate.month == tempStart.month && cellDate.day == tempStart.day;
                      bool isEnd = cellDate.year == tempEnd.year && cellDate.month == tempEnd.month && cellDate.day == tempEnd.day;
                      bool isInRange = cellDate.isAfter(DateTime(tempStart.year, tempStart.month, tempStart.day, 23, 59, 59)) &&
                          cellDate.isBefore(DateTime(tempEnd.year, tempEnd.month, tempEnd.day, 0, 0, 0));

                      Color bg = Colors.transparent;
                      Color txtColor = Colors.white;

                      if (isStart || isEnd) {
                        bg = const Color(0xFFE65C00);
                        txtColor = Colors.white;
                      } else if (isInRange) {
                        bg = const Color(0xFFE65C00).withOpacity(0.2);
                        txtColor = const Color(0xFFF7B731);
                      }

                      return InkWell(
                        onTap: () {
                          setDialogState(() {
                            if (selectingTarget == 'start') {
                              tempStart = DateTime(cellDate.year, cellDate.month, cellDate.day, 0, 0, 0);
                              if (tempStart.isAfter(tempEnd)) {
                                tempEnd = DateTime(cellDate.year, cellDate.month, cellDate.day, 23, 59, 59);
                              }
                              selectingTarget = 'end';
                            } else {
                              tempEnd = DateTime(cellDate.year, cellDate.month, cellDate.day, 23, 59, 59);
                              if (tempEnd.isBefore(tempStart)) {
                                tempStart = DateTime(cellDate.year, cellDate.month, cellDate.day, 0, 0, 0);
                              }
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(8),
                            border: isStart || isEnd ? Border.all(color: Colors.white70, width: 1.2) : null,
                          ),
                          child: Text('$dayNumber', style: TextStyle(color: txtColor, fontWeight: (isStart || isEnd || isInRange) ? FontWeight.bold : FontWeight.normal, fontSize: 12.5)),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65C00),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          setState(() {
                            selectedPeriod = 'Custom';
                            fromDate = tempStart;
                            toDate = tempEnd;
                            fromDateController.text = _formatDate(fromDate);
                            toDateController.text = _formatDate(toDate);
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('Apply Range', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: const Color(0xFF26211D), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF382F2A))),
        child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ),
    );
  }

  // --- CROSS-PLATFORM CSV DOWNLOAD TRIGGER ---
  void _downloadCsvFile(String csvContent, String filename) {
    try {
      downloadFileCrossPlatform(csvContent, filename);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$filename download ho gaya!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // --- CSV GENERATION LOGIC ---
  void _generateAndDownloadSalesCsv(List<DocumentSnapshot> docs, DateTime start, DateTime end) {
    var rangeDocs = docs.where((doc) {
      var d = doc.data() as Map<String, dynamic>;
      Timestamp? t = d['createdAt'] as Timestamp?;
      if (t == null) return false;
      DateTime dt = t.toDate();
      return dt.isAfter(start.subtract(const Duration(seconds: 1))) && dt.isBefore(end.add(const Duration(seconds: 1)));
    }).toList();

    StringBuffer csv = StringBuffer();
    csv.writeln("Bill No,Date,Time,Table No,Customer Name,Phone,Item Count,Subtotal,GST,Discount,Grand Total,Payment Status,Order Status");

    for (var doc in rangeDocs) {
      var d = doc.data() as Map<String, dynamic>;
      String billNo = '#${doc.id.substring(0, doc.id.length > 5 ? 5 : doc.id.length).toUpperCase()}';
      DateTime dt = (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      String dateStr = '${dt.day}-${dt.month}-${dt.year}';
      String timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      String table = (d['tableNo'] ?? d['orderType'] ?? 'Dine-In').toString().replaceAll(',', ' ');
      String name = (d['customerName'] ?? 'Guest').toString().replaceAll(',', ' ');
      String phone = (d['customerPhone'] ?? '').toString();
      List items = d['items'] ?? [];
      double subtotal = (d['subtotal'] ?? d['totalPrice'] ?? 0.0).toDouble();
      double total = (d['totalPrice'] ?? 0.0).toDouble();
      double discount = (d['discountGiven'] ?? 0.0).toDouble();
      double gst = (d['hasGst'] == true) ? (total - subtotal) : 0.0;
      String payStatus = (d['paymentStatus'] ?? 'pending').toString().toUpperCase();
      String status = (d['status'] ?? 'completed').toString().toUpperCase();

      csv.writeln('"$billNo","$dateStr","$timeStr","$table","$name","$phone",${items.length},$subtotal,$gst,$discount,$total,"$payStatus","$status"');
    }

    String filename = 'Sales_Report_${_formatDate(start)}_to_${_formatDate(end)}.csv';
    _downloadCsvFile(csv.toString(), filename);
  }

  void _generateAndDownloadCustomerCsv(List<DocumentSnapshot> allDocs, DateTime start, DateTime end) {
    Map<String, Map<String, dynamic>> custMap = {};

    for (var doc in allDocs) {
      var d = doc.data() as Map<String, dynamic>;
      Timestamp? t = d['createdAt'] as Timestamp?;
      if (t == null) continue;
      DateTime dt = t.toDate();
      if (dt.isBefore(start) || dt.isAfter(end)) continue;

      String phone = (d['customerPhone'] ?? '').toString().trim();
      String rawName = (d['customerName'] ?? 'Guest').toString().trim();
      String name = rawName.replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '').trim();
      String key = phone.isNotEmpty ? phone : name.toLowerCase();

      double price = (d['totalPrice'] ?? 0.0).toDouble();

      if (!custMap.containsKey(key)) {
        custMap[key] = {
          'name': name.isEmpty ? 'Guest' : name,
          'phone': phone,
          'totalOrders': 1,
          'totalSpent': price,
          'lastVisit': dt,
        };
      } else {
        custMap[key]!['totalOrders'] = (custMap[key]!['totalOrders'] as int) + 1;
        custMap[key]!['totalSpent'] = (custMap[key]!['totalSpent'] as double) + price;
        DateTime curLast = custMap[key]!['lastVisit'];
        if (dt.isAfter(curLast)) custMap[key]!['lastVisit'] = dt;
      }
    }

    StringBuffer csv = StringBuffer();
    csv.writeln("Customer Name,Mobile Number,Orders Placed,Total Spent (Rs),Average Order Value (Rs),Last Visit Date");

    for (var c in custMap.values) {
      int orders = c['totalOrders'];
      double spent = c['totalSpent'];
      double avg = orders > 0 ? (spent / orders) : 0.0;
      DateTime lv = c['lastVisit'];

      String name = c['name'].toString().replaceAll(',', ' ');
      String phone = c['phone'].toString();

      csv.writeln('"$name","$phone",$orders,$spent,${avg.toStringAsFixed(2)},"${lv.day}-${lv.month}-${lv.year}"');
    }

    String filename = 'Customer_Report_${_formatDate(start)}_to_${_formatDate(end)}.csv';
    _downloadCsvFile(csv.toString(), filename);
  }

  void _generateAndDownloadItemCsv(List<DocumentSnapshot> docs, DateTime start, DateTime end) {
    Map<String, Map<String, dynamic>> itemMap = {};
    double totalRev = 0.0;

    for (var doc in docs) {
      var d = doc.data() as Map<String, dynamic>;
      Timestamp? t = d['createdAt'] as Timestamp?;
      if (t == null) continue;
      DateTime dt = t.toDate();
      if (dt.isBefore(start) || dt.isAfter(end)) continue;

      List items = d['items'] ?? [];
      for (var it in items) {
        String name = (it['name'] ?? 'Item').toString().replaceAll(',', ' ');
        String size = it['size'] ?? 'Regular';
        String key = '$name ($size)';
        int qty = it['qty'] ?? 1;
        double price = (it['price'] ?? 0.0).toDouble();
        double rev = qty * price;
        totalRev += rev;

        if (!itemMap.containsKey(key)) {
          itemMap[key] = {'name': name, 'size': size, 'qty': qty, 'price': price, 'revenue': rev};
        } else {
          itemMap[key]!['qty'] = (itemMap[key]!['qty'] as int) + qty;
          itemMap[key]!['revenue'] = (itemMap[key]!['revenue'] as double) + rev;
        }
      }
    }

    StringBuffer csv = StringBuffer();
    csv.writeln("Item Name,Variant / Size,Quantity Sold,Unit Price (Rs),Total Revenue (Rs),Revenue Contribution (%)");

    for (var it in itemMap.values) {
      String name = it['name'];
      String size = it['size'];
      int qty = it['qty'];
      double price = it['price'];
      double rev = it['revenue'];
      double contrib = totalRev > 0 ? ((rev / totalRev) * 100) : 0.0;

      csv.writeln('"$name","$size",$qty,$price,$rev,${contrib.toStringAsFixed(2)}%');
    }

    String filename = 'Item_Sales_${_formatDate(start)}_to_${_formatDate(end)}.csv';
    _downloadCsvFile(csv.toString(), filename);
  }

  void _openExportReportModal(BuildContext context, List<DocumentSnapshot> allDocs) {
    DateTime exportStart = fromDate;
    DateTime exportEnd = toDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1A17),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF2C2520))),
            title: Row(
              children: const [
                Icon(Icons.file_download_outlined, color: Color(0xFFE65C00), size: 22),
                SizedBox(width: 8),
                Text('Export Report (.CSV)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Date Range for Export:', style: TextStyle(color: Colors.white54, fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _openModernRangeDialog(context);
                    if (context.mounted) _openExportReportModal(context, allDocs);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFF26211D), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE65C00).withOpacity(0.5))),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded, color: Color(0xFFF7B731), size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${_formatDate(exportStart)}  to  ${_formatDate(exportEnd)}', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold))),
                        const Icon(Icons.edit_calendar_rounded, color: Colors.white54, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Choose Report Type:', style: TextStyle(color: Colors.white54, fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _buildExportItem(icon: Icons.receipt_long_rounded, title: 'Sales Report', subtitle: 'Bill-wise grand total, taxes & dates', onTap: () { Navigator.pop(ctx); _generateAndDownloadSalesCsv(allDocs, exportStart, exportEnd); }),
                const SizedBox(height: 8),
                _buildExportItem(icon: Icons.groups_rounded, title: 'Customer Report', subtitle: 'Customer spend history & visits', onTap: () { Navigator.pop(ctx); _generateAndDownloadCustomerCsv(allDocs, exportStart, exportEnd); }),
                const SizedBox(height: 8),
                _buildExportItem(icon: Icons.fastfood_rounded, title: 'Item Sales Report', subtitle: 'Item-wise quantity sold & revenue', onTap: () { Navigator.pop(ctx); _generateAndDownloadItemCsv(allDocs, exportStart, exportEnd); }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildExportItem({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFF26211D), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF382F2A))),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: const Color(0xFFE65C00).withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: const Color(0xFFE65C00), size: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)), const SizedBox(height: 2), Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10.5))])),
            const Icon(Icons.download_rounded, color: Colors.greenAccent, size: 18),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    DateTime now = DateTime.now();
    DateTime startOfToday = DateTime(now.year, now.month, now.day, 0, 0, 0);

    return Scaffold(
      backgroundColor: const Color(0xFF141211),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirestorePaths.orders().snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFE65C00)));

          var allDocs = snapshot.data!.docs;
          var todayDocs = allDocs.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            Timestamp? t = data['createdAt'] as Timestamp?;
            if (t == null) return false;
            return t.toDate().isAfter(startOfToday);
          }).toList();

          double todaySales = 0.0;
          for (var doc in todayDocs) {
            var d = doc.data() as Map<String, dynamic>;
            todaySales += (d['totalPrice'] ?? 0.0).toDouble();
          }
          int todayOrdersCount = todayDocs.length;
          double todayAvgOrderValue = todayOrdersCount > 0 ? (todaySales / todayOrdersCount) : 0.0;

          Set<String> allTimeCustomerKeys = {};
          Map<String, double> customerTotalSpendMap = {};
          Map<String, int> customerOrderCountMap = {};
          Map<String, String> customerNameMap = {};

          for (var doc in allDocs) {
            var d = doc.data() as Map<String, dynamic>;
            String phone = (d['customerPhone'] ?? '').toString().trim();
            String rawName = (d['customerName'] ?? 'Guest').toString().trim();
            String cleanName = rawName.replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '').trim();
            String key = phone.isNotEmpty ? phone : cleanName.toLowerCase();
            double price = (d['totalPrice'] ?? 0.0).toDouble();

            allTimeCustomerKeys.add(key);
            customerNameMap[key] = cleanName.isNotEmpty ? cleanName : 'Guest';
            customerTotalSpendMap[key] = (customerTotalSpendMap[key] ?? 0.0) + price;
            customerOrderCountMap[key] = (customerOrderCountMap[key] ?? 0) + 1;
          }

          var filteredDocs = allDocs.where((doc) {
            var d = doc.data() as Map<String, dynamic>;
            Timestamp? t = d['createdAt'] as Timestamp?;
            if (t == null) return false;
            DateTime dt = t.toDate();
            return dt.isAfter(fromDate.subtract(const Duration(seconds: 1))) && dt.isBefore(toDate.add(const Duration(seconds: 1)));
          }).toList();

          double periodTotalSales = 0.0;
          int periodTotalOrders = filteredDocs.length;
          int dineInCount = 0;
          int takeawayCount = 0;
          int completedCount = 0;
          int cancelledCount = 0;
          double highestBill = 0.0;

          Map<String, int> itemSoldQtyMap = {};
          Map<String, double> itemRevenueMap = {};
          Set<String> periodCustomerKeys = {};

          for (var doc in filteredDocs) {
            var d = doc.data() as Map<String, dynamic>;
            double price = (d['totalPrice'] ?? 0.0).toDouble();
            periodTotalSales += price;
            if (price > highestBill) highestBill = price;

            String orderType = (d['orderType'] ?? 'Dine-In').toString().toLowerCase();
            if (orderType.contains('takeaway')) {
              takeawayCount++;
            } else {
              dineInCount++;
            }

            String status = (d['status'] ?? 'pending').toString().toLowerCase();
            if (status == 'completed') completedCount++;
            if (status == 'cancelled') cancelledCount++;

            String phone = (d['customerPhone'] ?? '').toString().trim();
            String rawName = (d['customerName'] ?? '').toString().trim();
            String cleanName = rawName.replaceAll(RegExp(r'\(Table\s*\d+\)', caseSensitive: false), '').trim();
            String key = phone.isNotEmpty ? phone : cleanName.toLowerCase();
            if (key.isNotEmpty) periodCustomerKeys.add(key);

            List items = d['items'] ?? [];
            for (var it in items) {
              String iName = it['name'] ?? 'Item';
              int qty = it['qty'] ?? 1;
              double iPrice = (it['price'] ?? 0.0).toDouble();
              itemSoldQtyMap[iName] = (itemSoldQtyMap[iName] ?? 0) + qty;
              itemRevenueMap[iName] = (itemRevenueMap[iName] ?? 0.0) + (iPrice * qty);
            }
          }

          double periodAvgBill = periodTotalOrders > 0 ? (periodTotalSales / periodTotalOrders) : 0.0;
          var sortedItemsList = itemSoldQtyMap.keys.toList()..sort((a, b) => (itemSoldQtyMap[b] ?? 0).compareTo(itemSoldQtyMap[a] ?? 0));

          int returningCustomersCount = 0;
          int newCustomersCount = 0;
          for (var key in periodCustomerKeys) {
            int lifetimeOrders = customerOrderCountMap[key] ?? 1;
            if (lifetimeOrders > 1) {
              returningCustomersCount++;
            } else {
              newCustomersCount++;
            }
          }

          String topSpenderName = 'None';
          double topSpenderAmount = 0.0;
          customerTotalSpendMap.forEach((key, spend) {
            if (spend > topSpenderAmount) {
              topSpenderAmount = spend;
              topSpenderName = customerNameMap[key] ?? 'Customer';
            }
          });

          return LayoutBuilder(
            builder: (context, constraints) {
              int columns = constraints.maxWidth > 1100 ? 4 : (constraints.maxWidth > 650 ? 2 : 1);

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionHeader("Today's Summary", Icons.bolt, const Color(0xFFF7B731)),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65C00),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _openExportReportModal(context, allDocs),
                          icon: const Icon(Icons.download_rounded, size: 16),
                          label: const Text('Export Report (.CSV)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildModernGrid(
                      columns: columns,
                      children: [
                        _buildModernStatCard(title: "Today's Sales", value: "₹${todaySales.toInt()}", icon: Icons.trending_up_rounded, accentColor: Colors.greenAccent, subtitle: "Realtime Collections"),
                        _buildModernStatCard(title: "Today's Orders", value: "$todayOrdersCount", icon: Icons.receipt_long_rounded, accentColor: Colors.lightBlueAccent, subtitle: "Total bills placed"),
                        _buildModernStatCard(title: "Total Customers", value: "${allTimeCustomerKeys.length}", icon: Icons.people_alt_rounded, accentColor: const Color(0xFFF7B731), subtitle: "In database records"),
                        _buildModernStatCard(title: "Avg Order Value", value: "₹${todayAvgOrderValue.toInt()}", icon: Icons.auto_graph_rounded, accentColor: Colors.purpleAccent, subtitle: "Ticket size / order"),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionHeader("Sales Report", Icons.analytics_rounded, const Color(0xFFE65C00)),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF7B731),
                            side: const BorderSide(color: Color(0xFFF7B731)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          ),
                          onPressed: () => _openModernRangeDialog(context),
                          icon: const Icon(Icons.date_range_rounded, size: 16),
                          label: const Text('Pick Custom Date Range', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF1B1715), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF2C2520))),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: const Color(0xFF241E1B), borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              children: [
                                Expanded(child: _buildModernTab('Today')),
                                Expanded(child: _buildModernTab('This Week')),
                                Expanded(child: _buildModernTab('This Month')),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => _openModernRangeDialog(context),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(color: const Color(0xFF241E1B), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF382F2A))),
                                    child: Row(children: [const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFFF7B731)), const SizedBox(width: 8), Text('From: ${fromDateController.text}', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold))]),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: () => _openModernRangeDialog(context),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(color: const Color(0xFF241E1B), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF382F2A))),
                                    child: Row(children: [const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFFF7B731)), const SizedBox(width: 8), Text('To: ${toDateController.text}', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold))]),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildModernStatCard(title: 'Period Total Sales', value: '₹${periodTotalSales.toInt()}', icon: Icons.account_balance_wallet_rounded, accentColor: Colors.greenAccent, subtitle: '${filteredDocs.length} orders counted')),
                        const SizedBox(width: 12),
                        Expanded(child: _buildModernStatCard(title: 'Period Orders', value: '$periodTotalOrders', icon: Icons.receipt_rounded, accentColor: Colors.lightBlueAccent, subtitle: '${fromDateController.text} to ${toDateController.text}')),
                      ],
                    ),
                    const SizedBox(height: 28),
                    _buildSectionHeader("Order Analytics", Icons.pie_chart_rounded, const Color(0xFFF7B731)),
                    const SizedBox(height: 12),
                    _buildModernGrid(
                      columns: columns,
                      children: [
                        _buildModernStatCard(title: 'Dine-In', value: '$dineInCount', icon: Icons.restaurant_rounded, accentColor: Colors.blueAccent, subtitle: 'Table orders'),
                        _buildModernStatCard(title: 'Takeaway', value: '$takeawayCount', icon: Icons.shopping_bag_rounded, accentColor: Colors.deepOrangeAccent, subtitle: 'Parcel orders'),
                        _buildModernStatCard(title: 'Completed', value: '$completedCount', icon: Icons.check_circle_rounded, accentColor: Colors.greenAccent, subtitle: 'Settled bills'),
                        _buildModernStatCard(title: 'Cancelled', value: '$cancelledCount', icon: Icons.cancel_rounded, accentColor: Colors.redAccent, subtitle: 'Voided bills'),
                        _buildModernStatCard(title: 'Average Bill', value: '₹${periodAvgBill.toInt()}', icon: Icons.payments_rounded, accentColor: Colors.purpleAccent, subtitle: 'Mean order value'),
                        _buildModernStatCard(title: 'Highest Bill', value: '₹${highestBill.toInt()}', icon: Icons.star_rounded, accentColor: const Color(0xFFF7B731), subtitle: 'Single highest order'),
                      ],
                    ),
                    const SizedBox(height: 28),
                    _buildSectionHeader("Top Selling Items", Icons.local_fire_department_rounded, const Color(0xFFE65C00)),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(color: const Color(0xFF1B1715), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF2C2520))),
                      padding: const EdgeInsets.all(16),
                      child: sortedItemsList.isEmpty
                          ? const Padding(padding: EdgeInsets.all(20.0), child: Center(child: Text('No item sales in this period.', style: TextStyle(color: Colors.white38))))
                          : Column(
                              children: [
                                Row(
                                  children: const [
                                    Expanded(flex: 6, child: Text('ITEM NAME', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold))),
                                    Expanded(flex: 2, child: Text('QTY', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold))),
                                    Expanded(flex: 2, child: Text('REVENUE', textAlign: TextAlign.right, style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold))),
                                  ],
                                ),
                                const Divider(color: Color(0xFF2C2520), height: 20),
                                ...sortedItemsList.take(6).toList().asMap().entries.map((entry) {
                                  int idx = entry.key + 1;
                                  String itmName = entry.value;
                                  int soldQty = itemSoldQtyMap[itmName] ?? 0;
                                  double rev = itemRevenueMap[itmName] ?? 0.0;

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 7.0),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 24, height: 24,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(color: const Color(0xFFE65C00).withOpacity(0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE65C00).withOpacity(0.4))),
                                          child: Text('$idx', style: const TextStyle(color: Color(0xFFE65C00), fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(flex: 6, child: Text(itmName, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600))),
                                        Expanded(flex: 2, child: Text('$soldQty', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFF7B731), fontWeight: FontWeight.bold, fontSize: 13.5))),
                                        Expanded(flex: 2, child: Text('₹${rev.toInt()}', textAlign: TextAlign.right, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13.5))),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                    ),
                    const SizedBox(height: 28),
                    _buildSectionHeader("Customer Analytics", Icons.supervised_user_circle_rounded, const Color(0xFFF7B731)),
                    const SizedBox(height: 12),
                    _buildModernGrid(
                      columns: columns,
                      children: [
                        _buildModernStatCard(title: 'Total Customers', value: '${allTimeCustomerKeys.length}', icon: Icons.groups_rounded, accentColor: Colors.blueAccent, subtitle: 'In CRM database'),
                        _buildModernStatCard(title: 'New Customers', value: '$newCustomersCount', icon: Icons.person_add_rounded, accentColor: Colors.greenAccent, subtitle: 'First time visit'),
                        _buildModernStatCard(title: 'Returning', value: '$returningCustomersCount', icon: Icons.repeat_rounded, accentColor: Colors.deepOrangeAccent, subtitle: 'Repeat visits'),
                        _buildModernStatCard(title: 'Top Spender', value: topSpenderName, icon: Icons.workspace_premium_rounded, accentColor: const Color(0xFFF7B731), subtitle: '₹${topSpenderAmount.toInt()} total spent', isText: true),
                      ],
                    ),
                    const SizedBox(height: 50),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color accentColor) {
    return Row(
      children: [
        Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: accentColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)), child: Icon(icon, color: accentColor, size: 16)),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
      ],
    );
  }

  Widget _buildModernGrid({required int columns, required List<Widget> children}) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: columns,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: columns >= 4 ? 1.85 : (columns == 2 ? 2.1 : 2.7),
      children: children,
    );
  }

  Widget _buildModernTab(String label) {
    bool isSelected = selectedPeriod == label;
    return InkWell(
      onTap: () => _applyPresetPeriod(label),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: isSelected ? const Color(0xFFE65C00) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontSize: 12.5, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildModernStatCard({required String title, required String value, required IconData icon, required Color accentColor, required String subtitle, bool isText = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1B1715), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF2C2520)), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(title.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: accentColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: accentColor, size: 16)),
            ],
          ),
          Text(value, style: TextStyle(color: accentColor, fontSize: isText ? 16 : 22, fontWeight: FontWeight.w900, letterSpacing: 0.3), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(subtitle, style: const TextStyle(color: Colors.white30, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}