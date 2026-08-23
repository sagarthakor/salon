<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class BranchResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return ['id' => $this->id, 'name' => $this->name, 'slug' => $this->slug, 'phone' => $this->phone, 'email' => $this->email, 'address' => ['line_1' => $this->address_line_1, 'line_2' => $this->address_line_2, 'city' => $this->city, 'state' => $this->state, 'country' => $this->country, 'postal_code' => $this->postal_code], 'latitude' => $this->latitude, 'longitude' => $this->longitude, 'timezone' => $this->timezone, 'status' => $this->status->value];
    }
}
