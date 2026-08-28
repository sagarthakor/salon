<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Queue\SerializesModels;

/**
 * The single Mailable every notification event renders through — Laravel's
 * existing mail architecture (config/mail.php), not a second mail system.
 * Content is plain title/body text on purpose: notification emails carry
 * only the minimum necessary information (see NOTIFICATION_ARCHITECTURE.md,
 * "Privacy"), never internal notes or raw model dumps.
 *
 * Deliberately does NOT implement ShouldQueue: it is only ever sent from
 * inside SendNotificationDeliveryJob, which is already queued — queueing it
 * again would just add a second, redundant hop.
 */
class NotificationMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(public readonly string $notificationTitle, public readonly string $notificationBody) {}

    public function build(): self
    {
        return $this->subject($this->notificationTitle)->view('emails.notification');
    }
}
