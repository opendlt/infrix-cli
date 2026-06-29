# @infrix/cli

`npx` launcher for the [Infrix](https://github.com/opendlt) CLI.

```sh
npx @infrix/cli version
npx @infrix/cli doctor
```

On first run it downloads the prebuilt `infrix` binary matching your platform
from [`opendlt/infrix-cli`](https://github.com/opendlt/infrix-cli/releases),
**verifies its SHA-256** against the release checksums, caches it under
`~/.infrix/bin/<version>`, and runs it. The package version pins the CLI version
(`npx @infrix/cli@0.1.0` runs `infrix` v0.1.0).

Infrix is open-core: this launcher and the binaries are public; the runtime
source is private.

## No install needed to see the value

```sh
npm i @infrix/verify   # verify a real proof offline, no node, no trust
```

## License

MIT
