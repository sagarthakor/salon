<?php

namespace App\Models;

use App\Enums\TenantStatus;
use App\Services\Billing\SubscriptionService;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

class Tenant extends Model
{
    use HasUlids;

    protected $fillable = ['name', 'slug', 'status'];

    protected function casts(): array
    {
        return ['status' => TenantStatus::class];
    }

    protected static function booted(): void
    {
        // Every tenant — however it's created (registration flow, a test
        // fixture, a seeder) — starts a trial against the default active
        // plan the instant it exists. See SAAS_BILLING_ARCHITECTURE.md for
        // why this lives here rather than a controller: there is currently
        // no HTTP-driven "create a tenant" endpoint at all, so a model hook
        // is the one place that reliably covers every creation path.
        static::created(function (Tenant $tenant): void {
            app(SubscriptionService::class)->startTrialFor($tenant);
        });
    }

    public function users(): BelongsToMany
    {
        return $this->belongsToMany(User::class)->withPivot('role')->withTimestamps();
    }

    public function salon(): HasOne
    {
        return $this->hasOne(Salon::class);
    }

    public function branches(): HasMany
    {
        return $this->hasMany(Branch::class);
    }

    public function subscription(): HasOne
    {
        return $this->hasOne(Subscription::class);
    }
}
