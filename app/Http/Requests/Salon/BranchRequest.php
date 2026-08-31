<?php

namespace App\Http\Requests\Salon;

use App\Enums\BusinessStatus;
use App\Models\Branch;
use App\Support\TenantContext;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class BranchRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $branch = Branch::query()->find($this->route('branch'));

        // Required on create only: a branch silently defaulting to the
        // `timezone` column's DB default ('UTC') when the owner's real salon
        // is elsewhere is what let same-day past time slots keep showing as
        // available (AvailabilityService/BookingService already compare
        // against `now()` in this exact timezone — see BOOKING_ENGINE.md).
        // Nullable on update so editing any other field never forces
        // resending an unrelated one, and an existing branch's current value
        // is left untouched either way. Deliberately keyed off the raw route
        // parameter, not `$branch` above: `$branch` is tenant-scoped, so a
        // cross-tenant update attempt (a real {branch} id belonging to
        // another tenant) resolves to null there too — using it here would
        // misclassify that as a create and wrongly 422 on a missing
        // timezone instead of the controller's own 404 for a foreign id.
        $timezoneRule = $this->route('branch') === null ? 'required' : 'nullable';

        return ['name' => ['required', 'string', 'max:150'], 'slug' => ['nullable', 'string', 'max:150', 'regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/', Rule::unique('branches', 'slug')->where('tenant_id', app(TenantContext::class)->id())->ignore($branch?->id)], 'phone' => ['nullable', 'string', 'max:32', 'regex:/^[0-9+() .-]+$/'], 'email' => ['nullable', 'email:rfc', 'max:255'], 'address_line_1' => ['nullable', 'string', 'max:255'], 'address_line_2' => ['nullable', 'string', 'max:255'], 'city' => ['nullable', 'string', 'max:100'], 'state' => ['nullable', 'string', 'max:100'], 'country' => ['nullable', 'string', 'size:2'], 'postal_code' => ['nullable', 'string', 'max:32'], 'latitude' => ['nullable', 'numeric', 'between:-90,90'], 'longitude' => ['nullable', 'numeric', 'between:-180,180'], 'timezone' => [$timezoneRule, 'timezone'], 'status' => ['nullable', Rule::enum(BusinessStatus::class)]];
    }
}
