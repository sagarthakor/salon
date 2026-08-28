<?php

namespace App\Http\Requests\Customer;

use App\Enums\BusinessStatus;
use App\Enums\CustomerGender;
use App\Enums\UserRole;
use App\Models\Customer;
use App\Support\TenantContext;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class CustomerRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId = app(TenantContext::class)->id();
        $current = Customer::query()->find($this->route('customer'));

        return [
            'user_id' => ['nullable', Rule::exists('users', 'id')->where('role', UserRole::CUSTOMER->value), Rule::unique('customer_profiles', 'user_id')->where('tenant_id', $tenantId)->ignore($current?->id)],
            'name' => ['required', 'string', 'max:150'],
            'phone' => ['required', 'string', 'max:32', 'regex:/^[0-9+() .-]+$/'],
            'country_code' => ['nullable', 'string', 'max:6', 'regex:/^\+?[0-9]{1,4}$/'],
            'email' => ['nullable', 'email:rfc', 'max:255'],
            'gender' => ['nullable', Rule::enum(CustomerGender::class)],
            'date_of_birth' => ['nullable', 'date_format:Y-m-d', 'before:today'],
            'profile_photo' => ['nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120', 'dimensions:min_width=100,min_height=100,max_width=4000,max_height=4000'],
            'address' => ['nullable', 'string', 'max:2000'],
            'status' => ['nullable', Rule::enum(BusinessStatus::class)],
        ];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            $phone = $this->input('phone');
            if (! $phone) {
                return;
            }
            $normalized = Customer::normalizePhone($phone, $this->input('country_code'));
            $current = Customer::query()->find($this->route('customer'));
            $duplicate = Customer::query()->where('normalized_phone', $normalized)->when($current, fn ($query, $customer) => $query->whereKeyNot($customer->id))->exists();
            if ($duplicate) {
                $validator->errors()->add('phone', 'A customer with this phone number already exists.');
            }
        }];
    }
}
