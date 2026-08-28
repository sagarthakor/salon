<?php

namespace App\Http\Requests\Auth;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Self-service salon-owner registration — see OwnerRegistrationService. Only
 * ever produces a `salon_owner`; the role itself is never a request field
 * here, exactly like RegisterRequest never accepts one for the customer
 * path. `slug` is optional (auto-derived from `salon_name` when omitted) but
 * still validated with the same format/uniqueness rules a client-supplied
 * value would need, since OwnerRegistrationService reuses this validated
 * value as a first attempt before falling back to its own generation.
 */
class RegisterOwnerRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'string', 'email:filter', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', 'min:12', 'confirmed'],
            'salon_name' => ['required', 'string', 'max:150'],
            'slug' => ['nullable', 'string', 'max:150', 'alpha_dash', Rule::unique('tenants', 'slug')],
        ];
    }
}
