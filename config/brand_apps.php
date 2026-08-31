<?php

// Maps a branded single-salon Flutter app's slug (sent as the `X-App-Brand`
// request header) to the one tenant it is allowed to reach. Every
// customer-facing endpoint that resolves a tenant from a client-supplied
// branch/salon/booking id checks this via App\Support\BrandAppGuard right
// after resolving that tenant. A request with no `X-App-Brand` header (every
// existing client — the multi-tenant customer app, owner app, staff app) is
// completely unaffected: the guard is opt-in per request, not a global
// restriction. Adding a future branded app is one new entry here.
return [
    'nil_hair_port' => '01m16303p8xgzejrr9ezvtvwfv',
];
