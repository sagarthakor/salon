<?php

namespace App\Http\Requests\Booking;

use App\Support\TenantContext;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class BookingRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId = app(TenantContext::class)->id();

        return [
            'branch_id' => ['required', Rule::exists('branches', 'id')->where('tenant_id', $tenantId)],
            'customer_id' => ['required', Rule::exists('customer_profiles', 'id')->where('tenant_id', $tenantId)],
            'date' => ['required', 'date_format:Y-m-d'],
            'start_time' => ['required', 'date_format:H:i'],
            'items' => ['required', 'array', 'min:1'],
            'items.*.service_id' => ['required', Rule::exists('services', 'id')->where('tenant_id', $tenantId)],
            'items.*.staff_id' => ['nullable', Rule::exists('staff_profiles', 'id')->where('tenant_id', $tenantId)],
            'notes' => ['nullable', 'string', 'max:2000'],
            // Phase 12 — validity/availability is re-checked server-side
            // regardless of what is sent here; see BookingPricingService.
            'coupon_code' => ['nullable', 'string', 'max:32'],
            'loyalty_points_to_redeem' => ['nullable', 'integer', 'min:1'],
        ];
    }
}
