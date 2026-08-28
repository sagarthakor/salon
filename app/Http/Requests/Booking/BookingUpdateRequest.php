<?php

namespace App\Http\Requests\Booking;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class BookingUpdateRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'status' => ['nullable', Rule::in(['checked_in', 'in_service', 'completed', 'no_show'])],
            'notes' => ['nullable', 'string', 'max:2000'],
        ];
    }
}
