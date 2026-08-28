<?php

namespace App\Http\Requests\Reports;

use App\Http\Requests\Reports\Concerns\HasReportFilterRules;
use Illuminate\Foundation\Http\FormRequest;

class RevenueReportRequest extends FormRequest
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
            ...$this->serviceFilterRule(),
            ...$this->categoryFilterRule(),
            ...$this->groupByRule(),
        ];
    }
}
