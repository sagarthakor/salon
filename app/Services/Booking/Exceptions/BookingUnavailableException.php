<?php

namespace App\Services\Booking\Exceptions;

use RuntimeException;

class BookingUnavailableException extends RuntimeException
{
    /**
     * @param  array<string, list<string>>  $errors
     */
    public function __construct(string $message, private readonly array $errors = [])
    {
        parent::__construct($message);
    }

    /**
     * @return array<string, list<string>>
     */
    public function errors(): array
    {
        return $this->errors !== [] ? $this->errors : ['booking' => [$this->getMessage()]];
    }
}
