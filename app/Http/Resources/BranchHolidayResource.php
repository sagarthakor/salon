<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class BranchHolidayResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return ['id' => $this->id, 'holiday_date' => $this->holiday_date->format('Y-m-d'), 'name' => $this->name, 'is_closed' => $this->is_closed];
    }
}
