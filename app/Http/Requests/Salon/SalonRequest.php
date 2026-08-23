<?php

namespace App\Http\Requests\Salon;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Models\Salon;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class SalonRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $currentSalon = $this->isMethod('post') ? null : Salon::query()->first();

        return ['name' => ['required', 'string', 'max:150'], 'slug' => ['nullable', 'string', 'max:150', 'regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/', Rule::unique('salons', 'slug')->ignore($currentSalon?->id)], 'description' => ['nullable', 'string', 'max:5000'], 'gender_type' => ['required', Rule::enum(GenderType::class)], 'logo' => ['nullable', 'string', 'max:2048'], 'cover_image' => ['nullable', 'string', 'max:2048'], 'phone' => ['nullable', 'string', 'max:32', 'regex:/^[0-9+() .-]+$/'], 'email' => ['nullable', 'email:rfc', 'max:255'], 'website' => ['nullable', 'url', 'max:255'], 'address_line_1' => ['nullable', 'string', 'max:255'], 'address_line_2' => ['nullable', 'string', 'max:255'], 'city' => ['nullable', 'string', 'max:100'], 'state' => ['nullable', 'string', 'max:100'], 'country' => ['nullable', 'string', 'size:2'], 'postal_code' => ['nullable', 'string', 'max:32'], 'latitude' => ['nullable', 'numeric', 'between:-90,90'], 'longitude' => ['nullable', 'numeric', 'between:-180,180'], 'timezone' => ['nullable', 'timezone'], 'status' => ['nullable', Rule::enum(BusinessStatus::class)]];
    }
}
