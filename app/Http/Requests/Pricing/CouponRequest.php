<?php

namespace App\Http\Requests\Pricing;

use App\Enums\CouponDiscountType;
use App\Models\Coupon;
use App\Support\TenantContext;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class CouponRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId = app(TenantContext::class)->id();

        return [
            'code' => ['required', 'string', 'max:32'],
            'name' => ['required', 'string', 'max:150'],
            'description' => ['nullable', 'string', 'max:2000'],
            'discount_type' => ['required', Rule::enum(CouponDiscountType::class)],
            'discount_value' => ['required', 'numeric', 'min:0.01'],
            'minimum_booking_amount' => ['nullable', 'numeric', 'min:0'],
            'maximum_discount_amount' => ['nullable', 'numeric', 'min:0'],
            'starts_at' => ['nullable', 'date'],
            'expires_at' => ['nullable', 'date', 'after:starts_at'],
            'usage_limit' => ['nullable', 'integer', 'min:1'],
            'usage_limit_per_customer' => ['nullable', 'integer', 'min:1'],
            'is_active' => ['nullable', 'boolean'],
            'first_booking_only' => ['nullable', 'boolean'],
            'service_ids' => ['nullable', 'array'],
            'service_ids.*' => [Rule::exists('services', 'id')->where('tenant_id', $tenantId)],
            'category_ids' => ['nullable', 'array'],
            'category_ids.*' => [Rule::exists('service_categories', 'id')->where('tenant_id', $tenantId)],
        ];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            if ($this->filled('discount_type') && $this->filled('discount_value') && $this->input('discount_type') === CouponDiscountType::PERCENTAGE->value) {
                if ((float) $this->input('discount_value') > 100) {
                    $validator->errors()->add('discount_value', 'A percentage discount cannot exceed 100.');
                }
            }
            if (! $this->filled('code')) {
                return;
            }
            $tenantId = app(TenantContext::class)->id();
            $normalized = Coupon::normalizeCode((string) $this->input('code'));
            $existing = Coupon::withoutGlobalScope('tenant')->where('tenant_id', $tenantId)->where('code', $normalized);
            if ($this->route('coupon') !== null) {
                $existing->whereKeyNot($this->route('coupon'));
            }
            if ($existing->exists()) {
                $validator->errors()->add('code', 'This coupon code is already in use.');
            }
        }];
    }
}
