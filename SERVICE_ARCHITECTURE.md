# Service Architecture

Categories and services are tenant-owned, branch-specific records. This direct relationship is the simplest scalable choice because branches can independently set service price, duration, status, and future availability. Slugs are unique within each branch.

Prices use `decimal(12,2)` and duration is a positive integer of minutes. Images are optional Laravel public-disk uploads under `services/` or `service-categories/`, validated as JPEG, PNG, or WebP, at most 5 MB, with safe generated filenames.

Staff-service mapping is deferred to Phase 4: no staff table exists yet, so adding an FK now would create a broken schema. Future bookings must snapshot a service's name, price, and duration at confirmation.
