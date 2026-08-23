# Deployment

Set production environment variables from a secret manager; never commit `.env`. Configure MySQL, Redis-compatible cache/queue drivers when enabled, a web worker, queue workers, the scheduler, TLS, backups, and centralized logs. Run `php artisan migrate --force` during deployment. Replace the local demo seeder credentials before any non-local deployment.
