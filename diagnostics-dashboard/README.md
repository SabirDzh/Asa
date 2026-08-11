# ASA diagnostics dashboard

Private Vercel dashboard and serverless API for user-initiated ASA diagnostic reports.

## Architecture

- Flutter sends only a redacted, bounded report to `POST /api/reports`.
- Vercel Route Handlers validate the payload and store it in Neon Postgres.
- Admins sign in at `/login`; reports are visible at `/dashboard`.
- No database, admin, or Telegram secret is shipped in the APK.
- The API never receives tasks, descriptions, attachments, backups, sync secrets, or clipboard data.

## Local setup

```bash
npm install
cp .env.example .env.local
# Fill .env.local with server-only values.
npm run hash-password -- 'use-a-long-local-password'
# Put the resulting hash in ADMIN_USERS_JSON, for example:
# {"admin":"scrypt$..."}
# Apply db/schema.sql to Neon, then:
npm run dev
```

## Vercel setup

1. Import this repository into Vercel and set the project root to `diagnostics-dashboard`.
2. Create a Neon project and apply [`db/schema.sql`](db/schema.sql).
3. Add every variable from `.env.example` to Vercel Production Environment Variables.
4. Generate independent random values for `SESSION_SECRET` and `RATE_LIMIT_SALT`.
5. Use a long unique admin password; do not reuse the GitHub, email, or keystore password.
6. Deploy and open `/login` to verify the private dashboard.
7. Put the public report URL in the local Flutter config (not in Vercel secrets):

```bash
cp ../config/private.env.example ../config/private.env
# Edit the URL, then protect the file:
chmod 600 ../config/private.env
```

Build with `../scripts/build.sh --split` or `../scripts/release.sh <version> <build>`. These scripts validate the owner-only file and automatically pass the endpoint to Flutter; no manual `--dart-define=DIAGNOSTICS_ENDPOINT` argument is needed. Direct `flutter build` commands intentionally do not read files from the host and therefore keep diagnostics disabled unless a build script supplies the endpoint.

The endpoint is public client configuration, not a secret. Do not put a bearer token, Neon URL, session secret, or admin credential in `config/private.env` or in the Flutter build. The public report endpoint is protected by strict validation, size limits, database-backed rate limits, and retention; additionally enable Vercel WAF/rate limiting for the production domain when available. The dashboard and report-management APIs require the signed admin session.

## Operations

- Reports are retained for `REPORT_RETENTION_DAYS` (default 30 days).
- Expired reports are deleted opportunistically on report ingestion and dashboard reads.
- Delete individual reports from the dashboard when no longer needed.
- Rotate `SESSION_SECRET`, `RATE_LIMIT_SALT`, and the admin password if exposed.
- Keep Neon backups and Vercel logs access-controlled; do not log report payloads in server output.
- Review Vercel and Neon data-region settings before publishing the privacy policy.
- Treat submitted reports as potentially sensitive despite client redaction.

## API contract

`POST /api/reports` accepts JSON with `installationId`, `appVersion`, `platform`, `deviceName`, `sentAt`, and `logs`. It returns `201 {"reportId":"..."}` on success. The client must retry only after a timeout or 5xx; the server does not accept report uploads without a valid HTTPS client contract.
