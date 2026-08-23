<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class BranchWorkingHourResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return ['day_of_week' => $this->day_of_week, 'is_open' => $this->is_open, 'opening_time' => $this->opening_time ? substr($this->opening_time, 0, 5) : null, 'closing_time' => $this->closing_time ? substr($this->closing_time, 0, 5) : null];
    }
}
