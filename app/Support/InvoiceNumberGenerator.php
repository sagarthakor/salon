<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;

/**
 * Atomically reserves the next sequential invoice number from a single
 * locked counter row (`invoice_number_counters`) — never a random string,
 * never derived from the invoice's own ulid. Must be called inside the same
 * DB transaction that inserts the invoice, so the reserved number and the
 * row it belongs to commit (or roll back) together.
 */
class InvoiceNumberGenerator
{
    public function next(): string
    {
        $counter = DB::table('invoice_number_counters')->lockForUpdate()->first();
        $number = $counter->next_number;
        DB::table('invoice_number_counters')->where('id', $counter->id)->update(['next_number' => $number + 1]);

        $prefix = config('billing.invoice_number_prefix');
        $year = now()->format('Y');

        return sprintf('%s-%s-%06d', $prefix, $year, $number);
    }
}
