<?php

namespace App\Http\Requests\Service;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Models\Branch;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Support\InstagramUrl;
use App\Support\TenantContext;
use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class ServiceRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Normalizes `instagram_url` (scheme defaulted to https, host
     * lowercased) before validation runs, so a harmless variation like
     * `instagram.com/p/ABC` or `http://www.Instagram.com/p/ABC` validates
     * and stores identically to the canonical form — never changing which
     * post it points to. See InstagramUrl::normalize().
     */
    protected function prepareForValidation(): void
    {
        if ($this->filled('instagram_url')) {
            $this->merge(['instagram_url' => InstagramUrl::normalize($this->string('instagram_url')->toString())]);
        }
    }

    public function rules(): array
    {
        $branch = Branch::query()->find($this->input('branch_id'));
        $current = Service::query()->find($this->route('service'));

        return ['branch_id' => ['required', Rule::exists('branches', 'id')->where('tenant_id', app(TenantContext::class)->id())], 'category_id' => ['required', Rule::exists('service_categories', 'id')->where('tenant_id', app(TenantContext::class)->id())], 'name' => ['required', 'string', 'max:150'], 'slug' => ['nullable', 'string', 'max:150', 'regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/', Rule::unique('services', 'slug')->where('branch_id', $branch?->id)->ignore($current?->id)], 'description' => ['nullable', 'string', 'max:5000'], 'gender' => ['required', Rule::enum(GenderType::class)], 'price' => ['required', 'decimal:0,2', 'min:0'], 'duration_minutes' => ['required', 'integer', 'min:1', 'max:1440'], 'image' => ['nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120', 'dimensions:min_width=100,min_height=100,max_width=4000,max_height=4000'], 'instagram_url' => ['nullable', 'string', 'max:500', function (string $attribute, mixed $value, Closure $fail): void {
            if (is_string($value) && ! InstagramUrl::isValid($value)) {
                $fail('The Instagram URL must be a valid instagram.com post, reel, or video link.');
            }
        }], 'status' => ['nullable', Rule::enum(BusinessStatus::class)], 'sort_order' => ['nullable', 'integer', 'min:0', 'max:65535']];
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
