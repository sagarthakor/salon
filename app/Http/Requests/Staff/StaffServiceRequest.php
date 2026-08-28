<?php

namespace App\Http\Requests\Staff;

use App\Models\Service;
use App\Models\Staff;
use App\Support\TenantContext;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class StaffServiceRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $tenantId = app(TenantContext::class)->id();

        return [
            'service_ids' => ['present', 'array'],
            'service_ids.*' => ['distinct', Rule::exists('services', 'id')->where('tenant_id', $tenantId)],
        ];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            $staff = Staff::query()->find($this->route('staff'));
            if ($staff === null) {
                return;
            }
            $branchIds = $staff->branches()->pluck('branches.id')->all();
            if ($branchIds === []) {
                return;
            }
            $services = Service::query()->whereIn('id', $this->input('service_ids', []))->get(['id', 'branch_id']);
            foreach ($services as $service) {
                if (! in_array($service->branch_id, $branchIds, true)) {
                    $validator->errors()->add('service_ids', "Service {$service->id} does not belong to a branch this staff member is assigned to.");
                }
            }
        }];
    }
}
