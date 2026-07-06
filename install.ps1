# Infrix CLI installer for Windows (ADOPTION-03).
#
#   iwr -useb https://raw.githubusercontent.com/opendlt/infrix-cli/main/install.ps1 | iex
#
# Downloads the prebuilt infrix.exe, verifies its SHA-256 against the signed
# checksums file, and installs it to %LOCALAPPDATA%\Infrix\bin (added to PATH).
# Override version with $env:INFRIX_VERSION, dir with $env:INFRIX_INSTALL_DIR.
$ErrorActionPreference = 'Stop'
$repo = 'opendlt/infrix-cli'
$base = "https://github.com/$repo/releases"

# Windows binaries ship for amd64 today.
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
if ($arch -eq 'arm64') { Write-Warning 'windows/arm64 is not yet published; using amd64 under emulation'; $arch = 'amd64' }

if ($env:INFRIX_VERSION) {
  $tag = $env:INFRIX_VERSION
} else {
  $latest = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
  $tag = $latest.tag_name
}
if (-not $tag) { throw 'could not resolve latest release tag (set $env:INFRIX_VERSION)' }
$ver = $tag.TrimStart('v')

$archive = "infrix_${ver}_windows_${arch}.zip"
$sums    = "infrix_${ver}_checksums.txt"
$sig     = "infrix_${ver}_checksums.txt.ed25519.sig"
$tmp = Join-Path $env:TEMP ("infrix-install-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  Write-Host "infrix-install: downloading $archive ($tag)"
  Invoke-WebRequest "$base/download/$tag/$archive" -OutFile (Join-Path $tmp $archive)
  Invoke-WebRequest "$base/download/$tag/$sums"    -OutFile (Join-Path $tmp $sums)
  Invoke-WebRequest "$base/download/$tag/$sig"     -OutFile (Join-Path $tmp $sig)

  # --- authenticate the checksums file BEFORE trusting any hash in it ---
  # Pass-17 audit P0-1: verify the detached Ed25519 signature over the checksums
  # against a PINNED release public key (embedded here, never fetched from the
  # endpoint), using OpenSSL. Fail closed on any mismatch.
  $openssl = (Get-Command openssl -ErrorAction SilentlyContinue)
  if (-not $openssl) {
    throw "openssl is required to authenticate the release checksums signature. Install OpenSSL (e.g. Git for Windows ships it) and re-run, or follow the manual steps in the dist VERIFY.md."
  }
  # Pinned Ed25519 release key (RELEASE-SIGNING-KEY.pub, fingerprint d5c3c240...).
  $pinKeyB64 = 'KayNyxm3HuYpCkyi24G2rWXWiXJji0KktABtI2gDui8='
  $pem = "-----BEGIN PUBLIC KEY-----`nMCowBQYDK2VwAyEA$pinKeyB64`n-----END PUBLIC KEY-----`n"
  $pemPath = Join-Path $tmp 'relkey.pem'
  [System.IO.File]::WriteAllText($pemPath, $pem)
  # The signature ships base64-encoded; decode to the raw 64-byte signature.
  $sigRaw = [System.Convert]::FromBase64String((Get-Content (Join-Path $tmp $sig) -Raw).Trim())
  $sigBin = Join-Path $tmp 'sig.bin'
  [System.IO.File]::WriteAllBytes($sigBin, $sigRaw)
  & openssl pkeyutl -verify -pubin -inkey $pemPath -rawin -in (Join-Path $tmp $sums) -sigfile $sigBin *> $null
  if ($LASTEXITCODE -ne 0) {
    throw "checksums signature does NOT verify against the pinned release key - refusing to install (possible tampered release endpoint)"
  }
  Write-Host 'infrix-install: checksums signature verified against the pinned release key'

  $want = (Get-Content (Join-Path $tmp $sums) | Where-Object { $_ -match [regex]::Escape($archive) } |
           Select-Object -First 1).Split(' ')[0]
  if (-not $want) { throw "no checksum entry for $archive" }
  $got = (Get-FileHash (Join-Path $tmp $archive) -Algorithm SHA256).Hash.ToLower()
  if ($want.ToLower() -ne $got) { throw "checksum mismatch (expected $want, got $got) - refusing to install" }
  Write-Host 'infrix-install: checksum verified'

  Expand-Archive -Path (Join-Path $tmp $archive) -DestinationPath $tmp -Force
  $dest = if ($env:INFRIX_INSTALL_DIR) { $env:INFRIX_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Infrix\bin' }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item (Join-Path $tmp 'infrix.exe') (Join-Path $dest 'infrix.exe') -Force

  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($userPath -notlike "*$dest*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$dest", 'User')
    Write-Host "infrix-install: added $dest to your user PATH (restart your shell)"
  }
  Write-Host "infrix-install: installed to $dest\infrix.exe"
  & (Join-Path $dest 'infrix.exe') version
  Write-Host "infrix-install: done - try 'infrix doctor'"
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
