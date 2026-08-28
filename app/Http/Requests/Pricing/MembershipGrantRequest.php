<?php

namespace App\Http\Requests\Pricing;

use App\Support\TenantContext;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class MembershipGrantRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId = app(TenantContext::class)->id();

        return [
            'customer_id' => ['required', Rule::exists('customer_profiles', 'id')->where('tenant_id', $tenantId)],
            'membership_plan_id' => ['required', Rule::exists('membership_plans', 'id')->where('tenant_id', $tenantId)->where('is_active', true)],
        ];
    }
}
