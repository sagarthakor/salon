<?php

namespace App\Services\Notifications;

use App\Enums\NotificationEventType;

/**
 * Renders the title/body/deep-link data for one (event, audience) pair from
 * backend-resolved context only — never from anything the client sent (see
 * NOTIFICATION_ARCHITECTURE.md, "Booking confirmed": "Do not reconstruct
 * important booking information from Flutter"). `data` is a small, typed
 * payload the Flutter app uses for deep-linking (see NotificationDeepLink) —
 * never an arbitrary route string.
 *
 * @phpstan-type BuiltMessage array{title: string, body: string, data: array<string, mixed>}
 */
class NotificationMessageBuilder
{
    /**
     * @param  'customer'|'staff'|'owner'  $audience
     * @param  array<string, mixed>  $context
     * @return array{title: string, body: string, data: array<string, mixed>}
     */
    public function build(NotificationEventType $event, string $audience, array $context): array
    {
        return match ($event) {
            NotificationEventType::BOOKING_CREATED => $this->bookingCreated($audience, $context),
            NotificationEventType::BOOKING_CONFIRMED => $this->bookingConfirmed($audience, $context),
            NotificationEventType::BOOKING_RESCHEDULED => $this->bookingRescheduled($audience, $context),
            NotificationEventType::BOOKING_CANCELLED => $this->bookingCancelled($audience, $context),
            NotificationEventType::BOOKING_CHECKED_IN => $this->simpleBookingUpdate($context, 'Customer checked in', "{$context['customer_name']} has checked in for {$context['service_names']}."),
            NotificationEventType::BOOKING_STARTED => $this->simpleBookingUpdate($context, 'Service started', "{$context['service_names']} for {$context['customer_name']} is now in progress."),
            NotificationEventType::BOOKING_COMPLETED => $this->bookingCompleted($audience, $context),
            NotificationEventType::BOOKING_NO_SHOW => $this->simpleBookingUpdate($context, 'Customer no-show', "{$context['customer_name']} did not show up for their {$context['date']} {$context['time']} appointment."),
            NotificationEventType::BOOKING_REMINDER => $this->bookingReminder($context),
            NotificationEventType::PAYMENT_SUCCEEDED => $this->message('Payment received', "Your payment of {$context['currency']} {$context['amount']} was successful.", $this->bookingLinkData($context)),
            NotificationEventType::PAYMENT_FAILED => $this->message('Payment failed', "Your payment of {$context['currency']} {$context['amount']} could not be processed. Please try again.", $this->subscriptionLinkData()),
            NotificationEventType::SUBSCRIPTION_ACTIVATED => $this->message('Subscription active', "Your {$context['plan_name']} subscription is now active.", $this->subscriptionLinkData()),
            NotificationEventType::SUBSCRIPTION_PAST_DUE => $this->message('Payment overdue', 'Your subscription payment is overdue. Please renew to avoid interruption.', $this->subscriptionLinkData()),
            NotificationEventType::SUBSCRIPTION_GRACE_PERIOD => $this->message('Subscription in grace period', "Your subscription will expire on {$context['grace_ends_at']} unless renewed.", $this->subscriptionLinkData()),
            NotificationEventType::SUBSCRIPTION_EXPIRED => $this->message('Subscription expired', 'Your subscription has expired. Renew now to restore access.', $this->subscriptionLinkData()),
            NotificationEventType::SUBSCRIPTION_CANCELLED => $this->message('Subscription cancelled', 'Your subscription has been cancelled.', $this->subscriptionLinkData()),
            NotificationEventType::MEMBERSHIP_ACTIVATED => $this->message('Membership active', "Your {$context['plan_name']} membership is now active until {$context['expires_at']}.", $this->membershipLinkData()),
            NotificationEventType::MEMBERSHIP_EXPIRED => $this->message('Membership expired', "Your {$context['plan_name']} membership has expired.", $this->membershipLinkData()),
            NotificationEventType::LOYALTY_POINTS_EARNED => $this->message('Points earned', "You earned {$context['points']} loyalty points from your recent visit.", $this->loyaltyLinkData()),
        };
    }

    private function bookingCreated(string $audience, array $context): array
    {
        $body = match ($audience) {
            'staff' => "You have a new appointment: {$context['service_names']} with {$context['customer_name']} on {$context['date']} at {$context['time']}.",
            'owner' => "New booking: {$context['service_names']} for {$context['customer_name']} on {$context['date']} at {$context['time']}.",
            default => "Your booking for {$context['service_names']} at {$context['salon_name']} on {$context['date']} at {$context['time']} has been received (ref {$context['booking_reference']}).",
        };

        return $this->message($audience === 'customer' ? 'Booking received' : 'New booking', $body, $this->bookingLinkData($context));
    }

    private function bookingConfirmed(string $audience, array $context): array
    {
        $body = match ($audience) {
            'staff' => "Confirmed: {$context['service_names']} with {$context['customer_name']} on {$context['date']} at {$context['time']}.",
            default => "Your booking at {$context['salon_name']} ({$context['branch_name']}) for {$context['service_names']} on {$context['date']} at {$context['time']} is confirmed. Ref {$context['booking_reference']}.",
        };

        return $this->message('Booking confirmed', $body, $this->bookingLinkData($context));
    }

    private function bookingRescheduled(string $audience, array $context): array
    {
        $body = match ($audience) {
            'staff' => "Appointment with {$context['customer_name']} moved from {$context['old_date']} {$context['old_time']} to {$context['date']} {$context['time']}.",
            default => "Your booking at {$context['salon_name']} was moved from {$context['old_date']} {$context['old_time']} to {$context['date']} {$context['time']}. Ref {$context['booking_reference']}.",
        };

        return $this->message('Booking rescheduled', $body, $this->bookingLinkData($context));
    }

    private function bookingCancelled(string $audience, array $context): array
    {
        $reasonSuffix = filled($context['reason'] ?? null) ? " Reason: {$context['reason']}." : '';
        $body = match ($audience) {
            'staff' => "The {$context['date']} {$context['time']} appointment with {$context['customer_name']} was cancelled.{$reasonSuffix}",
            'owner' => "Booking ref {$context['booking_reference']} ({$context['customer_name']}, {$context['date']} {$context['time']}) was cancelled.{$reasonSuffix}",
            default => "Your booking at {$context['salon_name']} on {$context['date']} at {$context['time']} was cancelled.{$reasonSuffix}",
        };

        return $this->message('Booking cancelled', $body, $this->bookingLinkData($context));
    }

    private function bookingCompleted(string $audience, array $context): array
    {
        $body = $audience === 'customer'
            ? "Thanks for visiting {$context['salon_name']}! Your {$context['service_names']} appointment is complete."
            : "Completed: {$context['service_names']} for {$context['customer_name']}.";

        return $this->message('Appointment completed', $body, $this->bookingLinkData($context));
    }

    private function bookingReminder(array $context): array
    {
        $body = "Reminder: your appointment for {$context['service_names']} at {$context['salon_name']} is on {$context['date']} at {$context['time']}.";

        return $this->message('Upcoming appointment', $body, $this->bookingLinkData($context));
    }

    private function simpleBookingUpdate(array $context, string $title, string $body): array
    {
        return $this->message($title, $body, $this->bookingLinkData($context));
    }

    private function bookingLinkData(array $context): array
    {
        return ['deep_link' => 'booking', 'booking_id' => $context['booking_id'] ?? null];
    }

    private function subscriptionLinkData(): array
    {
        return ['deep_link' => 'subscription'];
    }

    private function membershipLinkData(): array
    {
        return ['deep_link' => 'membership'];
    }

    private function loyaltyLinkData(): array
    {
        return ['deep_link' => 'loyalty'];
    }

    private function message(string $title, string $body, array $data): array
    {
        return ['title' => $title, 'body' => $body, 'data' => $data];
    }
}
