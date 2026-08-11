import { randomBytes, scryptSync } from 'node:crypto';

const password = process.argv[2];
if (!password || password.length < 12) {
  console.error('Usage: npm run hash-password -- "a-password-at-least-12-chars"');
  process.exit(1);
}

const cost = 16384;
const blockSize = 8;
const parallelization = 1;
const salt = randomBytes(16);
const derived = scryptSync(password, salt, 32, {
  N: cost,
  r: blockSize,
  p: parallelization,
  maxmem: 64 * 1024 * 1024,
});
console.log(
  `scrypt$${cost}$${blockSize}$${parallelization}$${salt.toString('base64url')}$${derived.toString('base64url')}`,
);
