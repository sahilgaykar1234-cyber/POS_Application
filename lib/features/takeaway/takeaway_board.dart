import '../orders/order_model.dart';

/// Pure grouping/timing logic for the Takeaway screen (unit-tested).
class TakeawayBoard {
  TakeawayBoard._(this.incoming, this.preparing, this.ready, this.pickedUp);

  final List<PosOrder> incoming; // status pending
  final List<PosOrder> preparing;
  final List<PosOrder> ready; // waiting for the customer
  final List<PosOrder> pickedUp; // completed today, newest first

  int get active => incoming.length + preparing.length + ready.length;

  static TakeawayBoard from(Iterable<PosOrder> todays) {
    final take = todays.where((o) => o.isTakeaway && o.tableNo.trim().isEmpty).toList();
    int byToken(PosOrder a, PosOrder b) {
      final ta = a.tokenNo, tb = b.tokenNo;
      if (ta != null && tb != null) return ta.compareTo(tb);
      return (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0));
    }

    List<PosOrder> st(String s) => take.where((o) => o.status == s).toList()..sort(byToken);
    final picked = take.where((o) => o.isCompleted).toList()
      ..sort((a, b) => (b.completedAt ?? b.createdAt ?? DateTime(0)).compareTo(a.completedAt ?? a.createdAt ?? DateTime(0)));
    return TakeawayBoard._(st('pending'), st('preparing'), st('ready'), picked);
  }
}

enum PickupState { asap, onTime, dueSoon, late }

/// Promised-pickup status: "in 12 min", "due in 3 min", "late by 4 min".
({PickupState state, String label}) pickupStatus(PosOrder o, DateTime now) {
  final at = o.pickupAt;
  if (at == null) return (state: PickupState.asap, label: 'ASAP');
  final diff = at.difference(now);
  final mins = diff.inSeconds.abs() ~/ 60 + (diff.inSeconds.abs() % 60 > 0 ? 1 : 0);
  if (diff.isNegative && o.status != 'ready') return (state: PickupState.late, label: 'Late by $mins min');
  if (diff.isNegative) return (state: PickupState.onTime, label: 'Waiting since ${-diff.inMinutes} min');
  if (mins <= 5) return (state: PickupState.dueSoon, label: 'Due in $mins min');
  return (state: PickupState.onTime, label: 'In $mins min');
}

/// Total waiting customers' tokens, e.g. for "Now serving".
List<int> readyTokens(TakeawayBoard b) => [for (final o in b.ready) ?o.tokenNo];
