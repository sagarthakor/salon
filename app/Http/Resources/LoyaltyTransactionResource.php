<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class LoyaltyTransactionResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'type' => $this->type->value,
            'points' => $this->points,
            'balance_after' => $this->balance_after,
            'description' => $this->description,
            'booking_id' => $this->booking_id,
            'created_at' => $this->created_at->toIso8601String(),
        ];
    }
}
