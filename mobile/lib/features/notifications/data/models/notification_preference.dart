/// One row of the preference matrix returned by
/// `NotificationPreferenceController::matrix()` — every (event_type, channel)
/// combination the backend knows about, with the currently effective value
/// (`enabled`) and whether that came from an explicit override
/// (`isOverride`) or the system default.
class NotificationPreferenceRow {
  const NotificationPreferenceRow({
    required this.eventType,
    required this.channel,
    required this.enabled,
    required this.isOverride,
  });

  factory NotificationPreferenceRow.fromJson(Map<String, dynamic> json) => NotificationPreferenceRow(
    eventType: json['event_type'] as String,
    channel: json['channel'] as String,
    enabled: json['enabled'] as bool,
    isOverride: json['is_override'] as bool,
  );

  final String eventType;
  final String channel;
  final bool enabled;
  final bool isOverride;

  NotificationPreferenceRow copyWith({bool? enabled}) => NotificationPreferenceRow(
    eventType: eventType,
    channel: channel,
    enabled: enabled ?? this.enabled,
    isOverride: true,
  );
}
