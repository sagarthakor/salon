<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class StaffResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'user_id' => $this->user_id,
            'name' => $this->name,
            'photo' => $this->photo,
            'phone' => $this->phone,
            'email' => $this->email,
            'gender' => $this->gender->value,
            'bio' => $this->bio,
            'joining_date' => $this->joining_date?->format('Y-m-d'),
            'status' => $this->status->value,
            'commission_type' => $this->commission_type?->value,
            'commission_value' => $this->commission_value,
            'branches' => BranchResource::collection($this->whenLoaded('branches')),
        ];
    }
}
