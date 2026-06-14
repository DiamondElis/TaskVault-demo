import { webcrypto } from 'node:crypto';

// Node 16 (vuln-8 base) lacks global crypto.getRandomValues required by AWS SDK v3.
if (!globalThis.crypto?.getRandomValues) {
  Object.defineProperty(globalThis, 'crypto', {
    value: webcrypto,
    configurable: true,
  });
}
