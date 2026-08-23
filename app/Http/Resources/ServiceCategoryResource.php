<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ServiceCategoryResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return ['id' => $this->id, 'branch_id' => $this->branch_id, 'name' => $this->name, 'slug' => $this->slug, 'description' => $this->description, 'image' => $this->image, 'status' => $this->status->value, 'sort_order' => $this->sort_order];
    }
}
