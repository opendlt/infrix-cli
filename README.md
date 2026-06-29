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

Every release includes `infrix_<version>_checksums.txt` (SHA-256) and a
cosign signature (`.sig` + `.pem`). The installers verify the checksum
automatically and refuse to install on mismatch. To verify the checksums file
signature yourself:

```sh
cosign verify-blob \
  --certificate infrix_<version>_checksums.txt.pem \
  --signature  infrix_<version>_checksums.txt.sig \
  --certificate-identity-regexp 'github.com/opendlt' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  infrix_<version>_checksums.txt
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
