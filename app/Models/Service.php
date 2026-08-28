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

class Service extends Model
{
    use BelongsToTenant, HasUlids, SoftDeletes;

    protected $fillable = ['branch_id', 'category_id', 'name', 'slug', 'description', 'gender', 'price', 'duration_minutes', 'image', 'status', 'sort_order'];

    protected function casts(): array
    {
        return ['gender' => GenderType::class, 'status' => BusinessStatus::class, 'price' => 'decimal:2'];
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
