/// Mirrors `App\Http\Resources\StaffWorkingHourResource`.
class StaffWorkingHourEntry {
  const StaffWorkingHourEntry({
    required this.dayOfWeek,
    required this.isWorking,
    this.startTime,
    this.endTime,
  });

  factory StaffWorkingHourEntry.fromJson(Map<String, dynamic> json) => StaffWorkingHourEntry(
    dayOfWeek: json['day_of_week'] as int,
    isWorking: json['is_working'] as bool,
    startTime: json['start_time'] as String?,
    endTime: json['end_time'] as String?,
  );

  final int dayOfWeek;
  final bool isWorking;
  final String? startTime;
  final String? endTime;

  Map<String, dynamic> toJson() => {
    'day_of_week': dayOfWeek,
    'is_working': isWorking,
    'start_time': startTime,
    'end_time': endTime,
  };

  StaffWorkingHourEntry copyWith({bool? isWorking, String? startTime, String? endTime}) => StaffWorkingHourEntry(
    dayOfWeek: dayOfWeek,
    isWorking: isWorking ?? this.isWorking,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
  );
}

/// Mirrors `App\Http\Resources\StaffBreakResource`.
class StaffBreakEntry {
  const StaffBreakEntry({required this.id, required this.dayOfWeek, required this.startTime, required this.endTime});

  factory StaffBreakEntry.fromJson(Map<String, dynamic> json) => StaffBreakEntry(
    id: json['id'] as int,
    dayOfWeek: json['day_of_week'] as int,
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
  );

  final int id;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
}

/// Mirrors `App\Http\Resources\StaffLeaveResource`.
class StaffLeaveEntry {
  const StaffLeaveEntry({
    required this.id,
    required this.startDate,
    required this.endDate,
    this.reason,
    required this.status,
  });

  factory StaffLeaveEntry.fromJson(Map<String, dynamic> json) => StaffLeaveEntry(
    id: json['id'] as int,
    startDate: json['start_date'] as String,
    endDate: json['end_date'] as String,
    reason: json['reason'] as String?,
    status: json['status'] as String,
  );

  final int id;
  final String startDate;
  final String endDate;
  final String? reason;
  final String status;
}
