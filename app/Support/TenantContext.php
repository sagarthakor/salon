<?php

namespace App\Support;

use App\Models\Tenant;
use LogicException;

class TenantContext
{
    private ?Tenant $tenant = null;

    public function set(Tenant $tenant): void
    {
        $this->tenant = $tenant;
    }

    public function get(): ?Tenant
    {
        return $this->tenant;
    }

    public function id(): ?string
    {
        return $this->tenant?->getKey();
    }

    public function require(): Tenant
    {
        return $this->tenant ?? throw new LogicException('A tenant context is required.');
    }

    public function clear(): void
    {
        $this->tenant = null;
    }
}
