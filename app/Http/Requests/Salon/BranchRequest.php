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

        return ['name' => ['required', 'string', 'max:150'], 'slug' => ['nullable', 'string', 'max:150', 'regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/', Rule::unique('branches', 'slug')->where('tenant_id', app(TenantContext::class)->id())->ignore($branch?->id)], 'phone' => ['nullable', 'string', 'max:32', 'regex:/^[0-9+() .-]+$/'], 'email' => ['nullable', 'email:rfc', 'max:255'], 'address_line_1' => ['nullable', 'string', 'max:255'], 'address_line_2' => ['nullable', 'string', 'max:255'], 'city' => ['nullable', 'string', 'max:100'], 'state' => ['nullable', 'string', 'max:100'], 'country' => ['nullable', 'string', 'size:2'], 'postal_code' => ['nullable', 'string', 'max:32'], 'latitude' => ['nullable', 'numeric', 'between:-90,90'], 'longitude' => ['nullable', 'numeric', 'between:-180,180'], 'timezone' => ['nullable', 'timezone'], 'status' => ['nullable', Rule::enum(BusinessStatus::class)]];
    }
}
