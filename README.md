# infrix-cli

**Prebuilt binaries for the [Infrix](https://github.com/opendlt) CLI.**

Infrix is a policy-governed, identity-native execution fabric on Accumulate.
Infrix is **open-core**: the governance runtime/node source is private; this repo
ships the **compiled `infrix` CLI** for every platform, with checksums and
signatures so you can trust what you run.

## Install

**macOS / Linux**

```sh
curl -fsSL https://raw.githubusercontent.com/opendlt/infrix-cli/main/install.sh | sh
```

**Windows (PowerShell)**

```powershell
iwr -useb https://raw.githubusercontent.com/opendlt/infrix-cli/main/install.ps1 | iex
```

**Node users (no global install)**

```sh
npx @infrix/cli version
```

Then:

```sh
infrix version
infrix doctor      # checks your toolchain, the L0 endpoint, and proof tooling
```

Pin a version with `INFRIX_VERSION=v0.1.0` (env) before the install command, or
`npx @infrix/cli@0.1.0`.

## Manual download

Grab the archive for your platform from the [latest release](https://github.com/opendlt/infrix-cli/releases/latest),
verify it against `infrix_<version>_checksums.txt`, and put `infrix` on your PATH.
Targets: `linux_amd64`, `linux_arm64`, `darwin_amd64`, `darwin_arm64`, `windows_amd64`.

## Verifying downloads

Every release includes `infrix_<version>_checksums.txt` (SHA-256) and a detached
**Ed25519 signature** over that checksums file
(`infrix_<version>_checksums.txt.ed25519.sig`, base64), plus the release public
key `RELEASE-SIGNING-KEY.pub` (`ed25519 <base64>`, fingerprint `d5c3c240…`).

The one-line installers (`install.sh`, `install.ps1`) and the `npx @infrix/cli`
wrapper now **authenticate the checksums file automatically**: they download the
signature and verify it against a release public key **pinned inside the
installer** (never fetched from the release endpoint) BEFORE trusting any hash in
the checksums file, then verify the payload's SHA-256. Any of a missing,
malformed, or invalid signature — or a checksum mismatch — makes every installer
**refuse to install**. So a compromised endpoint that swaps both the payload and
the checksums cannot forge a valid signature under the pinned key. The Windows
`install.ps1` verifies the Ed25519 signature with a **native pure-PowerShell
verifier** (RFC 8032, `System.Numerics.BigInteger` + built-in SHA-512), so it is
**dependency-free on a clean Windows host** — no OpenSSL required (pass-18 P2-4).

To verify the checksums-file signature yourself (matches
`infrix-core/scripts/verify-release-evidence.sh`, and the dist `VERIFY.md`):

```sh
# Rebuild a PEM SubjectPublicKeyInfo for the raw Ed25519 key, decode the
# base64 signature, then verify with OpenSSL 3.x.
key=$(awk '{print $2}' RELEASE-SIGNING-KEY.pub)
printf -- '-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA%s\n-----END PUBLIC KEY-----\n' "$key" > relkey.pem
openssl base64 -d -in infrix_<version>_checksums.txt.ed25519.sig -out sig.bin
openssl pkeyutl -verify -pubin -inkey relkey.pem -rawin \
  -in infrix_<version>_checksums.txt -sigfile sig.bin
```

## No install needed to see the value

You can verify a **real** Infrix proof offline, against a server you don't have
to trust, with zero install of anything private:

```sh
npm i @infrix/verify
```

See the [30-second quickstart](https://github.com/opendlt/infrix-sdk-js#start-here-prove-it-to-yourself-in-30-seconds).

## How releases are produced

Binaries are cross-compiled (pure-Go, no CGO) and published from the private
core repo's release pipeline **only when the fail-closed certification gate is
green**. This repo holds the binaries, installers, and the `@infrix/cli` npm
launcher — never the runtime source.

## License

MIT — see [LICENSE](LICENSE).
