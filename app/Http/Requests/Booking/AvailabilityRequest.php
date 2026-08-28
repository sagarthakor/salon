<?php

namespace App\Http\Requests\Booking;

use App\Enums\BusinessStatus;
use App\Models\Branch;
use App\Models\Salon;
use App\Support\BookingSettings;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;
use Throwable;

class AvailabilityRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $branch = Branch::withoutGlobalScope('tenant')->find($this->route('branch'));
        $tenantId = $branch?->tenant_id;

        return [
            'date' => ['required', 'date_format:Y-m-d'],
            'service_ids' => ['required', 'array', 'min:1'],
            'service_ids.*' => ['distinct', Rule::exists('services', 'id')->where(fn ($q) => $q->where('tenant_id', $tenantId)->where('branch_id', $branch?->id)->where('status', BusinessStatus::ACTIVE->value))],
            'staff_id' => ['nullable', Rule::exists('staff_profiles', 'id')->where(fn ($q) => $q->where('tenant_id', $tenantId)->where('status', BusinessStatus::ACTIVE->value))],
        ];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            $branch = Branch::withoutGlobalScope('tenant')->find($this->route('branch'));
            if ($branch === null) {
                return;
            }
            if ($branch->status !== BusinessStatus::ACTIVE) {
                $validator->errors()->add('date', 'The branch is not active.');
            }

            $date = $this->input('date');
            if ($date) {
                $branchTz = $branch->timezone ?: 'UTC';
                $today = CarbonImmutable::now($branchTz)->startOfDay();
                try {
                    $target = CarbonImmutable::createFromFormat('Y-m-d', $date, $branchTz)->startOfDay();
                } catch (Throwable) {
                    $target = null;
                }
                if ($target !== null) {
                    if ($target->lt($today)) {
                        $validator->errors()->add('date', 'The date cannot be in the past.');
                    }
                    $salon = Salon::withoutGlobalScope('tenant')->with(['settings' => fn ($q) => $q->withoutGlobalScope('tenant')])->find($branch->salon_id);
                    $settings = new BookingSettings($salon);
                    if ($target->gt($today->addDays($settings->maxAdvanceDays()))) {
                        $validator->errors()->add('date', 'The date is beyond the maximum advance booking period.');
                    }
                }
            }

            $serviceIds = array_values(array_unique(array_filter((array) $this->input('service_ids', []))));
            $staffId = $this->input('staff_id');
            if ($staffId && $serviceIds !== []) {
                if (! DB::table('staff_branches')->where('staff_id', $staffId)->where('branch_id', $branch->id)->exists()) {
                    $validator->errors()->add('staff_id', 'The selected staff member is not assigned to this branch.');
                }
                $capableCount = DB::table('staff_services')->where('staff_id', $staffId)->whereIn('service_id', $serviceIds)->count();
                if ($capableCount !== count($serviceIds)) {
                    $validator->errors()->add('staff_id', 'The selected staff member cannot perform all requested services.');
                }
            }
        }];
    }
}
