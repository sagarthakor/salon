# Flutter Architecture

Flutter is not installed and no Flutter project exists in Phase 1. A later single codebase should use feature modules (`auth`, `customer`, `salon`, `booking`, `owner`, `staff`), a network/repository layer, role-aware routing, and secure storage for Sanctum tokens. UI widgets must not call APIs directly. The Laravel API remains authoritative for price, tenancy, permissions, availability, and payment state.
