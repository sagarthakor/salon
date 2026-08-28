<?php

namespace App\Enums;

/**
 * Who a service/category is for — the master catalog's top-level grouping
 * (see MASTER_CATALOG_ARCHITECTURE.md) and the customer app's entry point
 * ("Men" / "Women" / "Unisex" / "Kids"). Deliberately its own enum, not a
 * reuse of `GenderType` (Salon's served-gender classification) or
 * `CustomerGender`/`StaffGender` (personal gender fields) — this project's
 * existing convention is one small enum per concept, never one shared
 * "gender" enum forced across unrelated entities. New audiences can be
 * added here without any other code change, since every consumer (seeder,
 * provisioning, filters, Resources) switches on this enum, never a raw
 * string.
 */
enum ServiceAudience: string
{
    case MALE = 'male';
    case FEMALE = 'female';
    case UNISEX = 'unisex';
    case KIDS = 'kids';

    public function label(): string
    {
        return match ($this) {
            self::MALE => 'Men',
            self::FEMALE => 'Women',
            self::UNISEX => 'Unisex',
            self::KIDS => 'Kids',
        };
    }
}
