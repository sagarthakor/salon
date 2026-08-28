<?php

namespace App\Http\Requests\Staff;

use App\Enums\BusinessStatus;
use App\Enums\CommissionType;
use App\Enums\StaffGender;
use App\Enums\TenantMembershipRole;
use App\Models\Staff;
use App\Support\TenantContext;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class StaffRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId = app(TenantContext::class)->id();
        $current = Staff::query()->find($this->route('staff'));

        return [
            'user_id' => ['nullable', Rule::exists('tenant_user', 'user_id')->where(fn ($query) => $query->where('tenant_id', $tenantId)->where('role', TenantMembershipRole::STAFF->value)), Rule::unique('staff_profiles', 'user_id')->where('tenant_id', $tenantId)->ignore($current?->id)],
            'name' => ['required', 'string', 'max:150'],
            'photo' => ['nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120', 'dimensions:min_width=100,min_height=100,max_width=4000,max_height=4000'],
            'phone' => ['nullable', 'string', 'max:32', 'regex:/^[0-9+() .-]+$/'],
            'email' => ['nullable', 'email:rfc', 'max:255'],
            'gender' => ['required', Rule::enum(StaffGender::class)],
            'bio' => ['nullable', 'string', 'max:5000'],
            'joining_date' => ['nullable', 'date_format:Y-m-d'],
            'status' => ['nullable', Rule::enum(BusinessStatus::class)],
            'commission_type' => ['nullable', Rule::enum(CommissionType::class)],
            'commission_value' => ['nullable', 'numeric', 'min:0'],
            'branch_ids' => ['nullable', 'array'],
            'branch_ids.*' => ['distinct', Rule::exists('branches', 'id')->where('tenant_id', $tenantId)],
        ];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            $type = $this->input('commission_type');
            $value = $this->input('commission_value');
            if ($type && $value === null) {
                $validator->errors()->add('commission_value', 'A commission value is required when a commission type is set.');
            }
            if (! $type && $value !== null) {
                $validator->errors()->add('commission_type', 'A commission type is required when a commission value is set.');
            }
            if ($type === CommissionType::PERCENTAGE->value && $value !== null && $value > 100) {
                $validator->errors()->add('commission_value', 'A percentage commission cannot exceed 100.');
            }
        }];
    }
}
