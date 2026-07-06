// Pass-17 audit P0-1: prove the npx installer AUTHENTICATES the checksums file —
// it fails closed on a tampered, wrong-length, or missing signature, and accepts
// only a real signature over the exact checksums bytes under the pinned release
// key. No network I/O: uses the committed dist fixture.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const { verifyChecksumSignature } = require(path.join(here, '..', 'index.js'));

// Locate the committed distribution fixture (a sibling release-dist checkout).
function distDir() {
  const candidates = [
    path.resolve(here, '..', '..', '..', 'infrix-cli-dist-v0.1.1'),
    path.resolve(here, '..', '..', 'infrix-cli-dist-v0.1.1'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(path.join(c, 'infrix_0.1.1_checksums.txt'))) return c;
  }
  return null;
}

test('npx checksum-signature authentication fails closed on tamper/absence and passes on a valid signature', (t) => {
  const dist = distDir();
  if (!dist) {
    t.skip('release dist fixture not present next to the repo');
    return;
  }
  const sums = fs.readFileSync(path.join(dist, 'infrix_0.1.1_checksums.txt'));
  const sig = fs.readFileSync(path.join(dist, 'infrix_0.1.1_checksums.txt.ed25519.sig'));

  // 1. A real signature over the exact checksums bytes verifies.
  assert.doesNotThrow(() => verifyChecksumSignature(sums, sig), 'a valid signature must verify');

  // 2. Tampering the checksums file must fail closed.
  const tampered = Buffer.from(sums);
  tampered[0] ^= 0xff;
  assert.throws(() => verifyChecksumSignature(tampered, sig), /does NOT verify/, 'tampered checksums must be rejected');

  // 3. A missing/empty signature must fail closed (never trust an unsigned file).
  assert.throws(() => verifyChecksumSignature(sums, Buffer.alloc(0)), /missing/, 'a missing signature must be rejected');

  // 4. A wrong-length signature must fail closed.
  const shortSig = Buffer.from('YWJjZA==', 'utf8'); // base64 of 3 bytes
  assert.throws(() => verifyChecksumSignature(sums, shortSig), /64-byte/, 'a wrong-length signature must be rejected');
});
