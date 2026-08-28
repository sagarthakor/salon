<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class LoyaltyAccountResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'balance' => $this->balance,
            'lifetime_earned' => $this->lifetime_earned,
            'lifetime_redeemed' => $this->lifetime_redeemed,
            // Only present when eager-loaded — LoyaltyManagementController::index()
            // (the owner's cross-customer search list) loads it; every
            // customer-scoped/single-account endpoint does not, since the
            // caller already knows which customer they asked for.
            'customer' => new CustomerResource($this->whenLoaded('customer')),
        ];
    }
}
