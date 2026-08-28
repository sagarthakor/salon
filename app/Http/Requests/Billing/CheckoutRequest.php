<?php

namespace App\Http\Requests\Billing;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Deliberately accepts only `plan_id` — never `amount`/`price`/`currency`.
 * The server always resolves those from the database plan row; see
 * SAAS_BILLING_ARCHITECTURE.md, "Amount tampering".
 */
class CheckoutRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'plan_id' => ['required', 'string', Rule::exists('plans', 'id')->where('is_active', true)],
        ];
    }
}
