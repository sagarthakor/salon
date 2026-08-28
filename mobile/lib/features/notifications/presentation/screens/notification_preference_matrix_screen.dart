import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../data/models/notification_preference.dart';

/// Shared rendering for both preference scopes — `NotificationPreferencesScreen`
/// (personal, any user) and `TenantNotificationSettingsScreen` (owner-only
/// tenant defaults) differ only in *which* API they read/write, both backed
/// by the same (event_type × channel) matrix shape. Only external channels
/// are shown; in-app is always on in this phase (see
/// NOTIFICATION_ARCHITECTURE.md).
class NotificationPreferenceMatrixScreen extends ConsumerStatefulWidget {
  const NotificationPreferenceMatrixScreen({super.key, required this.title, required this.fetch, required this.update});

  final String title;
  final Future<List<NotificationPreferenceRow>> Function() fetch;
  final Future<List<NotificationPreferenceRow>> Function(List<NotificationPreferenceRow> rows) update;

  @override
  ConsumerState<NotificationPreferenceMatrixScreen> createState() => _NotificationPreferenceMatrixScreenState();
}

class _NotificationPreferenceMatrixScreenState extends ConsumerState<NotificationPreferenceMatrixScreen> {
  List<NotificationPreferenceRow>? _rows;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await widget.fetch();
      if (mounted) setState(() => _rows = rows);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _toggle(NotificationPreferenceRow row, bool value) async {
    final rows = _rows!;
    final updated = row.copyWith(enabled: value);
    setState(() {
      _rows = [for (final r in rows) (r.eventType == row.eventType && r.channel == row.channel) ? updated : r];
      _saving = true;
    });
    try {
      await widget.update([updated]);
    } on ApiException {
      // Revert on failure — the server is the source of truth.
      setState(() => _rows = rows);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: _saving ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator()) : null,
      ),
      body: Builder(
        builder: (context) {
          if (_error != null) return ErrorView(message: _error!, onRetry: _load);
          final rows = _rows;
          if (rows == null) return const LoadingView();
          final byEvent = <String, List<NotificationPreferenceRow>>{};
          for (final row in rows) {
            byEvent.putIfAbsent(row.eventType, () => []).add(row);
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: byEvent.entries
                .map((e) => _EventPreferenceCard(eventType: e.key, rows: e.value, onChanged: _toggle))
                .toList(),
          );
        },
      ),
    );
  }
}

class _EventPreferenceCard extends StatelessWidget {
  const _EventPreferenceCard({required this.eventType, required this.rows, required this.onChanged});

  final String eventType;
  final List<NotificationPreferenceRow> rows;
  final void Function(NotificationPreferenceRow row, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_eventLabel(eventType), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: rows
                  .map(
                    (r) => FilterChip(
                      label: Text(_channelLabel(r.channel)),
                      selected: r.enabled,
                      onSelected: (value) => onChanged(r, value),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _eventLabel(String eventType) =>
      eventType.split('.').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');

  String _channelLabel(String channel) => switch (channel) {
    'push' => 'Push',
    'email' => 'Email',
    'whatsapp' => 'WhatsApp',
    'sms' => 'SMS',
    _ => channel,
  };
}
