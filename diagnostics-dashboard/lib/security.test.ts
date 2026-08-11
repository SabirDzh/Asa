import assert from 'node:assert/strict';
import { randomBytes, scryptSync } from 'node:crypto';
import test from 'node:test';
import {
  createSignedSession,
  parseSignedSession,
  verifyScryptPassword,
} from './security-core.ts';

function hash(password: string): string {
  const salt = randomBytes(16);
  const derived = scryptSync(password, salt, 32, { N: 16384, r: 8, p: 1 });
  return `scrypt$16384$8$1$${salt.toString('base64url')}$${derived.toString('base64url')}`;
}

test('verifies valid scrypt password and rejects wrong password', () => {
  const encoded = hash('correct horse battery staple');
  assert.equal(verifyScryptPassword('correct horse battery staple', encoded), true);
  assert.equal(verifyScryptPassword('wrong password', encoded), false);
});

test('signed session parses and tampering or expiry is rejected', () => {
  const secret = 'session-secret-for-tests-12345678901234567890';
  const users = { admin: hash('password') };
  const token = createSignedSession('admin', secret, 100, 1000);
  assert.equal(parseSignedSession(token, secret, users, 105)?.username, 'admin');
  assert.equal(parseSignedSession(`${token}tampered`, secret, users, 105), null);
  assert.equal(parseSignedSession(token, secret, users, 1100), null);
});
