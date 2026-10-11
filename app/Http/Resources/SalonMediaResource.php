<?php

namespace App\Http\Resources;

use App\Models\SalonMedia;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\Storage;

/** @mixin SalonMedia */
class SalonMediaResource extends JsonResource
{
    protected function base(): array
    {
        $disk = Storage::disk(SalonMedia::disk());
        $native = $this->hasNativeVideo();
        $thumbnail = $this->thumbnailUrl();
        $photo = $this->isPhoto();
        $service = $this->relationLoaded('service') ? $this->service : null;
        if ($service !== null && $service->status->value !== 'active') {
            $service = null;
        }

        return [
            'id' => $this->id,
            'media_type' => $this->media_type,
            'category' => $this->category?->value,
            'category_label' => $this->category?->label(),
            'caption' => $this->caption,
            'branch_id' => $this->branch_id,
            'service' => $service === null ? null : ['id' => $service->id, 'name' => $service->name, 'branch_id' => $service->branch_id],
            'instagram_url' => $this->instagram_url,
            'has_native_video' => $native,
            // Only hosted, salon-owned files are ever exposed as a playable URL.
            'video_url' => $native ? $disk->url($this->video_path) : null,
            'thumbnail_url' => $thumbnail,
            // How the app should present this item: native player, Instagram
            // link-out, or neither (no fake play button).
            'playback' => $photo ? 'image' : ($native ? 'native' : ($this->instagram_url !== null ? 'instagram' : 'none')),
            // Photos: the full-size image to show in the viewer (same file as the thumbnail).
            'image_url' => $photo ? $thumbnail : null,
            'sort_order' => $this->sort_order,
            'posted_at' => $this->instagram_posted_at?->toIso8601String(),
        ];
    }

    public function toArray(Request $request): array
    {
        return $this->base() + [
            'source' => $this->source->value,
            'is_active' => $this->is_active,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
