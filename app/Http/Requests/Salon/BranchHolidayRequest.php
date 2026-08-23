<?php

namespace App\Http\Requests\Salon;

use App\Models\Branch;
use App\Models\BranchHoliday;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class BranchHolidayRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $branch = Branch::query()->find($this->route('branch'));
        $holiday = BranchHoliday::query()->find($this->route('holiday'));

        return ['holiday_date' => ['required', 'date_format:Y-m-d', Rule::unique('branch_holidays', 'holiday_date')->where('branch_id', $branch?->id)->ignore($holiday?->id)], 'name' => ['required', 'string', 'max:150'], 'is_closed' => ['nullable', 'boolean']];
    }
}
