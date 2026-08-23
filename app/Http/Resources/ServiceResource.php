<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ServiceResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return ['id' => $this->id, 'branch_id' => $this->branch_id, 'category' => new ServiceCategoryResource($this->whenLoaded('category')), 'name' => $this->name, 'slug' => $this->slug, 'description' => $this->description, 'gender' => $this->gender->value, 'price' => $this->price, 'duration_minutes' => $this->duration_minutes, 'image' => $this->image, 'status' => $this->status->value, 'sort_order' => $this->sort_order];
    }
}
