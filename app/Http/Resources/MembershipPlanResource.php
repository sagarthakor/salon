<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class MembershipPlanResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'code' => $this->code,
            'description' => $this->description,
            'price' => $this->price,
            'currency' => $this->currency,
            'duration_days' => $this->duration_days,
            'discount_type' => $this->discount_type->value,
            'discount_value' => $this->discount_value,
            'maximum_discount_amount' => $this->maximum_discount_amount,
            'is_active' => $this->is_active,
            'service_ids' => $this->whenLoaded('services', fn () => $this->services->pluck('id')),
            'category_ids' => $this->whenLoaded('categories', fn () => $this->categories->pluck('id')),
            'created_at' => $this->created_at->toIso8601String(),
        ];
    }
}
