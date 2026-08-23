<?php

namespace App\Models\Concerns;

use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use LogicException;

trait BelongsToTenant
{
    public static function bootBelongsToTenant(): void
    {
        static::addGlobalScope('tenant', function (Builder $builder): void {
            $tenantId = app(TenantContext::class)->id();
            if ($tenantId === null) {
                $builder->whereRaw('1 = 0');

                return;
            }

            $builder->where($builder->getModel()->qualifyColumn('tenant_id'), $tenantId);
        });
        static::creating(function (Model $model): void {
            $tenantId = app(TenantContext::class)->id();
            if ($tenantId === null) {
                throw new LogicException('Cannot create a tenant-owned record without a tenant context.');
            } $model->setAttribute('tenant_id', $tenantId);
        });
    }
}
