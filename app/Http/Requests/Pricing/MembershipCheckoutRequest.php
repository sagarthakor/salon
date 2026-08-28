<?php

namespace App\Http\Requests\Pricing;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Deliberately accepts only `membership_plan_id` — never a price. The
 * server always resolves the amount from the database plan row (see
 * MembershipService::initiateCheckout / "Money rule").
 */
class MembershipCheckoutRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'membership_plan_id' => ['required', 'string', 'exists:membership_plans,id'],
        ];
    }
}
