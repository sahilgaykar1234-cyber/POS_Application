import 'package:flutter/material.dart';

import '../../core/data/firestore_paths.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import 'print_station.dart';
import 'package:pos_app/core/i18n/tr.dart';

/// Settings card body: make this device the Print Station, and see whether
/// the cafe's Print Station is online.
class PrintStationSettings extends StatelessWidget {
  const PrintStationSettings({super.key});

  static Stream<StationInfo?> _station(PrintStationService svc) {
    try {
      return svc.watchStation();
    } catch (_) {
      return Stream.value(null); // previews / tests without a cafe
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = PrintStationService.instance;
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: svc.enabled,
          builder: (context, on, _) => SwitchListTile(
            key: const Key('print-station-switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('This device is the Print Station')),
            subtitle: Text(tr('Turn on only on the phone or computer that has the printer connected. Keep it on charge with the app open.')),
            value: on,
            onChanged: (v) => svc.setEnabled(FirestorePaths.activeCafeId, v),
          ),
        ),
        StreamBuilder<StationInfo?>(
          stream: _station(svc),
          builder: (context, snap) {
            final s = snap.data;
            final online = s != null && s.isOnline(DateTime.now());
            return Text(
              s == null
                  ? tr('No Print Station set up yet.')
                  : online
                      ? tr('Print Station is online.')
                      : tr('Print Station is offline (last seen {0}).', [Fmt.dateTime(s.lastSeen)]),
              style: TextStyle(color: online ? p.success : p.inkSubtle, fontSize: 13, fontWeight: FontWeight.w600),
            );
          },
        ),
      ],
    );
  }
}
