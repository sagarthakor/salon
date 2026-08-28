<?php

namespace App\Http\Requests\Notifications;

use App\Enums\DevicePlatform;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class DeviceTokenRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'platform' => ['required', Rule::enum(DevicePlatform::class)],
            'token' => ['required', 'string', 'max:512'],
            'device_identifier' => ['nullable', 'string', 'max:255'],
        ];
    }
}
