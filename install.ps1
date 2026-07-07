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

# --- Pass-18 audit P2-4: native, dependency-free Ed25519 verification ---
# Windows PowerShell 5.1 runs on .NET Framework, which has no Ed25519 primitive,
# and the release checksums are Ed25519-signed. Rather than require OpenSSL on a
# clean Windows host, verify the signature in pure PowerShell (RFC 8032) using
# System.Numerics.BigInteger + the built-in SHA-512 — no external dependency.
function Test-InfrixEd25519 {
  param([byte[]]$PublicKey, [byte[]]$Message, [byte[]]$Signature)
  if ($PublicKey.Length -ne 32) { return $false }
  if ($Signature.Length -ne 64) { return $false }

  $p = ([System.Numerics.BigInteger]::Pow(2, 255)) - 19
  $L = ([System.Numerics.BigInteger]::Pow(2, 252)) + [System.Numerics.BigInteger]::Parse('27742317777372353535851937790883648493')

  function M([System.Numerics.BigInteger]$a) { $r = $a % $p; if ($r.Sign -lt 0) { $r += $p }; return $r }
  function Inv([System.Numerics.BigInteger]$a) { return [System.Numerics.BigInteger]::ModPow((M $a), $p - 2, $p) }
  # unsigned little-endian bytes -> BigInteger (append 0x00 so the sign bit stays clear)
  function LeToBig([byte[]]$b) { $t = New-Object 'byte[]' ($b.Length + 1); [Array]::Copy($b, $t, $b.Length); return New-Object System.Numerics.BigInteger (,$t) }

  $d = M ((M ([System.Numerics.BigInteger]::MinusOne * 121665)) * (Inv ([System.Numerics.BigInteger]121666)))

  # Extended twisted-Edwards points as @{X;Y;Z;T} hashtables; no per-op inverse.
  function PtAdd($P1, $P2) {
    $A = M (($P1.Y - $P1.X) * ($P2.Y - $P2.X))
    $B = M (($P1.Y + $P1.X) * ($P2.Y + $P2.X))
    $C = M ($P1.T * 2 * $d * $P2.T)
    $D = M ($P1.Z * 2 * $P2.Z)
    $E = $B - $A; $F = $D - $C; $G = $D + $C; $H = $B + $A
    return @{ X = (M ($E * $F)); Y = (M ($G * $H)); Z = (M ($F * $G)); T = (M ($E * $H)) }
  }
  function PtDouble($P1) {
    $A = M ($P1.X * $P1.X); $B = M ($P1.Y * $P1.Y); $Cc = M (2 * $P1.Z * $P1.Z)
    $Dd = M ([System.Numerics.BigInteger]::MinusOne * $A)
    $E = M (($P1.X + $P1.Y) * ($P1.X + $P1.Y) - $A - $B)
    $G = $Dd + $B; $F = $G - $Cc; $H = $Dd - $B
    return @{ X = (M ($E * $F)); Y = (M ($G * $H)); Z = (M ($F * $G)); T = (M ($E * $H)) }
  }
  function PtMul([System.Numerics.BigInteger]$e, $P1) {
    $Q = @{ X = [System.Numerics.BigInteger]::Zero; Y = [System.Numerics.BigInteger]::One; Z = [System.Numerics.BigInteger]::One; T = [System.Numerics.BigInteger]::Zero }
    $bits = ($e.ToByteArray().Length * 8)
    for ($i = $bits; $i -ge 0; $i--) {
      $Q = PtDouble $Q
      if ((($e -shr $i) -band [System.Numerics.BigInteger]::One) -eq [System.Numerics.BigInteger]::One) { $Q = PtAdd $Q $P1 }
    }
    return $Q
  }
  function PtEqual($P1, $P2) {
    return ((M ($P1.X * $P2.Z)) -eq (M ($P2.X * $P1.Z))) -and ((M ($P1.Y * $P2.Z)) -eq (M ($P2.Y * $P1.Z)))
  }
  function RecoverX([System.Numerics.BigInteger]$y, [int]$sign) {
    $y2 = M ($y * $y)
    $u = M ($y2 - 1); $v = M ($d * $y2 + 1)
    $x = M ($u * (Inv $v))
    $x = [System.Numerics.BigInteger]::ModPow($x, ($p + 3) / 8, $p)
    if ((M ($x * $x - (M ($u * (Inv $v))))) -ne [System.Numerics.BigInteger]::Zero) {
      $x = M ($x * ([System.Numerics.BigInteger]::ModPow([System.Numerics.BigInteger]2, ($p - 1) / 4, $p)))
    }
    if ((M ($x * $x - (M ($u * (Inv $v))))) -ne [System.Numerics.BigInteger]::Zero) { return $null }
    if (([int]($x -band [System.Numerics.BigInteger]::One)) -ne $sign) { $x = $p - $x }
    return $x
  }
  function DecodePoint([byte[]]$enc) {
    $b = $enc.Clone()
    $sign = ($b[31] -shr 7) -band 1
    $b[31] = $b[31] -band 0x7F
    $y = LeToBig $b
    if ($y -ge $p) { return $null }
    $x = RecoverX $y $sign
    if ($null -eq $x) { return $null }
    return @{ X = $x; Y = $y; Z = [System.Numerics.BigInteger]::One; T = (M ($x * $y)) }
  }

  $By = M (4 * (Inv ([System.Numerics.BigInteger]5)))
  $Bx = RecoverX $By 0
  $Bpt = @{ X = $Bx; Y = $By; Z = [System.Numerics.BigInteger]::One; T = (M ($Bx * $By)) }

  $A = DecodePoint $PublicKey
  if ($null -eq $A) { return $false }
  $Rbytes = $Signature[0..31]
  $R = DecodePoint $Rbytes
  if ($null -eq $R) { return $false }
  $S = LeToBig ($Signature[32..63])
  if ($S -ge $L) { return $false }

  $sha = [System.Security.Cryptography.SHA512]::Create()
  $kInput = New-Object 'byte[]' (32 + 32 + $Message.Length)
  [Array]::Copy($Rbytes, 0, $kInput, 0, 32)
  [Array]::Copy($PublicKey, 0, $kInput, 32, 32)
  [Array]::Copy($Message, 0, $kInput, 64, $Message.Length)
  $kHash = $sha.ComputeHash($kInput)
  $k = (LeToBig $kHash) % $L

  # Check [8][S]B == [8](R + [k]A) (cofactor-cleared, matches RFC 8032 verify).
  $lhs = PtMul $S $Bpt
  $rhs = PtAdd $R (PtMul $k $A)
  $lhs = PtDouble (PtDouble (PtDouble $lhs))
  $rhs = PtDouble (PtDouble (PtDouble $rhs))
  return (PtEqual $lhs $rhs)
}

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
  # Pass-17 audit P0-1 + pass-18 P2-4: verify the detached Ed25519 signature over
  # the checksums against a PINNED release public key (embedded here, never
  # fetched from the endpoint) using the NATIVE pure-PowerShell verifier above —
  # no OpenSSL, no external dependency on a clean Windows host. Fail closed on any
  # missing/malformed/invalid signature.
  # Pinned Ed25519 release key (RELEASE-SIGNING-KEY.pub, fingerprint d5c3c240...).
  $pinKeyB64 = 'KayNyxm3HuYpCkyi24G2rWXWiXJji0KktABtI2gDui8='
  $pubKey = [System.Convert]::FromBase64String($pinKeyB64)
  # The signature ships base64-encoded; decode to the raw 64-byte signature.
  $sigRaw = [System.Convert]::FromBase64String((Get-Content (Join-Path $tmp $sig) -Raw).Trim())
  if ($sigRaw.Length -ne 64) {
    throw "checksums signature is not a 64-byte Ed25519 signature (got $($sigRaw.Length) bytes) - refusing to install"
  }
  $sumsBytes = [System.IO.File]::ReadAllBytes((Join-Path $tmp $sums))
  if (-not (Test-InfrixEd25519 -PublicKey $pubKey -Message $sumsBytes -Signature $sigRaw)) {
    throw "checksums signature does NOT verify against the pinned release key - refusing to install (possible tampered release endpoint)"
  }
  Write-Host 'infrix-install: checksums signature verified against the pinned release key (native Ed25519)'

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
