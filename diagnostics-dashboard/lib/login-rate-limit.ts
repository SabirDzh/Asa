import { hashRateLimitIdentifier } from './security';
import { sql } from './db';
import { env } from './env';

export async function isLoginRateLimited(identifier: string): Promise<boolean> {
  const key = hashRateLimitIdentifier(identifier);
  const rows = await sql()`
    select count(*) as count
    from auth_login_attempts
    where identifier_hash = ${key}
      and attempted_at > now() - interval '15 minutes'
  ` as unknown as Array<{ count: string | number }>;
  return Number(rows[0]?.count ?? 0) >=
    Math.min(Number.parseInt(process.env.MAX_LOGIN_ATTEMPTS_PER_IP_15M ?? '', 10) || 10, 100);
}

export async function recordFailedLogin(identifier: string): Promise<void> {
  await sql()`
    insert into auth_login_attempts (identifier_hash) values (${hashRateLimitIdentifier(identifier)})
  `;
}
