<?php

namespace App\Http\Requests\Service;

use App\Enums\BusinessStatus;
use App\Models\Branch;
use App\Models\ServiceCategory;
use App\Support\TenantContext;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class ServiceCategoryRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $branch = Branch::query()->find($this->input('branch_id'));
        $current = ServiceCategory::query()->find($this->route('service_category'));

        return ['branch_id' => ['required', Rule::exists('branches', 'id')->where('tenant_id', app(TenantContext::class)->id())], 'name' => ['required', 'string', 'max:150'], 'slug' => ['nullable', 'string', 'max:150', 'regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/', Rule::unique('service_categories', 'slug')->where('branch_id', $branch?->id)->ignore($current?->id)], 'description' => ['nullable', 'string', 'max:5000'], 'image' => ['nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120', 'dimensions:min_width=100,min_height=100,max_width=4000,max_height=4000'], 'status' => ['nullable', Rule::enum(BusinessStatus::class)], 'sort_order' => ['nullable', 'integer', 'min:0', 'max:65535']];
    }
}
