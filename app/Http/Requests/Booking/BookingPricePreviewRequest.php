<?php

namespace App\Http\Requests\Booking;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Deliberately loose service/branch existence rules (unlike BookingRequest,
 * which scopes `exists` to the current tenant context) — the owner and
 * customer preview endpoints share this request, and the customer one has
 * no `tenant.context` to scope against (see CustomerBookingRequest for the
 * same pattern). Each controller resolves the branch/tenant itself and
 * revalidates service ownership from there. This endpoint never creates a
 * booking — see "Price preview" in
 * LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md.
 */
class BookingPricePreviewRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'branch_id' => ['required', 'exists:branches,id'],
            // Required for the owner-side preview (which customer's
            // membership/loyalty account applies); ignored by the
            // customer-side preview, which always prices for the caller's
            // own profile regardless of what is sent here.
            'customer_id' => ['nullable', 'exists:customer_profiles,id'],
            'service_ids' => ['required', 'array', 'min:1'],
            'service_ids.*' => ['required', 'exists:services,id'],
            'coupon_code' => ['nullable', 'string', 'max:32'],
            'loyalty_points_to_redeem' => ['nullable', 'integer', 'min:1'],
        ];
    }
}
