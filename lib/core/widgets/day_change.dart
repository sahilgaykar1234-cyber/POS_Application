import 'dart:async';

import 'package:flutter/widgets.dart';

import '../utils/business_day.dart';

/// Rebuilds [builder] when the business day changes (e.g. at 5:00 AM), so
/// "today" lists empty themselves even if no new order arrives.
class DayChangeRebuilder extends StatefulWidget {
  const DayChangeRebuilder({super.key, required this.builder});
  final WidgetBuilder builder;

  @override
  State<DayChangeRebuilder> createState() => _DayChangeRebuilderState();
}

class _DayChangeRebuilderState extends State<DayChangeRebuilder> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final wait = BusinessDay.nextChange().difference(DateTime.now()) + const Duration(seconds: 1);
    // Re-check at least hourly (the end time can be changed in Settings).
    _timer = Timer(wait > const Duration(hours: 1) ? const Duration(hours: 1) : wait, () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// Same as [DayChangeRebuilder] for a [State]: calls setState when the
/// business day changes.
mixin DayChangeRefresh<T extends StatefulWidget> on State<T> {
  Timer? _dayTimer;

  @override
  void initState() {
    super.initState();
    _scheduleDayChange();
  }

  void _scheduleDayChange() {
    _dayTimer?.cancel();
    final wait = BusinessDay.nextChange().difference(DateTime.now()) + const Duration(seconds: 1);
    _dayTimer = Timer(wait > const Duration(hours: 1) ? const Duration(hours: 1) : wait, () {
      if (!mounted) return;
      setState(() {});
      _scheduleDayChange();
    });
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    super.dispose();
  }
}
