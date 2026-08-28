<?php

namespace App\Http\Requests\Staff;

use App\Models\Staff;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

class StaffBreakRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return ['day_of_week' => ['required', 'integer', 'between:0,6'], 'start_time' => ['required', 'date_format:H:i'], 'end_time' => ['required', 'date_format:H:i', 'after:start_time']];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            $staff = Staff::query()->find($this->route('staff'));
            if ($staff === null) {
                return;
            }
            $day = $this->input('day_of_week');
            $start = $this->input('start_time');
            $end = $this->input('end_time');
            if ($day === null || ! $start || ! $end) {
                return;
            }
            $workingHour = $staff->workingHours()->where('day_of_week', $day)->first();
            if ($workingHour === null || ! $workingHour->is_working) {
                $validator->errors()->add('day_of_week', 'A break cannot be scheduled on a day the staff member is not working.');
            } elseif ($start < substr((string) $workingHour->start_time, 0, 5) || $end > substr((string) $workingHour->end_time, 0, 5)) {
                $validator->errors()->add('start_time', 'The break must fall within the staff member\'s working hours for that day.');
            }
            $overlaps = $staff->breaks()
                ->where('day_of_week', $day)
                ->when($this->route('break'), fn ($query, $breakId) => $query->whereKeyNot($breakId))
                ->where('start_time', '<', $end)
                ->where('end_time', '>', $start)
                ->exists();
            if ($overlaps) {
                $validator->errors()->add('start_time', 'This break overlaps with an existing break.');
            }
        }];
    }
}
