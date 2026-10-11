<?php

namespace App\Services\Catalog;

use App\Enums\BusinessStatus;
use App\Enums\StaffGender;
use App\Models\Branch;
use App\Models\Salon;
use App\Models\SalonSetting;
use App\Models\Service;
use App\Models\Staff;
use Illuminate\Support\Facades\DB;

/**
 * Makes a branch bookable out of the box: default booking settings, weekly
 * hours, and one default staff member assigned to the branch's services with
 * matching weekly hours and a lunch break. Slots themselves are never stored;
 * AvailabilityService derives them from these rows.
 *
 * Strictly additive and idempotent — every step only fills what is missing,
 * so it never overwrites an owner's settings, hours, staff or assignments, and
 * it only ever touches the branch/tenant it is given (the tenant context must
 * already be set by the caller). See SALON_PROVISIONING.md.
 */
class BranchDefaultsService
{
    /**
     * @return array{settings:int, working_hours:int, staff_created:bool, services_assigned:int}
     */
    public function apply(Branch $branch): array
    {
        return DB::transaction(function () use ($branch): array {
            $report = ['settings' => 0, 'working_hours' => 0, 'staff_created' => false, 'services_assigned' => 0];
            $report['settings'] = $this->settings($branch->salon);
            $report['working_hours'] = $this->branchHours($branch);
            if (config('salon_defaults.default_staff.enabled')) {
                [$report['staff_created'], $report['services_assigned']] = $this->defaultStaff($branch);
            }

            return $report;
        });
    }

    private function settings(Salon $salon): int
    {
        $created = 0;
        foreach (config('salon_defaults.settings') as $key => $value) {
            $setting = SalonSetting::query()->firstOrCreate(['salon_id' => $salon->id, 'key' => $key], ['value' => $value]);
            $created += $setting->wasRecentlyCreated ? 1 : 0;
        }

        return $created;
    }

    private function branchHours(Branch $branch): int
    {
        $created = 0;
        foreach (config('salon_defaults.working_hours') as $day => $hours) {
            $row = $branch->workingHours()->firstOrCreate(['day_of_week' => $day], [
                'is_open' => $hours !== null,
                'opening_time' => $hours[0] ?? null,
                'closing_time' => $hours[1] ?? null,
            ]);
            $created += $row->wasRecentlyCreated ? 1 : 0;
        }

        return $created;
    }

    /**
     * @return array{0: bool, 1: int}
     */
    private function defaultStaff(Branch $branch): array
    {
        $config = config('salon_defaults.default_staff');
        $email = "default-stylist-{$branch->id}@{$config['email_domain']}";
        $staff = Staff::query()->where('email', $email)->first();
        $created = false;
        // Only for a branch nobody works at yet — an owner who has added (or removed) staff is left alone.
        if ($staff === null) {
            if ($branch->staff()->exists()) {
                return [false, 0];
            }
            $staff = Staff::query()->create([
                'name' => $config['name'], 'email' => $email, 'gender' => StaffGender::OTHER,
                'bio' => 'Default team member created with the salon. Rename or replace in Staff.',
                'status' => BusinessStatus::ACTIVE,
            ]);
            $staff->branches()->attach($branch->id, ['tenant_id' => $branch->tenant_id]);
            $created = true;
            $this->staffHours($staff);
        }

        // Services only on first creation, or if the default staff has none yet (never re-adds ones the owner removed).
        $assigned = 0;
        if ($created || $staff->services()->doesntExist()) {
            $ids = Service::query()->where('branch_id', $branch->id)->where('status', BusinessStatus::ACTIVE)->pluck('id')->all();
            $staff->services()->syncWithoutDetaching(array_fill_keys($ids, ['tenant_id' => $branch->tenant_id]));
            $assigned = count($ids);
        }

        return [$created, $assigned];
    }

    private function staffHours(Staff $staff): void
    {
        [$breakStart, $breakEnd] = config('salon_defaults.default_staff.break');
        foreach (config('salon_defaults.working_hours') as $day => $hours) {
            $staff->workingHours()->firstOrCreate(['day_of_week' => $day], [
                'is_working' => $hours !== null, 'start_time' => $hours[0] ?? null, 'end_time' => $hours[1] ?? null,
            ]);
            if ($hours !== null) {
                $staff->breaks()->firstOrCreate(['day_of_week' => $day], ['start_time' => $breakStart, 'end_time' => $breakEnd]);
            }
        }
    }
}
