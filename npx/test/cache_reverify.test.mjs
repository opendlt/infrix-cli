// Pass-18 audit P2-3: prove the npx wrapper RE-VERIFIES the cached binary on
// every invocation against the authenticated checksum persisted next to it.
// A cached binary whose hash no longer matches (tampering/corruption) — or one
// with no stored checksum — is not trusted, so it is deleted and redownloaded.
// No network I/O: exercises the pure cachedBinaryIsAuthentic predicate.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const { cachedBinaryIsAuthentic } = require(path.join(here, '..', 'index.js'));

test('cached binary re-verification: authentic passes, tampered/missing-checksum fail closed', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'infrix-npx-cache-'));
  try {
    const bin = path.join(dir, 'infrix');
    const sumPath = path.join(dir, 'infrix.sha256');
    const body = Buffer.from('fake-infrix-binary-payload');
    fs.writeFileSync(bin, body);
    const hash = crypto.createHash('sha256').update(body).digest('hex');
    fs.writeFileSync(sumPath, hash + '\n');

    // 1. Authentic cache (hash matches the stored authenticated checksum) → trusted.
    assert.equal(cachedBinaryIsAuthentic(bin, sumPath), true, 'a matching cached binary must be trusted');

    // 2. Tampered binary → NOT trusted (would trigger delete + redownload).
    fs.writeFileSync(bin, Buffer.concat([body, Buffer.from('!')]));
    assert.equal(cachedBinaryIsAuthentic(bin, sumPath), false, 'a tampered cached binary must fail re-verification');

    // 3. Restore binary but remove the stored checksum → cannot re-verify → NOT trusted.
    fs.writeFileSync(bin, body);
    fs.unlinkSync(sumPath);
    assert.equal(cachedBinaryIsAuthentic(bin, sumPath), false, 'a cache with no authenticated checksum must not be trusted');

    // 4. Missing binary → NOT trusted.
    fs.unlinkSync(bin);
    fs.writeFileSync(sumPath, hash + '\n');
    assert.equal(cachedBinaryIsAuthentic(bin, sumPath), false, 'a missing binary must not be trusted');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
