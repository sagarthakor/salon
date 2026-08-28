/// A staff member eligible for at least one returned slot, from the
/// additive `staff` field on `GET /branches/{branch}/availability` — the
/// slot-generation algorithm itself only deals in staff IDs, so names are
/// resolved once per response rather than per slot.
class StaffOption {
  const StaffOption({required this.id, required this.name});

  factory StaffOption.fromJson(Map<String, dynamic> json) =>
      StaffOption(id: json['id'] as String, name: json['name'] as String);

  final String id;
  final String name;
}

/// One bookable slot. `staffIds` lists every staff member eligible for this
/// specific slot — when the customer has not pre-selected a specific staff
/// member, any one of these may end up assigned by the backend.
class AvailabilitySlot {
  const AvailabilitySlot({required this.startTime, required this.endTime, required this.staffIds});

  factory AvailabilitySlot.fromJson(Map<String, dynamic> json) => AvailabilitySlot(
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
    staffIds: (json['staff_ids'] as List<dynamic>).map((e) => e.toString()).toList(),
  );

  final String startTime;
  final String endTime;
  final List<String> staffIds;
}

/// Mirrors the full response of `GET /branches/{branch}/availability`.
class AvailabilityResult {
  const AvailabilityResult({
    required this.date,
    required this.durationMinutes,
    required this.bufferMinutes,
    required this.slots,
    required this.staff,
  });

  factory AvailabilityResult.fromJson(Map<String, dynamic> json) => AvailabilityResult(
    date: json['date'] as String,
    durationMinutes: json['duration_minutes'] as int,
    bufferMinutes: json['buffer_minutes'] as int,
    slots: (json['slots'] as List<dynamic>)
        .map((s) => AvailabilitySlot.fromJson(s as Map<String, dynamic>))
        .toList(),
    staff: (json['staff'] as List<dynamic>? ?? [])
        .map((s) => StaffOption.fromJson(s as Map<String, dynamic>))
        .toList(),
  );

  final String date;
  final int durationMinutes;
  final int bufferMinutes;
  final List<AvailabilitySlot> slots;
  final List<StaffOption> staff;

  String? staffNameFor(String id) {
    for (final option in staff) {
      if (option.id == id) return option.name;
    }
    return null;
  }
}
