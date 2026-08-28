<?php

namespace App\Http\Requests\Pricing;

use App\Enums\CouponDiscountType;
use App\Models\MembershipPlan;
use App\Support\TenantContext;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class MembershipPlanRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId = app(TenantContext::class)->id();

        return [
            'name' => ['required', 'string', 'max:150'],
            'code' => ['required', 'string', 'max:32'],
            'description' => ['nullable', 'string', 'max:2000'],
            'price' => ['required', 'numeric', 'min:0'],
            'currency' => ['nullable', 'string', 'size:3'],
            'duration_days' => ['required', 'integer', 'min:1'],
            'discount_type' => ['required', Rule::enum(CouponDiscountType::class)],
            'discount_value' => ['required', 'numeric', 'min:0.01'],
            'maximum_discount_amount' => ['nullable', 'numeric', 'min:0'],
            'is_active' => ['nullable', 'boolean'],
            'service_ids' => ['nullable', 'array'],
            'service_ids.*' => [Rule::exists('services', 'id')->where('tenant_id', $tenantId)],
            'category_ids' => ['nullable', 'array'],
            'category_ids.*' => [Rule::exists('service_categories', 'id')->where('tenant_id', $tenantId)],
        ];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            if ($this->input('discount_type') === CouponDiscountType::PERCENTAGE->value && (float) $this->input('discount_value') > 100) {
                $validator->errors()->add('discount_value', 'A percentage discount cannot exceed 100.');
            }
            if (! $this->filled('code')) {
                return;
            }
            $tenantId = app(TenantContext::class)->id();
            $existing = MembershipPlan::withoutGlobalScope('tenant')->where('tenant_id', $tenantId)->where('code', $this->input('code'));
            if ($this->route('membership_plan') !== null) {
                $existing->whereKeyNot($this->route('membership_plan'));
            }
            if ($existing->exists()) {
                $validator->errors()->add('code', 'This plan code is already in use.');
            }
        }];
    }
}
