<?php

namespace App\Enums;

enum SalonMediaCategory: string
{
    case HAIRCUT = 'haircut';
    case HAIR_COLOUR = 'hair_colour';
    case HIGHLIGHTS = 'highlights';
    case STYLING = 'styling';
    case TRANSFORMATION = 'transformation';
    case OTHER = 'other';

    public function label(): string
    {
        return match ($this) {
            self::HAIRCUT => 'Haircut',
            self::HAIR_COLOUR => 'Hair Colour',
            self::HIGHLIGHTS => 'Highlights',
            self::STYLING => 'Styling',
            self::TRANSFORMATION => 'Transformation',
            self::OTHER => 'Other',
        };
    }
}
