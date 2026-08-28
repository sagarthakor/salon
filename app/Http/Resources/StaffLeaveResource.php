<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class StaffLeaveResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return ['id' => $this->id, 'start_date' => $this->start_date->format('Y-m-d'), 'end_date' => $this->end_date->format('Y-m-d'), 'reason' => $this->reason, 'status' => $this->status->value];
    }
}
