<?php

namespace App\Http\Requests\Booking;

use App\Models\Branch;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class CustomerBookingRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $branch = Branch::withoutGlobalScope('tenant')->find($this->input('branch_id'));
        $tenantId = $branch?->tenant_id;

        return [
            'branch_id' => ['required', 'exists:branches,id'],
            'date' => ['required', 'date_format:Y-m-d'],
            'start_time' => ['required', 'date_format:H:i'],
            'items' => ['required', 'array', 'min:1'],
            'items.*.service_id' => ['required', Rule::exists('services', 'id')->where('tenant_id', $tenantId)],
            'items.*.staff_id' => ['nullable', Rule::exists('staff_profiles', 'id')->where('tenant_id', $tenantId)],
            'notes' => ['nullable', 'string', 'max:2000'],
            'coupon_code' => ['nullable', 'string', 'max:32'],
            'loyalty_points_to_redeem' => ['nullable', 'integer', 'min:1'],
        ];
    }
}
