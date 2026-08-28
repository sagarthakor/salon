<?php

namespace App\Models;

use App\Enums\BusinessStatus;
use App\Enums\GenderType;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Storage;

class Service extends Model
{
    use BelongsToTenant, HasUlids, SoftDeletes;

    protected $fillable = ['branch_id', 'category_id', 'name', 'slug', 'description', 'gender', 'price', 'duration_minutes', 'image', 'instagram_url', 'status', 'sort_order'];

    protected function casts(): array
    {
        return ['gender' => GenderType::class, 'status' => BusinessStatus::class, 'price' => 'decimal:2'];
    }

    /**
     * A regular delete() is a soft delete — the image is deliberately kept
     * (the service, and its image, is recoverable). Only a genuine
     * forceDelete() — no code path calls this today, but nothing should
     * silently leak a file if one ever does — removes the stored image too.
     */
    protected static function booted(): void
    {
        static::forceDeleting(function (Service $service): void {
            if ($service->image !== null) {
                Storage::disk('public')->delete($service->image);
            }
        });
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(ServiceCategory::class, 'category_id');
    }

    public function staff(): BelongsToMany
    {
        return $this->belongsToMany(Staff::class, 'staff_services')->withTimestamps();
    }
}
