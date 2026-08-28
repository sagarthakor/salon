<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class CouponResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'code' => $this->code,
            'name' => $this->name,
            'description' => $this->description,
            'discount_type' => $this->discount_type->value,
            'discount_value' => $this->discount_value,
            'minimum_booking_amount' => $this->minimum_booking_amount,
            'maximum_discount_amount' => $this->maximum_discount_amount,
            'starts_at' => $this->starts_at?->toIso8601String(),
            'expires_at' => $this->expires_at?->toIso8601String(),
            'usage_limit' => $this->usage_limit,
            'usage_limit_per_customer' => $this->usage_limit_per_customer,
            'usage_count' => $this->usage_count,
            'is_active' => $this->is_active,
            'first_booking_only' => $this->first_booking_only,
            'service_ids' => $this->whenLoaded('services', fn () => $this->services->pluck('id')),
            'category_ids' => $this->whenLoaded('categories', fn () => $this->categories->pluck('id')),
            'created_at' => $this->created_at->toIso8601String(),
        ];
    }
}
