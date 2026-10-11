<?php

namespace App\Http\Requests\Media;

use App\Enums\SalonMediaCategory;
use App\Models\SalonMedia;
use App\Models\Service;
use App\Support\InstagramUrl;
use App\Support\TenantContext;
use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class SalonMediaRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    protected function prepareForValidation(): void
    {
        if ($this->filled('instagram_url')) {
            $normalized = InstagramUrl::normalize($this->string('instagram_url')->toString());
            // One spelling per Reel; an invalid link is left as typed so the rule below rejects it.
            $this->merge(['instagram_url' => InstagramUrl::canonical($normalized) ?? $normalized]);
        }
    }

    private function isCreate(): bool
    {
        return $this->route('media') === null;
    }

    public function rules(): array
    {
        $tenantId = app(TenantContext::class)->id();
        $presence = $this->isCreate() ? 'nullable' : 'sometimes';

        return [
            'branch_id' => ['nullable', Rule::exists('branches', 'id')->where('tenant_id', $tenantId)],
            'service_id' => ['nullable', Rule::exists('services', 'id')->where('tenant_id', $tenantId)->whereNull('deleted_at')],
            'category' => ['nullable', Rule::enum(SalonMediaCategory::class)],
            'caption' => ['nullable', 'string', 'max:2200'],
            'is_active' => ['sometimes', 'boolean'],
            'sort_order' => ['nullable', 'integer', 'min:0', 'max:1000000'],
            'instagram_url' => [$presence, 'string', 'max:500', function (string $attribute, mixed $value, Closure $fail): void {
                if (is_string($value) && ! InstagramUrl::isValid($value)) {
                    $fail('The Instagram URL must be a valid instagram.com post, reel, or video link.');
                }
            }],
            'video' => [$presence, 'file', 'mimes:mp4,mov', 'mimetypes:video/mp4,video/quicktime', 'max:'.config('salon_media.max_video_kb')],
            'image' => [$presence, 'image', 'mimes:jpg,jpeg,png,webp', 'max:'.config('salon_media.max_image_kb')],
            'thumbnail' => [$presence, 'image', 'mimes:jpg,jpeg,png,webp', 'max:'.config('salon_media.max_thumbnail_kb')],
            'remove_video' => ['sometimes', 'boolean'],
            'remove_thumbnail' => ['sometimes', 'boolean'],
        ];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            if ($this->isCreate() && ! $this->hasFile('video') && ! $this->hasFile('image') && ! $this->filled('instagram_url')) {
                $validator->errors()->add('video', 'Upload a photo or video, or provide an Instagram link.');
            }
            if ($this->hasFile('image') && $this->hasFile('video')) {
                $validator->errors()->add('image', 'Add either a photo or a video, not both.');
            }
            if ($this->filled('service_id') && $this->filled('branch_id')) {
                $service = Service::query()->find($this->input('service_id'));
                if ($service !== null && $service->branch_id !== $this->input('branch_id')) {
                    $validator->errors()->add('service_id', 'The service must belong to the selected branch.');
                }
            }
            $shortcode = $this->filled('instagram_url') ? InstagramUrl::shortcode($this->input('instagram_url')) : null;
            if ($shortcode !== null) {
                $existing = SalonMedia::query()->where('instagram_shortcode', $shortcode)
                    ->when(! $this->isCreate(), fn ($q) => $q->whereKeyNot($this->route('media')))
                    ->exists();
                if ($existing) {
                    $validator->errors()->add('instagram_url', 'This Instagram link is already in your gallery.');
                }
            }
        }];
    }
}
