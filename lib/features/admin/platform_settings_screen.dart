import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/business_day.dart';
import '../../core/widgets/ui.dart';
import 'admin_data.dart';
import 'admin_service.dart';
import 'admin_widgets.dart';
import '../../core/utils/friendly_error.dart';

/// Platform-wide settings (platform/settings). Cafe-specific settings, such
/// as a cafe's business-day end, stay with each cafe; the value here is only
/// the starting point for NEW cafes.
class PlatformSettingsScreen extends StatefulWidget {
  const PlatformSettingsScreen({super.key, required this.data});
  final ValueListenable<AdminData> data;

  @override
  State<PlatformSettingsScreen> createState() => _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState extends State<PlatformSettingsScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _trial = TextEditingController();
  final _reminder = TextEditingController();
  int _dayEnds = BusinessDay.defaultCutoffMinutes;
  String? _defaultPlan;
  bool _alertNew = true, _alertExpiring = true, _alertPayments = true;
  bool _loaded = false, _saving = false, _dirty = false;

  void _load(PlatformSettings s) {
    _name.text = s.platformName;
    _email.text = s.supportEmail;
    _phone.text = s.supportPhone;
    _trial.text = '${s.trialDays}';
    _reminder.text = '${s.reminderDays}';
    _dayEnds = s.defaultDayEndsAt;
    _defaultPlan = s.defaultPlanId;
    _alertNew = s.alertNewCafes;
    _alertExpiring = s.alertExpiring;
    _alertPayments = s.alertPayments;
    _loaded = true;
  }

  void _touch() => setState(() => _dirty = true);

  Future<void> _save() async {
    final trial = int.tryParse(_trial.text.trim());
    final reminder = int.tryParse(_reminder.text.trim());
    if (trial == null || trial < 0 || trial > 365) return showError(context, 'Trial days must be 0–365.');
    if (reminder == null || reminder < 1 || reminder > 60) return showError(context, 'Reminder days must be 1–60.');
    setState(() => _saving = true);
    try {
      await AdminService.instance.savePlatformSettings({
        'platformName': _name.text.trim().isEmpty ? 'Cafe POS' : _name.text.trim(),
        'supportEmail': _email.text.trim(),
        'supportPhone': _phone.text.trim(),
        'trialDays': trial,
        'reminderDays': reminder,
        'defaultDayEndsAt': BusinessDay.format(_dayEnds),
        'defaultPlanId': _defaultPlan,
        'alertNewCafes': _alertNew,
        'alertExpiring': _alertExpiring,
        'alertPayments': _alertPayments,
      });
      if (mounted) {
        setState(() => _dirty = false);
        showSuccess(context, 'Platform settings saved');
      }
    } catch (e) {
      if (mounted) showError(context, friendlyError(e, 'save the settings'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AdminData>(
      valueListenable: widget.data,
      builder: (context, d, _) {
        if (d.loading && d.platform == null) return const LoadingState();
        if (!_loaded) _load(d.settings);
        final p = context.palette;
        final me = AuthService.instance.currentUser;
        final digits = [FilteringTextInputFormatter.digitsOnly];
        Widget twoCols(List<Widget> a, List<Widget> b) => LayoutBuilder(
          builder: (context, c) => c.maxWidth < 1000
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...a, ...b])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: a),
                    ),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: b),
                    ),
                  ],
                ),
        );
        return PageBody(
          children: [
            PageHeader(
              title: 'Platform settings',
              subtitle: 'Applies to the whole platform. Each cafe keeps its own settings.',
              actions: [
                FilledButton(key: const Key('platform-save'), onPressed: _dirty && !_saving ? _save : null, child: Text(_saving ? 'Saving…' : 'Save changes')),
              ],
            ),
            twoCols(
              [
                SectionCard(
                  title: 'Platform',
                  icon: Icons.apps_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _name,
                        onChanged: (_) => _touch(),
                        decoration: const InputDecoration(labelText: 'Platform name'),
                      ),
                      const SizedBox(height: Space.md),
                      TextField(
                        controller: _email,
                        onChanged: (_) => _touch(),
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Support email (shown to cafes)'),
                      ),
                      const SizedBox(height: Space.md),
                      TextField(
                        controller: _phone,
                        onChanged: (_) => _touch(),
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Support phone'),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'New cafes',
                  subtitle: 'Starting values only; change any cafe from its own page.',
                  icon: Icons.add_business_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _trial,
                        onChanged: (_) => _touch(),
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                        decoration: const InputDecoration(labelText: 'Free trial length (days)'),
                      ),
                      const SizedBox(height: Space.md),
                      DropdownButtonFormField<String?>(
                        initialValue: d.plans.any((x) => x.id == _defaultPlan) ? _defaultPlan : null,
                        decoration: const InputDecoration(labelText: 'Suggested plan after the trial'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('None')),
                          for (final x in d.plans) DropdownMenuItem(value: x.id, child: Text(x.name)),
                        ],
                        onChanged: (v) {
                          _defaultPlan = v;
                          _touch();
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Business day ends at'),
                        subtitle: const Text('Default for new cafes'),
                        trailing: OutlinedButton(
                          onPressed: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(hour: _dayEnds ~/ 60, minute: _dayEnds % 60),
                            );
                            if (t == null) return;
                            final m = t.hour * 60 + t.minute;
                            if (m > BusinessDay.maxCutoffMinutes) {
                              if (context.mounted) showError(context, 'Pick a time between 12:00 AM and 12:00 PM.');
                              return;
                            }
                            setState(() {
                              _dayEnds = m;
                              _dirty = true;
                            });
                          },
                          child: Text(BusinessDay.label(_dayEnds)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              [
                SectionCard(
                  title: 'Alerts',
                  icon: Icons.notifications_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _reminder,
                        onChanged: (_) => _touch(),
                        keyboardType: TextInputType.number,
                        inputFormatters: digits,
                        decoration: const InputDecoration(labelText: 'Warn before expiry (days)'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _alertExpiring,
                        onChanged: (v) => setState(() {
                          _alertExpiring = v;
                          _dirty = true;
                        }),
                        title: const Text('Expiring subscriptions'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _alertPayments,
                        onChanged: (v) => setState(() {
                          _alertPayments = v;
                          _dirty = true;
                        }),
                        title: const Text('Pending payments'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _alertNew,
                        onChanged: (v) => setState(() {
                          _alertNew = v;
                          _dirty = true;
                        }),
                        title: const Text('New cafes (first 7 days)'),
                      ),
                      Text('Expired and suspended subscriptions are always shown.', style: TextStyle(color: p.inkSubtle, fontSize: 12)),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'Your account',
                  icon: Icons.admin_panel_settings_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KvList([('Signed in as', me?.email ?? ''), ('Role', 'Super Admin (verified by the server)')]),
                      const SizedBox(height: Space.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: me == null || me.email.isEmpty
                              ? null
                              : () async {
                                  try {
                                    await AuthService.instance.sendPasswordResetEmail(me.email);
                                    if (context.mounted) showSuccess(context, 'Password reset email sent to ${me.email}');
                                  } catch (e) {
                                    if (context.mounted) showError(context, friendlyError(e, 'send the email'));
                                  }
                                },
                          icon: const Icon(Icons.lock_reset_rounded, size: 18),
                          label: const Text('Change password (email link)'),
                        ),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'Security',
                  icon: Icons.shield_outlined,
                  child: Text(
                    'Roles come from server-side claims: nobody can make themselves Super Admin from the app. '
                    'Firestore rules keep each cafe\'s data separate and allow these pages only for the Super Admin. '
                    'Every change here is written to the activity log without passwords or tokens.',
                    style: TextStyle(color: p.inkMuted, height: 1.45),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
