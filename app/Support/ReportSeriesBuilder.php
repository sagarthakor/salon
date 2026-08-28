<?php

namespace App\Support;

use Carbon\CarbonImmutable;

/**
 * Zero-fills a report time series so a chart never silently skips a day/
 * week/month with no bookings — every bucket in the requested range appears,
 * with `0` for any metric that had no matching rows. See "Revenue time
 * series" / "Booking status trend" in REPORTING_ANALYTICS_ARCHITECTURE.md.
 *
 * Bucket boundaries are computed in the report's resolved timezone (the same
 * one `DateRange` was resolved against), never the server's default.
 */
class ReportSeriesBuilder
{
    /**
     * @param  array<string, array<string, int|float>>  $dailyValues  keyed by `Y-m-d`, each value a metric-name => number map.
     * @param  list<string>  $metrics  metric keys to zero-fill when a bucket has no matching rows.
     * @return list<array<string, int|float|string>> one row per bucket, ordered chronologically, each carrying `date` (bucket start, `Y-m-d`) plus every metric.
     */
    public static function build(DateRange $range, string $groupBy, array $dailyValues, array $metrics): array
    {
        $buckets = [];
        foreach ($range->dailyDates() as $date) {
            $bucketKey = self::bucketKey($date, $groupBy, $range->timezone);
            $buckets[$bucketKey] ??= ['date' => $bucketKey, ...array_fill_keys($metrics, 0)];
            if (isset($dailyValues[$date])) {
                foreach ($metrics as $metric) {
                    $buckets[$bucketKey][$metric] += $dailyValues[$date][$metric] ?? 0;
                }
            }
        }

        return array_values($buckets);
    }

    private static function bucketKey(string $date, string $groupBy, string $timezone): string
    {
        $carbon = CarbonImmutable::createFromFormat('Y-m-d', $date, $timezone);

        return match ($groupBy) {
            'week' => $carbon->startOfWeek()->toDateString(),
            'month' => $carbon->startOfMonth()->toDateString(),
            default => $date,
        };
    }
}
