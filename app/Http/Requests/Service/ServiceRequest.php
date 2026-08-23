<?php

namespace App\Http\Requests\Service;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Models\Branch;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Support\TenantContext;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class ServiceRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $branch = Branch::query()->find($this->input('branch_id'));
        $current = Service::query()->find($this->route('service'));

        return ['branch_id' => ['required', Rule::exists('branches', 'id')->where('tenant_id', app(TenantContext::class)->id())], 'category_id' => ['required', Rule::exists('service_categories', 'id')->where('tenant_id', app(TenantContext::class)->id())], 'name' => ['required', 'string', 'max:150'], 'slug' => ['nullable', 'string', 'max:150', 'regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/', Rule::unique('services', 'slug')->where('branch_id', $branch?->id)->ignore($current?->id)], 'description' => ['nullable', 'string', 'max:5000'], 'gender' => ['required', Rule::enum(GenderType::class)], 'price' => ['required', 'decimal:0,2', 'min:0'], 'duration_minutes' => ['required', 'integer', 'min:1', 'max:1440'], 'image' => ['nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120', 'dimensions:min_width=100,min_height=100,max_width=4000,max_height=4000'], 'status' => ['nullable', Rule::enum(BusinessStatus::class)], 'sort_order' => ['nullable', 'integer', 'min:0', 'max:65535']];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            $branch = $this->input('branch_id');
            $category = ServiceCategory::query()->find($this->input('category_id'));
            if ($branch && $category && $category->branch_id !== $branch) {
                $validator->errors()->add('category_id', 'The category must belong to the selected branch.');
            }
        }];
    }
}
