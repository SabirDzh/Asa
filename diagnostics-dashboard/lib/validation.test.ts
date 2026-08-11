import assert from 'node:assert/strict';
import test from 'node:test';
import { parseDiagnosticPayload } from './validation.ts';

test('accepts a valid bounded report', () => {
  const parsed = parseDiagnosticPayload({
    installationId: 'installation-123',
    appVersion: '1.1.3',
    platform: 'android',
    deviceName: 'Pixel 9',
    sentAt: new Date().toISOString(),
    logs: ['[E] error'],
  });
  assert.equal(parsed?.logs.length, 1);
});

test('rejects malformed and oversized report fields', () => {
  assert.equal(parseDiagnosticPayload({ logs: ['x'] }), null);
  assert.equal(parseDiagnosticPayload({
    installationId: 'installation-123',
    appVersion: '1.1.3',
    platform: 'android',
    deviceName: 'Pixel 9',
    sentAt: new Date().toISOString(),
    logs: ['x'.repeat(8193)],
  }), null);
});
