import { createHmac, scryptSync, timingSafeEqual } from 'node:crypto';

type Session = { username: string; expiresAt: number };

function base64Url(value: Buffer): string {
  return value.toString('base64url');
}

function decodeBase64Url(value: string): Buffer {
  return Buffer.from(value, 'base64url');
}

function sign(value: string, secret: string): string {
  return base64Url(createHmac('sha256', secret).update(value).digest());
}

export function verifyScryptPassword(password: string, encoded: string): boolean {
  const parts = encoded.split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
  const [, rawN, rawR, rawP, rawSalt, rawExpected] = parts;
  const N = Number(rawN);
  const r = Number(rawR);
  const p = Number(rawP);
  if (!Number.isInteger(N) || !Number.isInteger(r) || !Number.isInteger(p)) return false;
  if (N < 16384 || N > 32768 || r < 1 || r > 16 || p < 1 || p > 4) return false;
  try {
    const expected = decodeBase64Url(rawExpected);
    const actual = scryptSync(password, decodeBase64Url(rawSalt), expected.length, {
      N,
      r,
      p,
      maxmem: 64 * 1024 * 1024,
    });
    return expected.length === actual.length && timingSafeEqual(expected, actual);
  } catch {
    return false;
  }
}

export function createSignedSession(
  username: string,
  secret: string,
  ttlSeconds = 60 * 60 * 8,
  nowSeconds = Math.floor(Date.now() / 1000),
): string {
  const payload: Session = { username, expiresAt: nowSeconds + ttlSeconds };
  const encoded = base64Url(Buffer.from(JSON.stringify(payload), 'utf8'));
  return `${encoded}.${sign(encoded, secret)}`;
}

export function parseSignedSession(
  value: string | undefined,
  secret: string,
  users: Record<string, string>,
  nowSeconds = Math.floor(Date.now() / 1000),
): { username: string; expiresAt: number } | null {
  if (!value) return null;
  const [encoded, signature] = value.split('.');
  if (!encoded || !signature) return null;
  const expected = sign(encoded, secret);
  const left = Buffer.from(signature);
  const right = Buffer.from(expected);
  if (left.length !== right.length || !timingSafeEqual(left, right)) return null;
  try {
    const session = JSON.parse(decodeBase64Url(encoded).toString('utf8')) as Partial<Session>;
    if (
      typeof session.username !== 'string' ||
      !Object.prototype.hasOwnProperty.call(users, session.username) ||
      typeof session.expiresAt !== 'number' ||
      session.expiresAt <= nowSeconds
    ) return null;
    return { username: session.username, expiresAt: session.expiresAt };
  } catch {
    return null;
  }
}
