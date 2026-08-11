import { createHash, randomUUID } from 'node:crypto';
import { cookies, headers } from 'next/headers';
import { redirect } from 'next/navigation';
import { env } from './env';

const SESSION_COOKIE = 'asa_admin_session';
const SESSION_TTL_SECONDS = 60 * 60 * 8;

import {
  createSignedSession,
  parseSignedSession,
  verifyScryptPassword,
} from './security-core';

type Session = { username: string; expiresAt: number };

export function verifyPassword(password: string, encoded: string): boolean {
  return verifyScryptPassword(password, encoded);
}

export function createSession(username: string): string {
  return createSignedSession(username, env.sessionSecret);
}

export function parseSession(value: string | undefined): Session | null {
  return parseSignedSession(value, env.sessionSecret, env.adminUsers);
}

export async function currentSession(): Promise<Session | null> {
  const store = await cookies();
  return parseSession(store.get(SESSION_COOKIE)?.value);
}

export async function requireSession(): Promise<Session> {
  const session = await currentSession();
  if (!session) redirect('/login');
  return session;
}

export async function setSessionCookie(value: string): Promise<void> {
  const store = await cookies();
  store.set(SESSION_COOKIE, value, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    path: '/',
    maxAge: SESSION_TTL_SECONDS,
  });
}

export async function clearSessionCookie(): Promise<void> {
  const store = await cookies();
  store.set(SESSION_COOKIE, '', { httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'strict', path: '/', maxAge: 0 });
}

export async function requireSameOrigin(): Promise<boolean> {
  const requestHeaders = await headers();
  const host = requestHeaders.get('host');
  if (!host) return false;
  const forwardedProto = requestHeaders.get('x-forwarded-proto') ?? 'https';
  const expectedOrigin = `${forwardedProto}://${host}`;
  const origin = requestHeaders.get('origin');
  if (origin) return origin === expectedOrigin;
  const referer = requestHeaders.get('referer');
  if (!referer) return false;
  try {
    return new URL(referer).origin === expectedOrigin;
  } catch {
    return false;
  }
}

export function hashRateLimitIdentifier(value: string): string {
  return createHash('sha256').update(`${env.rateLimitSalt}:${value}`).digest('hex');
}

export function verifyAdminCredentials(username: string, password: string): boolean {
  const hash = env.adminUsers[username];
  return typeof hash === 'string' && verifyPassword(password, hash);
}

export function randomReportId(): string {
  return randomUUID();
}
