<?php

namespace App\Console\Commands;

use App\Services\Notifications\BookingReminderService;
use Illuminate\Console\Command;

/**
 * `php artisan notifications:process-reminders` — scheduled every
 * config('notifications.reminders.run_frequency_minutes') minutes (see
 * routes/console.php). Idempotent: see BookingReminderService and
 * NOTIFICATION_ARCHITECTURE.md, "Reminder idempotency".
 */
class ProcessBookingReminders extends Command
{
    protected $signature = 'notifications:process-reminders';

    protected $description = 'Sends due booking reminders (24h/2h before appointment) exactly once per booking.';

    public function handle(BookingReminderService $reminders): int
    {
        $summary = $reminders->processDueReminders();

        foreach ($summary as $kind => $count) {
            $this->info(sprintf('%s: %d', $kind, $count));
        }

        return self::SUCCESS;
    }
}
