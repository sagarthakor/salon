<?php

namespace App\Enums;

enum SalonMediaSource: string
{
    /** Added via the Instagram API sync or a pasted Instagram link — no hosted file unless the owner attaches one. */
    case INSTAGRAM = 'instagram';
    /** Original file uploaded by the owner. */
    case UPLOAD = 'upload';
}
