<?php

namespace App\Http\Requests\Customer;

use App\Enums\CustomerGender;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class CustomerProfileRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:150'],
            'phone' => ['required', 'string', 'max:32', 'regex:/^[0-9+() .-]+$/'],
            'country_code' => ['nullable', 'string', 'max:6', 'regex:/^\+?[0-9]{1,4}$/'],
            'email' => ['nullable', 'email:rfc', 'max:255'],
            'gender' => ['nullable', Rule::enum(CustomerGender::class)],
            'date_of_birth' => ['nullable', 'date_format:Y-m-d', 'before:today'],
            'profile_photo' => ['nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120', 'dimensions:min_width=100,min_height=100,max_width=4000,max_height=4000'],
            'address' => ['nullable', 'string', 'max:2000'],
        ];
    }
}
