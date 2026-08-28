<?php

namespace App\Http\Requests\Reports;

use App\Http\Requests\Reports\Concerns\HasReportFilterRules;
use Illuminate\Foundation\Http\FormRequest;

class StaffReportRequest extends FormRequest
{
    use HasReportFilterRules;

    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            ...$this->dateRangeRules(),
            ...$this->branchFilterRule(),
            ...$this->staffFilterRule(),
            ...$this->paginationRules(),
            ...$this->sortRules(['staff_name', 'assigned_bookings', 'completed_bookings', 'net_revenue', 'completion_rate', 'utilization_percent']),
        ];
    }
}
