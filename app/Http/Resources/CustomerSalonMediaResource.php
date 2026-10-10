<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;

/** Public gallery shape: no visibility/source/admin fields. */
class CustomerSalonMediaResource extends SalonMediaResource
{
    public function toArray(Request $request): array
    {
        return $this->base();
    }
}
