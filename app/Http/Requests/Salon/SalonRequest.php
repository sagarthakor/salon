<?php

namespace App\Http\Requests\Salon;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Models\Salon;
use App\Support\InstagramUrl;
use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class SalonRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Normalizes `instagram_url` before validation runs — see
     * ServiceRequest::prepareForValidation() for the identical rationale.
     */
    protected function prepareForValidation(): void
    {
        if ($this->filled('instagram_url')) {
            $this->merge(['instagram_url' => InstagramUrl::normalize($this->string('instagram_url')->toString())]);
        }
    }

    public function rules(): array
    {
        $currentSalon = $this->isMethod('post') ? null : Salon::query()->first();

        // Required on create only: this is what the auto-provisioned first
        // Branch inherits (SalonController::defaultBranchFor() copies
        // `$salon->timezone` verbatim), and what AvailabilityService/
        // BookingService compare "now" against for that branch's same-day
        // slots — see BranchRequest::rules() for the identical rationale.
        // Nullable on update so editing any other field never forces
        // resending it.
        $timezoneRule = $this->isMethod('post') ? 'required' : 'nullable';

        return ['name' => ['required', 'string', 'max:150'], 'slug' => ['nullable', 'string', 'max:150', 'regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/', Rule::unique('salons', 'slug')->ignore($currentSalon?->id)], 'description' => ['nullable', 'string', 'max:5000'], 'gender_type' => ['required', Rule::enum(GenderType::class)], 'logo' => ['nullable', 'string', 'max:2048'], 'cover_image' => ['nullable', 'string', 'max:2048'], 'phone' => ['nullable', 'string', 'max:32', 'regex:/^[0-9+() .-]+$/'], 'email' => ['nullable', 'email:rfc', 'max:255'], 'website' => ['nullable', 'url', 'max:255'], 'instagram_url' => ['nullable', 'string', 'max:500', function (string $attribute, mixed $value, Closure $fail): void {
            if (is_string($value) && ! InstagramUrl::isValidProfile($value)) {
                $fail('The Instagram URL must be a valid instagram.com profile link.');
            }
        }], 'address_line_1' => ['nullable', 'string', 'max:255'], 'address_line_2' => ['nullable', 'string', 'max:255'], 'city' => ['nullable', 'string', 'max:100'], 'state' => ['nullable', 'string', 'max:100'], 'country' => ['nullable', 'string', 'size:2'], 'postal_code' => ['nullable', 'string', 'max:32'], 'latitude' => ['nullable', 'numeric', 'between:-90,90'], 'longitude' => ['nullable', 'numeric', 'between:-180,180'], 'timezone' => [$timezoneRule, 'timezone'], 'status' => ['nullable', Rule::enum(BusinessStatus::class)]];
    }
}
