<?php

namespace App\Http\Requests\Billing;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * `plan_id` is optional here (unlike `CheckoutRequest`) — omitting it
 * renews on the subscription's current plan. Either way, amount/currency
 * are always resolved server-side from the database plan row.
 */
class RenewRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'plan_id' => ['nullable', 'string', Rule::exists('plans', 'id')->where('is_active', true)],
        ];
    }
}
