<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class BookingResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'branch_id' => $this->branch_id,
            'customer' => new CustomerResource($this->whenLoaded('customer')),
            'booking_date' => $this->booking_date->format('Y-m-d'),
            'start_time' => $this->start_time ? substr($this->start_time, 0, 5) : null,
            'end_time' => $this->end_time ? substr($this->end_time, 0, 5) : null,
            'status' => $this->status->value,
            'subtotal' => $this->subtotal,
            'discount' => $this->discount,
            'tax' => $this->tax,
            'total' => $this->total,
            // Phase 12 pricing breakdown — `discount` above remains the
            // combined total for backward compatibility. See
            // LOYALTY_MEMBERSHIP_COUPON_ARCHITECTURE.md, "Booking snapshot".
            'coupon_code' => $this->coupon_code,
            'coupon_discount' => $this->coupon_discount,
            'membership_discount' => $this->membership_discount,
            'loyalty_points_redeemed' => $this->loyalty_points_redeemed,
            'loyalty_discount' => $this->loyalty_discount,
            'loyalty_points_earned' => $this->loyalty_points_earned,
            // "Book This Style": the gallery item that inspired this booking. `label` is a
            // snapshot; `thumbnail_url` is present only while the item still exists.
            'style' => $this->salon_media_id === null && $this->style_label === null ? null : [
                'id' => $this->salon_media_id,
                'label' => $this->style_label,
                'category_label' => $this->relationLoaded('styleMedia') ? $this->styleMedia?->category?->label() : null,
                'thumbnail_url' => $this->relationLoaded('styleMedia') ? $this->styleMedia?->thumbnailUrl() : null,
            ],
            'notes' => $this->notes,
            'cancellation_reason' => $this->cancellation_reason,
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'items' => BookingItemResource::collection($this->whenLoaded('items')),
            'status_history' => BookingStatusHistoryResource::collection($this->whenLoaded('statusHistories')),
        ];
    }
}
