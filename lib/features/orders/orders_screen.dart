import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/business_day.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/ui.dart';
import '../pos/pos_screen.dart';
import '../receipt/bill_view.dart';
import '../receipt/receipt_actions.dart';
import '../settings/business_settings.dart';
import 'order_model.dart';
import 'order_service.dart';
import 'orders_filter.dart';

/// All bills of the cafe: search, date / status / payment filters, pages,
/// and View · Print · WhatsApp on every bill (always the saved order, by id).
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.ordersStream, this.settingsStream, this.now});

  /// Tests: fixed data instead of Firestore (date filter applied locally).
  final Stream<List<PosOrder>>? ordersStream;
  final Stream<BusinessSettings>? settingsStream;
  final DateTime? now;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const _pageSize = 20;

  late final _settings = widget.settingsStream ?? BusinessSettingsRepository.instance.watch();
  DatePreset _preset = DatePreset.today;
  DateTimeRange? _custom;
  OrderStatusFilter _status = OrderStatusFilter.all;
  PaymentFilter _payment = PaymentFilter.all;
  String _q = '';
  int _page = 0;
  late Stream<List<PosOrder>> _orders = _open();

  DateTime get _now => widget.now ?? DateTime.now();

  (DateTime, DateTime) get _range {
    final r = _preset.range(_now);
    if (r != null) return r;
    final c = _custom!;
    return BusinessDay.range(c.start, c.end);
  }

  Stream<List<PosOrder>> _open() {
    final (from, to) = _range;
    if (widget.ordersStream != null) {
      return widget.ordersStream!.map((l) => l.where((o) => o.createdAt != null && !o.createdAt!.isBefore(from) && o.createdAt!.isBefore(to)).toList());
    }
    return OrderService.instance.watchRange(from, to);
  }

  void _setPreset(DatePreset p) async {
    if (p == DatePreset.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(_now.year - 3),
        lastDate: BusinessDay.dateOf(_now),
        initialDateRange: _custom ?? DateTimeRange(start: BusinessDay.dateOf(_now).subtract(const Duration(days: 6)), end: BusinessDay.dateOf(_now)),
      );
      if (picked == null) return;
      _custom = picked;
    }
    setState(() {
      _preset = p;
      _page = 0;
      _orders = _open();
    });
  }

  String get _rangeLabel {
    final (from, to) = _range;
    final first = BusinessDay.dateOf(from), last = BusinessDay.dateOf(to.subtract(const Duration(minutes: 1)));
    return first == last ? Fmt.date(first) : '${Fmt.date(first)} – ${Fmt.date(last)}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BusinessSettings>(
      stream: _settings,
      builder: (context, s) {
        final settings = s.data ?? BusinessSettings.empty;
        return StreamBuilder<List<PosOrder>>(
          stream: _orders,
          builder: (context, snap) {
            final loading = !snap.hasData && !snap.hasError;
            final list = filterOrders(snap.data ?? const [], search: _q, status: _status, payment: _payment);
            final pages = (list.length / _pageSize).ceil().clamp(1, 1 << 30);
            final page = _page.clamp(0, pages - 1);
            final rows = pageOf(list, page, _pageSize);
            final total = list.where((o) => !o.isCancelled).fold<double>(0, (t, o) => t + o.totalPrice);
            final paid = list.where((o) => o.isPaid && !o.isCancelled).fold<double>(0, (t, o) => t + o.totalPrice);

            return PageBody(
              children: [
                PageHeader(
                  title: 'Orders',
                  subtitle: '$_rangeLabel · ${list.length} bill${list.length == 1 ? '' : 's'} · ${Fmt.money(total)} billed · ${Fmt.money(paid)} paid',
                ),
                _Filters(
                  preset: _preset,
                  customLabel: _custom == null ? null : _rangeLabel,
                  status: _status,
                  payment: _payment,
                  onPreset: _setPreset,
                  onStatus: (v) => setState(() {
                    _status = v;
                    _page = 0;
                  }),
                  onPayment: (v) => setState(() {
                    _payment = v;
                    _page = 0;
                  }),
                  onSearch: (v) => setState(() {
                    _q = v;
                    _page = 0;
                  }),
                ),
                const SizedBox(height: Space.lg),
                if (snap.hasError)
                  const ErrorState()
                else if (loading)
                  const Padding(padding: EdgeInsets.all(Space.xxl), child: LoadingState(label: 'Loading bills…'))
                else if (list.isEmpty)
                  SurfaceCard(
                    child: EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: _q.isEmpty && _status == OrderStatusFilter.all && _payment == PaymentFilter.all ? 'No bills in this period' : 'No bills match',
                      message: 'Try another date or clear the filters.',
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, c) => c.maxWidth >= 1000
                        ? _Table(orders: rows, settings: settings, actions: _actionsFor)
                        : Column(
                            children: [
                              for (final o in rows)
                                Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: _OrderCard(order: o, actions: _actionsFor(o, settings))),
                            ],
                          ),
                  ),
                if (list.length > _pageSize) ...[
                  const SizedBox(height: Space.md),
                  _Pager(
                    page: page,
                    pages: pages,
                    from: page * _pageSize + 1,
                    to: page * _pageSize + rows.length,
                    total: list.length,
                    onPage: (p) => setState(() => _page = p),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  _RowActions _actionsFor(PosOrder o, BusinessSettings settings) => _RowActions(
        view: () => showBill(context, order: o.data, orderId: o.id, settings: settings.receiptSettings),
        print: () => printSavedBill(context, order: o.data, orderId: o.id, settings: settings.receiptSettings),
        whatsApp: () => shareSavedBillOnWhatsApp(context, order: o.data, orderId: o.id, settings: settings.receiptSettings),
        edit: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PosScreen(editing: o, standalone: true))),
        delete: () async {
          final ok = await showDangerConfirmDialog(
            context,
            title: 'Delete bill ${o.billNo}?',
            message: '${o.displayName} · ${Fmt.money(o.totalPrice)}${o.isPaid ? ' · already paid' : ''}\n'
                'It will be removed from sales and reports. This cannot be undone.',
            confirmLabel: 'Delete',
          );
          if (!ok || !mounted) return;
          try {
            await OrderService.instance.delete(o.id, data: o.data);
            if (mounted) showSuccess(context, 'Bill ${o.billNo} deleted');
          } catch (_) {
            if (mounted) showError(context, 'Could not delete the bill. Please check your connection.');
          }
        },
      );
}

class _RowActions {
  const _RowActions({required this.view, required this.print, required this.whatsApp, required this.edit, required this.delete});
  final VoidCallback view;
  final VoidCallback print;
  final VoidCallback whatsApp;
  final VoidCallback edit;
  final VoidCallback delete;
}

// ------------------------------------------------------------------ filters --

class _Filters extends StatelessWidget {
  const _Filters({
    required this.preset,
    required this.customLabel,
    required this.status,
    required this.payment,
    required this.onPreset,
    required this.onStatus,
    required this.onPayment,
    required this.onSearch,
  });
  final DatePreset preset;
  final String? customLabel;
  final OrderStatusFilter status;
  final PaymentFilter payment;
  final ValueChanged<DatePreset> onPreset;
  final ValueChanged<OrderStatusFilter> onStatus;
  final ValueChanged<PaymentFilter> onPayment;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 700;
      final search = SearchField(width: narrow ? double.infinity : 300, hint: 'Bill no, name, mobile or table', onChanged: onSearch);
      Widget drop<T>(T value, List<T> values, String Function(T) label, ValueChanged<T> on, Key key) => SizedBox(
            width: narrow ? (c.maxWidth - Space.sm) / 2 : 170,
            child: DropdownButtonFormField<T>(
              key: key,
              initialValue: value,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [for (final v in values) DropdownMenuItem(value: v, child: Text(label(v), overflow: TextOverflow.ellipsis))],
              onChanged: (v) => v == null ? null : on(v),
            ),
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterPills<DatePreset>(
            options: [
              for (final p in DatePreset.values) (p, p == DatePreset.custom && customLabel != null && preset == DatePreset.custom ? customLabel! : p.label),
            ],
            selected: preset,
            onSelected: onPreset,
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              search,
              drop(status, OrderStatusFilter.values, (v) => v.label, onStatus, const Key('orders-status')),
              drop(payment, PaymentFilter.values, (v) => v.label, onPayment, const Key('orders-payment')),
            ],
          ),
        ],
      );
    });
  }
}

// -------------------------------------------------------------------- table --

class _Table extends StatelessWidget {
  const _Table({required this.orders, required this.settings, required this.actions});
  final List<PosOrder> orders;
  final BusinessSettings settings;
  final _RowActions Function(PosOrder, BusinessSettings) actions;

  static const _flex = [14, 14, 18, 26, 11, 12, 11];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final head = TextStyle(color: p.inkSubtle, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4);
    Widget cell(int i, Widget child, {bool right = false}) =>
        Expanded(flex: _flex[i], child: Align(alignment: right ? Alignment.centerRight : Alignment.centerLeft, child: child));

    return SurfaceCard(
      child: Column(
        children: [
          Container(
            color: p.surfaceAlt,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
            child: Row(children: [
              cell(0, Text('BILL NO', style: head)),
              cell(1, Text('DATE & TIME', style: head)),
              cell(2, Text('CUSTOMER · TABLE', style: head)),
              cell(3, Text('ITEMS', style: head)),
              cell(4, Text('AMOUNT', style: head), right: true),
              cell(5, Padding(padding: const EdgeInsets.only(left: Space.lg), child: Text('PAYMENT', style: head))),
              cell(6, Text('STATUS', style: head)),
              const SizedBox(width: 176),
            ]),
          ),
          for (var i = 0; i < orders.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            _TableRow(order: orders[i], actions: actions(orders[i], settings), cell: cell),
          ],
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.order, required this.actions, required this.cell});
  final PosOrder order;
  final _RowActions actions;
  final Widget Function(int, Widget, {bool right}) cell;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final o = order;
    final (date, time) = _dateTime(o.createdAt);
    final who = [
      if (o.takeawayName.isNotEmpty && o.takeawayName != 'Walk-in') o.takeawayName,
      if (o.tableNo.isNotEmpty)
        (o.tableNo.toLowerCase().startsWith('table') ? o.tableNo : 'Table ${o.tableNo}')
      else if (o.tokenNo != null)
        'Token #${o.tokenNo}'
      else if (o.isTakeaway)
        'Takeaway',
    ].join(' · ');
    return InkWell(
      key: Key('order-row-${o.id}'),
      onTap: actions.view,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm + 2),
        child: Row(children: [
          cell(0, Text(o.billNo, style: const TextStyle(fontWeight: FontWeight.w700))),
          cell(1, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(date, style: const TextStyle(fontSize: 13.5)),
            Text(time, style: TextStyle(color: p.inkSubtle, fontSize: 12)),
          ])),
          cell(2, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(who.isEmpty ? '—' : who, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
            if (o.customerPhone.isNotEmpty) Text(o.customerPhone, style: TextStyle(color: p.inkSubtle, fontSize: 12)),
          ])),
          cell(3, Padding(
            padding: const EdgeInsets.only(right: Space.md),
            child: Text(itemsSummary(o.items), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.inkMuted, fontSize: 13)),
          )),
          cell(4, MoneyText(o.totalPrice, style: const TextStyle(fontWeight: FontWeight.w700)), right: true),
          cell(5, Padding(padding: const EdgeInsets.only(left: Space.lg), child: _PaymentChip(order: o))),
          cell(6, StatusChip(o.statusLabel)),
          SizedBox(width: 176, child: _ActionButtons(actions: actions, id: o.id)),
        ]),
      ),
    );
  }
}

// --------------------------------------------------------------------- card --

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.actions});
  final PosOrder order;
  final _RowActions actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final o = order;
    final (date, time) = _dateTime(o.createdAt);
    return SurfaceCard(
      child: InkWell(
        key: Key('order-card-${o.id}'),
        onTap: actions.view,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.xs, Space.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text('${o.billNo} · $date, $time', style: TextStyle(color: p.inkSubtle, fontSize: 12)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: Space.sm),
                  child: MoneyText(o.totalPrice, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ]),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: Text(itemsSummary(o.items), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.inkMuted, fontSize: 13)),
              ),
              const SizedBox(height: 6),
              Row(children: [
                _PaymentChip(order: o),
                const SizedBox(width: 6),
                StatusChip(o.statusLabel),
                const Spacer(),
                _ActionButtons(actions: actions, id: o.id),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  const _PaymentChip({required this.order});
  final PosOrder order;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return StatusChip(
      order.isPaid ? order.paymentLabel : 'Unpaid',
      color: order.isPaid ? p.success : p.warning,
      tint: order.isPaid ? p.successTint : p.warningTint,
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.actions, required this.id});
  final _RowActions actions;
  final String id;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(key: Key('order-view-$id'), tooltip: 'View bill', visualDensity: VisualDensity.compact, onPressed: actions.view, icon: Icon(Icons.visibility_outlined, size: 20, color: p.inkMuted)),
        IconButton(key: Key('order-print-$id'), tooltip: 'Print receipt', visualDensity: VisualDensity.compact, onPressed: actions.print, icon: Icon(Icons.print_outlined, size: 20, color: p.inkMuted)),
        IconButton(
          key: Key('order-whatsapp-$id'),
          tooltip: 'Share on WhatsApp',
          visualDensity: VisualDensity.compact,
          onPressed: actions.whatsApp,
          icon: const Icon(Icons.chat_outlined, size: 20, color: Color(0xFF128C4A)),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: Icon(Icons.more_vert_rounded, size: 20, color: p.inkMuted),
          onSelected: (v) => v == 'edit' ? actions.edit() : actions.delete(),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit bill'))),
            PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: p.danger), title: Text('Delete bill', style: TextStyle(color: p.danger)))),
          ],
        ),
      ],
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.pages, required this.from, required this.to, required this.total, required this.onPage});
  final int page, pages, from, to, total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text('Showing $from–$to of $total', style: TextStyle(color: context.palette.inkSubtle))),
        IconButton.outlined(tooltip: 'Previous page', onPressed: page > 0 ? () => onPage(page - 1) : null, icon: const Icon(Icons.chevron_left_rounded)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: Space.sm), child: Text('${page + 1} / $pages')),
        IconButton.outlined(tooltip: 'Next page', onPressed: page < pages - 1 ? () => onPage(page + 1) : null, icon: const Icon(Icons.chevron_right_rounded)),
      ]);
}

(String, String) _dateTime(DateTime? d) {
  if (d == null) return ('—', '');
  final parts = Fmt.dateTime(d).split(', ');
  return (parts.first, parts.length > 1 ? parts.last : '');
}
