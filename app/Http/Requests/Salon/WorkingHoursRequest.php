<?php

namespace App\Http\Requests\Salon;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

class WorkingHoursRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return ['hours' => ['required', 'array', 'min:1', 'max:7'], 'hours.*.day_of_week' => ['required', 'integer', 'between:0,6', 'distinct'], 'hours.*.is_open' => ['required', 'boolean'], 'hours.*.opening_time' => ['nullable', 'date_format:H:i'], 'hours.*.closing_time' => ['nullable', 'date_format:H:i']];
    }

    public function after(): array
    {
        return [function (Validator $validator): void {
            foreach ($this->input('hours', []) as $index => $hour) {
                $open = filter_var($hour['is_open'] ?? false, FILTER_VALIDATE_BOOLEAN);
                $opening = $hour['opening_time'] ?? null;
                $closing = $hour['closing_time'] ?? null;
                if ($open && (! $opening || ! $closing)) {
                    $validator->errors()->add("hours.$index.opening_time", 'Open days require opening and closing times.');
                } if (! $open && ($opening || $closing)) {
                    $validator->errors()->add("hours.$index.opening_time", 'Closed days cannot include working times.');
                } if ($open && $opening && $closing && $opening >= $closing) {
                    $validator->errors()->add("hours.$index.closing_time", 'Closing time must be after opening time.');
                }
            }
        }];
    }
}
