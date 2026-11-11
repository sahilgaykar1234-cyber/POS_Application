import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_service.dart';
import '../../core/data/firestore_paths.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/ui.dart';

const expenseCategories = ['Ingredients', 'Rent', 'Salary', 'Utilities', 'Maintenance', 'Packaging', 'Marketing', 'Other'];
const expensePaidVia = ['Cash', 'UPI', 'Bank', 'Card'];

class Expense {
  Expense(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;

  String get title => (data['title'] ?? '').toString();
  String get category => (data['category'] ?? 'Other').toString();
  double get amount => ((data['amount'] ?? 0) as num).toDouble();
  String get paidVia => (data['paidVia'] ?? 'Cash').toString();
  String get note => (data['note'] ?? '').toString();
  DateTime get date => (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
}

class ExpenseService {
  ExpenseService._();
  static final instance = ExpenseService._();

  Stream<List<Expense>> watch() => FirestorePaths.expenses().snapshots().map((s) {
        final list = s.docs.map((d) => Expense(d.id, d.data())).toList();
        list.sort((a, b) => b.date.compareTo(a.date));
        return list;
      });

  Future<void> save({String? id, required Map<String, dynamic> fields}) async {
    final data = {...fields, 'updatedAt': FieldValue.serverTimestamp()};
    if (id == null) {
      await FirestorePaths.expenses().add({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': AuthService.instance.currentUser?.uid,
      });
    } else {
      await FirestorePaths.expenses().doc(id).set(data, SetOptions(merge: true));
    }
  }

  Future<void> delete(String id) => FirestorePaths.expenses().doc(id).delete();
}

/// Sum of expenses whose date falls in [from, to).
double expensesBetween(Iterable<Expense> list, DateTime from, DateTime to) =>
    list.where((e) => !e.date.isBefore(from) && e.date.isBefore(to)).fold(0.0, (s, e) => s + e.amount);

enum _Range { today, month, last30, all }

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, this.expensesStream});
  final Stream<List<Expense>>? expensesStream;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late final _stream = widget.expensesStream ?? ExpenseService.instance.watch();
  _Range _range = _Range.month;
  String? _category;

  (DateTime, DateTime) get _bounds {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return switch (_range) {
      _Range.today => (today, today.add(const Duration(days: 1))),
      _Range.month => (DateTime(n.year, n.month), DateTime(n.year, n.month + 1)),
      _Range.last30 => (today.subtract(const Duration(days: 29)), today.add(const Duration(days: 1))),
      _Range.all => (DateTime(2000), DateTime(2100)),
    };
  }

  Future<void> _edit([Expense? e]) async {
    await showDialog<void>(context: context, builder: (_) => _ExpenseDialog(expense: e));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: context.isMobile
          ? FloatingActionButton(onPressed: () => _edit(), tooltip: 'Add expense', child: const Icon(Icons.add))
          : null,
      body: StreamBuilder<List<Expense>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return const ErrorState();
          if (!snap.hasData) return const LoadingState();
          final (from, to) = _bounds;
          final inRange = snap.data!.where((e) => !e.date.isBefore(from) && e.date.isBefore(to)).toList();
          final shown = _category == null ? inRange : inRange.where((e) => e.category == _category).toList();
          final total = shown.fold<double>(0, (s, e) => s + e.amount);
          final byCat = <String, double>{};
          for (final e in inRange) {
            byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
          }
          final topCats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

          return PageBody(
            children: [
              PageHeader(
                title: 'Expenses',
                subtitle: 'Track what the cafe spends — used for profit on the dashboard.',
                actions: [
                  if (!context.isMobile) FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add, size: 18), label: const Text('Add expense')),
                ],
              ),
              FilterPills<_Range>(
                options: const [(_Range.today, 'Today'), (_Range.month, 'This month'), (_Range.last30, 'Last 30 days'), (_Range.all, 'All time')],
                selected: _range,
                onSelected: (r) => setState(() => _range = r),
              ),
              const SizedBox(height: Space.lg),
              ResponsiveGrid(minTileWidth: 220, children: [
                StatCard(label: _category == null ? 'Total spent' : 'Spent on $_category', value: Fmt.money(total), icon: Icons.account_balance_wallet_outlined, highlight: true),
                StatCard(label: 'Entries', value: '${shown.length}', icon: Icons.receipt_outlined),
                if (topCats.isNotEmpty)
                  StatCard(label: 'Biggest category', value: topCats.first.key, icon: Icons.pie_chart_outline, caption: Fmt.money(topCats.first.value)),
              ]),
              const SizedBox(height: Space.lg),
              if (byCat.isNotEmpty) ...[
                FilterPills<String?>(
                  options: [(null, 'All categories'), for (final c in topCats) (c.key, c.key)],
                  selected: _category,
                  onSelected: (c) => setState(() => _category = c),
                ),
                const SizedBox(height: Space.md),
              ],
              if (shown.isEmpty)
                EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'No expenses in this period',
                  message: 'Add rent, ingredients, salaries and other costs to see real profit.',
                  action: FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add expense')),
                )
              else
                SurfaceCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < shown.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: p.border),
                        ListTile(
                          minTileHeight: 64,
                          leading: CircleAvatar(
                            backgroundColor: p.surfaceAlt,
                            child: Icon(_iconFor(shown[i].category), size: 20, color: p.inkSubtle),
                          ),
                          title: Text(shown[i].title.isEmpty ? shown[i].category : shown[i].title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text([shown[i].category, Fmt.date(shown[i].date), shown[i].paidVia, if (shown[i].note.isNotEmpty) shown[i].note].join(' · ')),
                          trailing: MoneyText(shown[i].amount, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          onTap: () => _edit(shown[i]),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static IconData _iconFor(String c) => switch (c) {
        'Ingredients' => Icons.shopping_basket_outlined,
        'Rent' => Icons.home_work_outlined,
        'Salary' => Icons.badge_outlined,
        'Utilities' => Icons.bolt_outlined,
        'Maintenance' => Icons.build_outlined,
        'Packaging' => Icons.inventory_2_outlined,
        'Marketing' => Icons.campaign_outlined,
        _ => Icons.receipt_outlined,
      };
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({this.expense});
  final Expense? expense;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.expense?.title ?? '');
  late final _amount = TextEditingController(text: widget.expense == null ? '' : widget.expense!.amount.toStringAsFixed(widget.expense!.amount % 1 == 0 ? 0 : 2));
  late final _note = TextEditingController(text: widget.expense?.note ?? '');
  late String _category = widget.expense?.category ?? 'Ingredients';
  late String _paidVia = widget.expense?.paidVia ?? 'Cash';
  late DateTime _date = widget.expense?.date ?? DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ExpenseService.instance.save(id: widget.expense?.id, fields: {
        'title': _title.text.trim(),
        'category': _category,
        'amount': double.parse(_amount.text.trim()),
        'paidVia': _paidVia,
        'note': _note.text.trim(),
        'date': Timestamp.fromDate(DateTime(_date.year, _date.month, _date.day, 12)),
      });
      if (mounted) {
        Navigator.pop(context);
        showSuccess(context, widget.expense == null ? 'Expense added' : 'Expense updated');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, 'Could not save. Please check your connection.');
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDangerConfirmDialog(context, title: 'Delete this expense?', message: 'This cannot be undone.', confirmLabel: 'Delete');
    if (!ok || !mounted) return;
    try {
      await ExpenseService.instance.delete(widget.expense!.id);
      if (mounted) {
        Navigator.pop(context);
        showSuccess(context, 'Expense deleted');
      }
    } catch (_) {
      if (mounted) showError(context, 'Could not delete.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.expense == null ? 'Add expense' : 'Edit expense'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _amount,
                  autofocus: widget.expense == null,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: const InputDecoration(labelText: 'Amount *', prefixText: '₹ '),
                  validator: (v) => (double.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Enter the amount' : null,
                ),
                const SizedBox(height: Space.md),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [for (final c in expenseCategories) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
                const SizedBox(height: Space.md),
                TextFormField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Description', hintText: 'e.g. Cheese 10 kg, electricity bill'),
                  validator: (v) => (v ?? '').length > 100 ? 'Too long' : null,
                ),
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _paidVia,
                        decoration: const InputDecoration(labelText: 'Paid via'),
                        items: [for (final c in expensePaidVia) DropdownMenuItem(value: c, child: Text(c))],
                        onChanged: (v) => setState(() => _paidVia = v ?? _paidVia),
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: InkWell(
                        borderRadius: Radii.controlR,
                        onTap: () async {
                          final d = await pickDate(context, initial: _date, last: DateTime.now());
                          if (d != null) setState(() => _date = d);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
                          child: Text(Fmt.date(_date)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.md),
                TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.expense != null)
          TextButton(onPressed: _saving ? null : _delete, style: TextButton.styleFrom(foregroundColor: context.palette.danger), child: const Text('Delete')),
        OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}
