<?php

namespace App\Http\Requests\Staff;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

class StaffWorkingHoursRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return ['hours' => ['required', 'array', 'min:1', 'max:7'], 'hours.*.day_of_week' => ['required', 'integer', 'between:0,6', 'distinct'], 'hours.*.is_working' => ['required', 'boolean'], 'hours.*.start_time' => ['nullable', 'date_format:H:i'], 'hours.*.end_time' => ['nullable', 'date_format:H:i']];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            foreach ($this->input('hours', []) as $index => $hour) {
                $working = filter_var($hour['is_working'] ?? false, FILTER_VALIDATE_BOOLEAN);
                $start = $hour['start_time'] ?? null;
                $end = $hour['end_time'] ?? null;
                if ($working && (! $start || ! $end)) {
                    $validator->errors()->add("hours.$index.start_time", 'Working days require a start and end time.');
                } if (! $working && ($start || $end)) {
                    $validator->errors()->add("hours.$index.start_time", 'Off days cannot include working times.');
                } if ($working && $start && $end && $start >= $end) {
                    $validator->errors()->add("hours.$index.end_time", 'End time must be after start time.');
                }
            }
        }];
    }
}
