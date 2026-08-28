<?php

namespace App\Support;

use Carbon\CarbonImmutable;
use InvalidArgumentException;

/**
 * Resolves a report's `range`/`from`/`to` request parameters into a concrete
 * start/end instant, anchored to a specific timezone — never the server's
 * default timezone. See "Date range resolution" in
 * REPORTING_ANALYTICS_ARCHITECTURE.md.
 *
 * `$start`/`$end` are inclusive day boundaries (00:00:00 to 23:59:59.999999)
 * in `$timezone`. Callers compare against date-only columns (e.g.
 * `bookings.booking_date`) using `startDate()`/`endDate()`, and against
 * datetime columns using `$start`/`$end` directly.
 */
final class DateRange
{
    public const PRESETS = ['today', 'yesterday', 'this_week', 'last_week', 'this_month', 'last_month', 'this_year', 'custom'];

    private function __construct(
        public readonly CarbonImmutable $start,
        public readonly CarbonImmutable $end,
        public readonly string $timezone,
        public readonly string $preset,
    ) {}

    public static function resolve(string $preset, ?string $from, ?string $to, string $timezone): self
    {
        if (! in_array($preset, self::PRESETS, true)) {
            throw new InvalidArgumentException("Unknown date range preset [{$preset}].");
        }

        $now = CarbonImmutable::now($timezone);

        [$start, $end] = match ($preset) {
            'today' => [$now->startOfDay(), $now->endOfDay()],
            'yesterday' => [$now->subDay()->startOfDay(), $now->subDay()->endOfDay()],
            'this_week' => [$now->startOfWeek(), $now->endOfWeek()],
            'last_week' => [$now->subWeek()->startOfWeek(), $now->subWeek()->endOfWeek()],
            'this_month' => [$now->startOfMonth(), $now->endOfMonth()],
            'last_month' => [$now->subMonthNoOverflow()->startOfMonth(), $now->subMonthNoOverflow()->endOfMonth()],
            'this_year' => [$now->startOfYear(), $now->endOfYear()],
            'custom' => self::customBounds($from, $to, $timezone),
        };

        return new self($start, $end, $timezone, $preset);
    }

    /**
     * @return array{0: CarbonImmutable, 1: CarbonImmutable}
     */
    private static function customBounds(?string $from, ?string $to, string $timezone): array
    {
        if ($from === null || $to === null) {
            throw new InvalidArgumentException('A custom date range requires both `from` and `to`.');
        }
        $start = CarbonImmutable::createFromFormat('Y-m-d', $from, $timezone)->startOfDay();
        $end = CarbonImmutable::createFromFormat('Y-m-d', $to, $timezone)->endOfDay();
        if ($start->greaterThan($end)) {
            throw new InvalidArgumentException('`from` must not be after `to`.');
        }

        return [$start, $end];
    }

    public function startDate(): string
    {
        return $this->start->toDateString();
    }

    public function endDate(): string
    {
        return $this->end->toDateString();
    }

    public function totalDays(): int
    {
        return $this->start->diffInDays($this->end) + 1;
    }

    /**
     * The bucket size a series should use when the caller doesn't request one
     * explicitly — daily for anything up to ~2 months, otherwise weekly up to
     * a year, otherwise monthly. Purely a display heuristic; never changes
     * what data is included.
     */
    public function defaultGroupBy(): string
    {
        return match (true) {
            $this->totalDays() <= 62 => 'day',
            $this->totalDays() <= 366 => 'week',
            default => 'month',
        };
    }

    /**
     * @return list<string> Y-m-d dates, inclusive, one per calendar day in the range.
     */
    public function dailyDates(): array
    {
        $dates = [];
        $cursor = $this->start;
        while ($cursor->lessThanOrEqualTo($this->end)) {
            $dates[] = $cursor->toDateString();
            $cursor = $cursor->addDay();
        }

        return $dates;
    }
}
