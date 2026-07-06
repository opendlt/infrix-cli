#!/usr/bin/env node
// npx @infrix/cli — downloads the prebuilt `infrix` binary matching this
// package's version + your platform, verifies its SHA-256 against the signed
// checksums file, caches it under ~/.infrix/bin/<version>, and execs it.
//
// The package version pins the CLI version: `npx @infrix/cli@0.1.0` runs infrix v0.1.0.
'use strict';

const https = require('https');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const REPO = 'opendlt/infrix-cli';
const VERSION = require('./package.json').version; // e.g. 0.1.0
const TAG = 'v' + VERSION;

// Pass-17 audit P0-1: the checksums file must itself be AUTHENTICATED, not merely
// downloaded from the same endpoint as the payload. This is the PINNED Ed25519
// release public key (docs/release custody `RELEASE-SIGNING-KEY.pub`, fingerprint
// d5c3c240…). It is embedded here — never fetched from the release endpoint —
// so a compromised endpoint that swaps both the payload AND the checksums cannot
// also forge a valid signature. Verification is mandatory and fail-closed.
const PINNED_ED25519_PUBKEY_B64 = 'KayNyxm3HuYpCkyi24G2rWXWiXJji0KktABtI2gDui8=';

// pinnedPublicKey builds a Node KeyObject from the raw 32-byte Ed25519 key by
// wrapping it in a DER SubjectPublicKeyInfo (fixed Ed25519 prefix + raw key).
function pinnedPublicKey() {
  const raw = Buffer.from(PINNED_ED25519_PUBKEY_B64, 'base64');
  if (raw.length !== 32) throw new Error('pinned release key is not a 32-byte Ed25519 key');
  const spki = Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), raw]);
  return crypto.createPublicKey({ key: spki, format: 'der', type: 'spki' });
}

// verifyChecksumSignature fails closed unless the detached Ed25519 signature over
// the checksums bytes verifies against the pinned release key.
function verifyChecksumSignature(sumsBuf, sigBuf) {
  if (!sigBuf || sigBuf.length === 0) {
    throw new Error('checksums signature (.ed25519.sig) is missing — refusing to trust an unsigned checksums file');
  }
  // The detached signature ships base64-encoded (see the dist VERIFY.md). Decode
  // to the raw 64-byte Ed25519 signature before verifying.
  const rawSig = Buffer.from(sigBuf.toString('utf8').trim(), 'base64');
  if (rawSig.length !== 64) {
    throw new Error(`checksums signature is not a 64-byte Ed25519 signature (got ${rawSig.length} bytes) — refusing to install`);
  }
  const ok = crypto.verify(null, sumsBuf, pinnedPublicKey(), rawSig);
  if (!ok) {
    throw new Error('checksums signature does NOT verify against the pinned release key — refusing to install (possible tampered release endpoint)');
  }
}

function target() {
  const osMap = { win32: 'windows', darwin: 'darwin', linux: 'linux' };
  const archMap = { x64: 'amd64', arm64: 'arm64' };
  const o = osMap[process.platform];
  const a = archMap[process.arch];
  if (!o || !a) {
    console.error(`@infrix/cli: unsupported platform ${process.platform}/${process.arch}`);
    process.exit(1);
  }
  const ext = o === 'windows' ? '.exe' : '';
  return { asset: `infrix_${VERSION}_${o}_${a}${ext}`, ext };
}

function get(url) {
  // GET with redirect-following, resolves to a Buffer.
  return new Promise((resolve, reject) => {
    const go = (u, n) => {
      if (n > 6) return reject(new Error('too many redirects'));
      https.get(u, { headers: { 'User-Agent': '@infrix/cli' } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          res.resume();
          return go(res.headers.location, n + 1);
        }
        if (res.statusCode !== 200) {
          res.resume();
          return reject(new Error(`HTTP ${res.statusCode} for ${u}`));
        }
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve(Buffer.concat(chunks)));
      }).on('error', reject);
    };
    go(url, 0);
  });
}

async function ensureBinary() {
  const { asset, ext } = target();
  const dir = path.join(os.homedir(), '.infrix', 'bin', VERSION);
  const bin = path.join(dir, 'infrix' + ext);
  if (fs.existsSync(bin)) return bin;

  const base = `https://github.com/${REPO}/releases/download/${TAG}`;
  process.stderr.write(`@infrix/cli: fetching ${asset} (${TAG})\n`);
  const [data, sumsBuf, sigBuf] = await Promise.all([
    get(`${base}/${asset}`),
    get(`${base}/infrix_${VERSION}_checksums.txt`),
    get(`${base}/infrix_${VERSION}_checksums.txt.ed25519.sig`).catch(() => Buffer.alloc(0)),
  ]);

  // Pass-17 audit P0-1: authenticate the checksums file with the pinned release
  // key BEFORE trusting any hash inside it. Fail closed on a missing or invalid
  // signature — a compromised endpoint that swaps both payload and checksums
  // cannot also forge a signature under the embedded release key.
  verifyChecksumSignature(sumsBuf, sigBuf);
  process.stderr.write('@infrix/cli: checksums signature verified against the pinned release key\n');

  const sums = sumsBuf.toString('utf8');
  const line = sums.split('\n').find((l) => l.trim().endsWith(' ' + asset) || l.trim().endsWith('*' + asset));
  if (!line) throw new Error(`no checksum entry for ${asset}`);
  const want = line.trim().split(/\s+/)[0].toLowerCase();
  const got = crypto.createHash('sha256').update(data).digest('hex');
  if (want !== got) throw new Error(`checksum mismatch (expected ${want}, got ${got}) — refusing to run`);

  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(bin, data, { mode: 0o755 });
  return bin;
}

// Export the authentication primitives so a test can prove they fail closed on a
// tampered/unsigned checksums file without any network I/O (pass-17 audit P0-1).
module.exports = { verifyChecksumSignature, pinnedPublicKey, PINNED_ED25519_PUBKEY_B64 };

// Only auto-download-and-exec when run directly (npx), not when required by a test.
if (require.main === module) {
ensureBinary()
  .then((bin) => {
    const r = spawnSync(bin, process.argv.slice(2), { stdio: 'inherit' });
    process.exit(r.status === null ? 1 : r.status);
  })
  .catch((e) => {
    console.error('@infrix/cli: ' + e.message);
    process.exit(1);
  });
}
