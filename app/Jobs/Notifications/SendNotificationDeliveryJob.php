<?php

namespace App\Jobs\Notifications;

use App\Enums\NotificationChannel;
use App\Enums\NotificationDeliveryStatus;
use App\Models\NotificationDelivery;
use App\Services\Notifications\Channels\EmailNotificationChannel;
use App\Services\Notifications\Channels\NotificationChannelInterface;
use App\Services\Notifications\Channels\PushNotificationChannel;
use App\Services\Notifications\Channels\SmsNotificationChannel;
use App\Services\Notifications\Channels\WhatsAppNotificationChannel;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Throwable;

/**
 * Sends one queued external-channel delivery and updates its
 * NotificationDelivery row. Never touches the originating business
 * transaction — by the time this runs, the booking/payment/subscription
 * change has already committed (see NotificationDispatcher, dispatched from
 * an `afterCommit` listener). A failure here is isolated: it marks the
 * delivery FAILED and, if retries remain, Laravel's queue worker retries it
 * per config('notifications.retry') — it never rolls back business data.
 */
class SendNotificationDeliveryJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries;

    public array $backoff;

    public function __construct(public readonly int $deliveryId)
    {
        $this->tries = (int) config('notifications.retry.tries', 5);
        $this->backoff = config('notifications.retry.backoff_seconds', [30, 120, 600, 1800]);
    }

    public function handle(): void
    {
        $delivery = NotificationDelivery::query()->with('notification')->find($this->deliveryId);
        if ($delivery === null || $delivery->notification === null) {
            return;
        }
        // A permanent failure/skip from a previous attempt, or a delivery
        // already sent, must never be re-processed by a stray retry.
        if (in_array($delivery->status, [NotificationDeliveryStatus::SENT, NotificationDeliveryStatus::SKIPPED], true)) {
            return;
        }

        $delivery->update([
            'status' => NotificationDeliveryStatus::PROCESSING,
            'attempt_count' => $delivery->attempt_count + 1,
            'last_attempt_at' => now(),
        ]);

        try {
            $this->channelFor($delivery->channel)->send($delivery, $delivery->notification);
        } catch (Throwable $e) {
            $delivery->markFailed($e->getMessage());
            throw $e;
        }

        if ($delivery->fresh()->status === NotificationDeliveryStatus::FAILED && $this->attempts() < $this->tries) {
            $this->release($this->backoff[min($this->attempts() - 1, count($this->backoff) - 1)]);
        }
    }

    private function channelFor(NotificationChannel $channel): NotificationChannelInterface
    {
        return match ($channel) {
            NotificationChannel::PUSH => app(PushNotificationChannel::class),
            NotificationChannel::EMAIL => app(EmailNotificationChannel::class),
            NotificationChannel::WHATSAPP => app(WhatsAppNotificationChannel::class),
            NotificationChannel::SMS => app(SmsNotificationChannel::class),
            NotificationChannel::IN_APP => throw new \LogicException('In-app notifications are never queued as a delivery.'),
        };
    }

    public function failed(Throwable $exception): void
    {
        $delivery = NotificationDelivery::find($this->deliveryId);
        $delivery?->markFailed($exception->getMessage());
    }
}
