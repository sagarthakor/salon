<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PlanResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'code' => $this->code,
            'description' => $this->description,
            'amount' => $this->amount,
            'currency' => $this->currency,
            'billing_interval' => $this->billing_interval->value,
            'billing_interval_count' => $this->billing_interval_count,
            'trial_days' => $this->trial_days,
            'is_active' => $this->is_active,
            'features' => $this->features,
        ];
    }
}
