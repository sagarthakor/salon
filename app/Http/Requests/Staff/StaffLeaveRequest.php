<?php

namespace App\Http\Requests\Staff;

use App\Enums\LeaveStatus;
use App\Models\Staff;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class StaffLeaveRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return ['start_date' => ['required', 'date_format:Y-m-d'], 'end_date' => ['required', 'date_format:Y-m-d', 'after_or_equal:start_date'], 'reason' => ['nullable', 'string', 'max:1000'], 'status' => ['nullable', Rule::enum(LeaveStatus::class)]];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            $staff = Staff::query()->find($this->route('staff'));
            $start = $this->input('start_date');
            $end = $this->input('end_date');
            if ($staff === null || ! $start || ! $end) {
                return;
            }
            $overlaps = $staff->leaves()
                ->where('status', '!=', LeaveStatus::REJECTED->value)
                ->when($this->route('leave'), fn ($query, $leaveId) => $query->whereKeyNot($leaveId))
                ->where('start_date', '<=', $end)
                ->where('end_date', '>=', $start)
                ->exists();
            if ($overlaps) {
                $validator->errors()->add('start_date', 'This leave overlaps with an existing leave record.');
            }
        }];
    }
}
