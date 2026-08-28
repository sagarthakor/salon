/// One bucket of a report time series — the backend has already zero-filled
/// and grouped by day/week/month (see `ReportSeriesBuilder`); Flutter never
/// recomputes or re-buckets this data, only renders it.
class ReportSeriesPoint {
  const ReportSeriesPoint({required this.date, required this.values});

  factory ReportSeriesPoint.fromJson(Map<String, dynamic> json) {
    final values = <String, num>{};
    for (final entry in json.entries) {
      if (entry.key == 'date') continue;
      final value = entry.value;
      if (value is num) {
        values[entry.key] = value;
      } else if (value is String) {
        values[entry.key] = num.tryParse(value) ?? 0;
      }
    }
    return ReportSeriesPoint(date: json['date'] as String, values: values);
  }

  final String date;
  final Map<String, num> values;

  num valueFor(String key) => values[key] ?? 0;
}
