<?php

namespace App\Services\Notifications;

use App\Enums\TenantMembershipRole;
use App\Models\Booking;
use App\Models\Staff;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Support\Collection;

/**
 * Resolves who should receive a booking notification, entirely server-side
 * — a customer profile's linked user, the distinct assigned staff's linked
 * users, and the tenant's owner user(s). Never trusts a client-supplied
 * recipient id (see NOTIFICATION_ARCHITECTURE.md, "Recipient resolution").
 * A Customer/Staff profile with no linked `user_id` (no login account yet)
 * simply has no in-app recipient — that's expected, not an error.
 */
class BookingRecipientResolver
{
    public function customerUser(Booking $booking): ?User
    {
        return $booking->customer?->user;
    }

    public function customerPhone(Booking $booking): ?string
    {
        return $this->formatPhone($booking->customer?->normalized_phone);
    }

    /**
     * @return Collection<int, User>
     */
    public function staffUsers(Booking $booking): Collection
    {
        return $booking->items->map(fn ($item) => $item->staff)
            ->filter()
            ->unique('id')
            ->map(fn (Staff $staff) => $staff->user)
            ->filter()
            ->unique('id')
            ->values();
    }

    /**
     * @return Collection<int, User>
     */
    public function ownerUsers(Tenant $tenant): Collection
    {
        return $tenant->users()->wherePivot('role', TenantMembershipRole::SALON_OWNER->value)->get();
    }

    private function formatPhone(?string $raw): ?string
    {
        if (blank($raw)) {
            return null;
        }

        return str_starts_with($raw, '+') ? $raw : '+'.$raw;
    }
}
