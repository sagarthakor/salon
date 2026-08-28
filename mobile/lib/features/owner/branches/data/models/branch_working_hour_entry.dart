/// Mirrors `App\Http\Resources\BranchWorkingHourResource`.
class BranchWorkingHourEntry {
  const BranchWorkingHourEntry({required this.dayOfWeek, required this.isOpen, this.openingTime, this.closingTime});

  factory BranchWorkingHourEntry.fromJson(Map<String, dynamic> json) => BranchWorkingHourEntry(
    dayOfWeek: json['day_of_week'] as int,
    isOpen: json['is_open'] as bool,
    openingTime: json['opening_time'] as String?,
    closingTime: json['closing_time'] as String?,
  );

  final int dayOfWeek;
  final bool isOpen;
  final String? openingTime;
  final String? closingTime;

  Map<String, dynamic> toJson() => {
    'day_of_week': dayOfWeek,
    'is_open': isOpen,
    'opening_time': openingTime,
    'closing_time': closingTime,
  };

  BranchWorkingHourEntry copyWith({bool? isOpen, String? openingTime, String? closingTime}) => BranchWorkingHourEntry(
    dayOfWeek: dayOfWeek,
    isOpen: isOpen ?? this.isOpen,
    openingTime: openingTime ?? this.openingTime,
    closingTime: closingTime ?? this.closingTime,
  );
}

/// Mirrors `App\Http\Resources\BranchHolidayResource`.
class BranchHolidayEntry {
  const BranchHolidayEntry({required this.id, required this.holidayDate, required this.name, required this.isClosed});

  factory BranchHolidayEntry.fromJson(Map<String, dynamic> json) => BranchHolidayEntry(
    id: json['id'] as String,
    holidayDate: json['holiday_date'] as String,
    name: json['name'] as String,
    isClosed: json['is_closed'] as bool,
  );

  final String id;
  final String holidayDate;
  final String name;
  final bool isClosed;
}
