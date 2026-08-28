<?php

namespace App\Services\Notifications;

use App\Enums\NotificationChannel;
use App\Enums\NotificationDeliveryStatus;
use App\Enums\NotificationEventType;
use App\Jobs\Notifications\SendNotificationDeliveryJob;
use App\Models\Notification;
use App\Models\NotificationDelivery;
use App\Models\Tenant;
use App\Models\User;
use App\Models\UserDeviceToken;
use App\Services\Notifications\Channels\InAppNotificationChannel;
use App\Services\Notifications\Providers\SmsProviderInterface;
use App\Services\Notifications\Providers\WhatsAppProviderInterface;
use Illuminate\Database\Eloquent\Model;

/**
 * The single entry point business-event listeners call — never a channel or
 * provider directly (see NOTIFICATION_ARCHITECTURE.md's
 * "Business Event → Notification Dispatcher → Notification → Channel"
 * diagram). Always: write the in-app record synchronously, then queue one
 * job per *available and wanted* external channel. A notification failure
 * on any channel never bubbles back up to the caller — this method never
 * throws for a delivery-side problem, only for a genuinely invalid call
 * (e.g. a malformed context).
 */
class NotificationDispatcher
{
    public function __construct(
        private readonly NotificationMessageBuilder $messageBuilder,
        private readonly NotificationPreferenceResolver $preferences,
        private readonly InAppNotificationChannel $inApp,
        private readonly WhatsAppProviderInterface $whatsApp,
        private readonly SmsProviderInterface $sms,
    ) {}

    /**
     * @param  'customer'|'staff'|'owner'  $audience
     * @param  array<string, mixed>  $context
     */
    public function dispatch(
        ?Tenant $tenant,
        User $recipient,
        NotificationEventType $event,
        string $audience,
        array $context,
        ?Model $notifiable = null,
        ?string $recipientPhone = null,
    ): Notification {
        $message = $this->messageBuilder->build($event, $audience, $context);

        $notification = $this->inApp->store($tenant, $recipient, $event, $message['title'], $message['body'], $message['data'], $notifiable);

        $hasActiveDeviceToken = UserDeviceToken::query()->where('user_id', $recipient->id)->where('is_active', true)->exists();

        $this->maybeQueue($tenant, $notification, $event, NotificationChannel::PUSH, $recipient->id, $hasActiveDeviceToken && $this->preferences->wants($tenant, $recipient, $event, NotificationChannel::PUSH));

        $this->maybeQueue($tenant, $notification, $event, NotificationChannel::EMAIL, $recipient->email, filled($recipient->email) && $this->preferences->wants($tenant, $recipient, $event, NotificationChannel::EMAIL));

        $whatsAppAvailable = $this->whatsApp->isConfigured() && filled($recipientPhone);
        $this->maybeQueue($tenant, $notification, $event, NotificationChannel::WHATSAPP, $recipientPhone, $whatsAppAvailable && $this->preferences->wants($tenant, $recipient, $event, NotificationChannel::WHATSAPP));

        $smsAvailable = $this->sms->isConfigured() && filled($recipientPhone);
        $this->maybeQueue($tenant, $notification, $event, NotificationChannel::SMS, $recipientPhone, $smsAvailable && $this->preferences->wants($tenant, $recipient, $event, NotificationChannel::SMS));

        return $notification;
    }

    private function maybeQueue(?Tenant $tenant, Notification $notification, NotificationEventType $event, NotificationChannel $channel, ?string $recipient, bool $shouldSend): void
    {
        if (! $shouldSend || blank($recipient)) {
            return;
        }

        $delivery = NotificationDelivery::query()->create([
            'tenant_id' => $tenant?->id,
            'notification_id' => $notification->id,
            'event_type' => $event,
            'channel' => $channel,
            'recipient' => $recipient,
            'status' => NotificationDeliveryStatus::PENDING,
        ]);

        SendNotificationDeliveryJob::dispatch($delivery->id);
    }
}
