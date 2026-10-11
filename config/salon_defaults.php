<?php

/*
 * Defaults applied to a salon/branch the first time it is provisioned, so a
 * customer can see bookable slots without the owner configuring every
 * dependency by hand. Applied only where nothing exists yet — never over an
 * owner's own settings, hours or staff. See SALON_PROVISIONING.md.
 */
return [
    // Keys of `SalonSettingKey`. Only missing keys are inserted.
    'settings' => [
        'booking_enabled' => true,
        'customer_booking_enabled' => true,
        'slot_interval_minutes' => 30,
        'min_advance_booking_minutes' => 30,
        'max_advance_booking_days' => 30,
        'booking_buffer_minutes' => 0,
        'cancellation_window_minutes' => 120,
    ],

    // day_of_week follows Carbon (0 = Sunday). null = closed that day.
    'working_hours' => [
        0 => null,
        1 => ['09:00', '20:00'],
        2 => ['09:00', '20:00'],
        3 => ['09:00', '20:00'],
        4 => ['09:00', '20:00'],
        5 => ['09:00', '20:00'],
        6 => ['09:00', '20:00'],
    ],

    // Created only for a branch that has no staff at all. Clearly labelled so the
    // owner renames or replaces it; it has no login and no real contact details.
    'default_staff' => [
        'enabled' => true,
        'name' => 'Default Stylist',
        'email_domain' => 'staff.invalid',
        'break' => ['13:00', '14:00'],
    ],
];
