<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\Storage;

class ServiceResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return ['id' => $this->id, 'branch_id' => $this->branch_id, 'category' => new ServiceCategoryResource($this->whenLoaded('category')), 'name' => $this->name, 'slug' => $this->slug, 'description' => $this->description, 'gender' => $this->gender->value, 'price' => $this->price, 'duration_minutes' => $this->duration_minutes, 'image_url' => $this->image === null ? null : Storage::disk('public')->url($this->image), 'instagram_url' => $this->instagram_url, 'status' => $this->status->value, 'sort_order' => $this->sort_order];
    }
}
