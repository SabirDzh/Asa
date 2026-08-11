function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing server environment variable: ${name}`);
  return value;
}

function positiveInt(name: string, fallback: number, max: number): number {
  const parsed = Number.parseInt(process.env[name] ?? '', 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.min(parsed, max);
}

export const env = {
  get databaseUrl(): string { return required('DATABASE_URL'); },
  get sessionSecret(): string {
    const value = required('SESSION_SECRET');
    if (value.length < 32) throw new Error('SESSION_SECRET must be at least 32 characters');
    return value;
  },
  get rateLimitSalt(): string {
    const value = required('RATE_LIMIT_SALT');
    if (value.length < 32) throw new Error('RATE_LIMIT_SALT must be at least 32 characters');
    return value;
  },
  get adminUsers(): Record<string, string> {
    const raw = required('ADMIN_USERS_JSON');
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new Error('ADMIN_USERS_JSON must be valid JSON');
    }
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('ADMIN_USERS_JSON must be an object');
    }
    const users: Record<string, string> = {};
    for (const [username, hash] of Object.entries(parsed)) {
      if (!/^[A-Za-z0-9._-]{1,64}$/.test(username) || typeof hash !== 'string') {
        throw new Error('ADMIN_USERS_JSON contains an invalid user');
      }
      users[username] = hash;
    }
    if (Object.keys(users).length === 0 || Object.keys(users).length > 10) {
      throw new Error('ADMIN_USERS_JSON must contain 1 to 10 users');
    }
    return users;
  },
  get retentionDays(): number { return positiveInt('REPORT_RETENTION_DAYS', 30, 3650); },
  get maxReportsPerInstallationPerHour(): number {
    return positiveInt('MAX_REPORTS_PER_INSTALLATION_PER_HOUR', 10, 1000);
  },
  get maxReportsPerIpPerHour(): number {
    return positiveInt('MAX_REPORTS_PER_IP_PER_HOUR', 50, 5000);
  },
};
