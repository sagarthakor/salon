<?php

namespace App\Http\Requests\Salon;

use App\Enums\SalonSettingKey;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

class SalonSettingsRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return ['settings' => ['required', 'array'], 'settings.*' => ['nullable']];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            foreach (array_keys($this->input('settings', [])) as $key) {
                if (SalonSettingKey::tryFrom($key) === null) {
                    $validator->errors()->add("settings.$key", 'This setting is not supported.');
                }
            }
        }];
    }
}
