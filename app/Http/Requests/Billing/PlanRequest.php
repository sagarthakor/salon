<?php

namespace App\Http\Requests\Billing;

use App\Enums\BillingInterval;
use App\Models\Plan;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class PlanRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $current = Plan::query()->find($this->route('plan'));

        return [
            'name' => ['required', 'string', 'max:150'],
            'code' => ['required', 'string', 'max:50', 'alpha_dash', Rule::unique('plans', 'code')->ignore($current?->id)],
            'description' => ['nullable', 'string', 'max:2000'],
            'amount' => ['required', 'numeric', 'min:0'],
            'currency' => ['required', 'string', 'size:3'],
            'billing_interval' => ['required', Rule::enum(BillingInterval::class)],
            'billing_interval_count' => ['required', 'integer', 'min:1'],
            'trial_days' => ['required', 'integer', 'min:0'],
            'is_active' => ['nullable', 'boolean'],
            'features' => ['nullable', 'array'],
        ];
    }
}
