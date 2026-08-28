<?php

namespace App\Services\Notifications\Providers;

use Illuminate\Support\Facades\Log;

/**
 * Placeholder SMS provider — no production vendor has been selected (see
 * Phase 11 report). Writes to the log channel instead of sending a real
 * message, and reports itself as unconfigured so SmsNotificationChannel
 * always marks these deliveries SKIPPED rather than SENT (never claim a
 * delivery that did not really happen). Replace with a real
 * SmsProviderInterface implementation and rebind it in AppServiceProvider
 * once a vendor is chosen.
 */
class LogSmsProvider implements SmsProviderInterface
{
    public function name(): string
    {
        return 'log';
    }

    public function isConfigured(): bool
    {
        return false;
    }

    public function send(string $to, string $message): ProviderSendResult
    {
        // Never log the destination number or message body in full — this
        // is a real customer phone number and real notification content
        // (which can include booking details), and this placeholder path
        // fires on every SMS-eligible event until a real provider is wired
        // up, so it would otherwise accumulate indefinitely in the log. A
        // truncated, redacted line is enough to confirm the no-op fired.
        Log::info('SMS (no provider configured — not actually sent)', [
            'to' => substr($to, 0, 4).str_repeat('*', max(strlen($to) - 4, 0)),
            'message_length' => strlen($message),
        ]);

        return ProviderSendResult::permanentFailure('No SMS provider is configured.');
    }
}
