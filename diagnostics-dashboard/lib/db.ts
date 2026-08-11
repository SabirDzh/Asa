import { neon } from '@neondatabase/serverless';
import { env } from './env';

let client: ReturnType<typeof neon> | undefined;

export function sql() {
  client ??= neon(env.databaseUrl);
  return client;
}
