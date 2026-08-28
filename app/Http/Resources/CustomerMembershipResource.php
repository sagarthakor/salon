<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class CustomerMembershipResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'customer' => new CustomerResource($this->whenLoaded('customer')),
            'plan' => new MembershipPlanResource($this->whenLoaded('membershipPlan')),
            'status' => $this->status->value,
            'starts_at' => $this->starts_at->toIso8601String(),
            'expires_at' => $this->expires_at->toIso8601String(),
            'purchased_amount' => $this->purchased_amount,
            'currency' => $this->currency,
            'source' => $this->source,
            'is_currently_active' => $this->isCurrentlyActive(),
        ];
    }
}
