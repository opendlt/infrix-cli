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
  const [data, sums] = await Promise.all([
    get(`${base}/${asset}`),
    get(`${base}/infrix_${VERSION}_checksums.txt`).then((b) => b.toString('utf8')),
  ]);

  const line = sums.split('\n').find((l) => l.trim().endsWith(' ' + asset) || l.trim().endsWith('*' + asset));
  if (!line) throw new Error(`no checksum entry for ${asset}`);
  const want = line.trim().split(/\s+/)[0].toLowerCase();
  const got = crypto.createHash('sha256').update(data).digest('hex');
  if (want !== got) throw new Error(`checksum mismatch (expected ${want}, got ${got}) — refusing to run`);

  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(bin, data, { mode: 0o755 });
  return bin;
}

ensureBinary()
  .then((bin) => {
    const r = spawnSync(bin, process.argv.slice(2), { stdio: 'inherit' });
    process.exit(r.status === null ? 1 : r.status);
  })
  .catch((e) => {
    console.error('@infrix/cli: ' + e.message);
    process.exit(1);
  });
