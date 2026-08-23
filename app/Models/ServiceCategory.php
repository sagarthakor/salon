<?php

namespace App\Models;

use App\Enums\BusinessStatus;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class ServiceCategory extends Model
{
    use BelongsToTenant, HasUlids, SoftDeletes;

    protected $fillable = ['branch_id', 'name', 'slug', 'description', 'image', 'status', 'sort_order'];

    protected function casts(): array
    {
        return ['status' => BusinessStatus::class];
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function services(): HasMany
    {
        return $this->hasMany(Service::class, 'category_id');
    }
}
