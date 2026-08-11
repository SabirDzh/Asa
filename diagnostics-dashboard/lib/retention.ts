import { sql } from './db';
import { env } from './env';

export async function pruneExpiredReports(): Promise<void> {
  const cutoff = new Date(Date.now() - env.retentionDays * 24 * 60 * 60 * 1000);
  await sql()`
    delete from diagnostic_reports
    where received_at < ${cutoff}
       or deleted_at is not null
  `;
  await sql()`
    delete from auth_login_attempts
    where attempted_at < now() - interval '15 minutes'
  `;
}
