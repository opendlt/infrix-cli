# Pass-18 audit P2-4: prove the native (dependency-free) Ed25519 verifier in
# install.ps1 is correct — it verifies an RFC 8032 known-answer vector, verifies
# the real committed release signature under the pinned key, and fails closed on
# a tampered message. Extracts the ACTUAL function from install.ps1 (AST) so the
# test can never drift from the shipped verifier.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installPs1 = Join-Path (Split-Path -Parent $here) 'install.ps1'

# Extract just the Test-InfrixEd25519 function definition from install.ps1.
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($installPs1, [ref]$tokens, [ref]$errors)
$fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-InfrixEd25519' }, $true) | Select-Object -First 1
if (-not $fn) { throw 'Test-InfrixEd25519 not found in install.ps1' }
Invoke-Expression $fn.Extent.Text

function HexBytes([string]$h) {
  $h = $h -replace '\s', ''
  $b = New-Object 'byte[]' ($h.Length / 2)
  for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [Convert]::ToByte($h.Substring($i * 2, 2), 16) }
  return ,$b
}

$fail = 0

# 1. RFC 8032 Ed25519 Test 1 (empty message) — a canonical known-answer vector.
$pk1  = HexBytes 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
$sig1 = HexBytes 'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'
if (Test-InfrixEd25519 -PublicKey $pk1 -Message (New-Object 'byte[]' 0) -Signature $sig1) {
  Write-Host 'PASS: RFC 8032 Test 1 vector verifies'
} else { Write-Host 'FAIL: RFC 8032 Test 1 vector did NOT verify'; $fail++ }

# 2. RFC 8032 Ed25519 Test 2 (1-byte message 0x72).
$pk2  = HexBytes '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c'
$msg2 = HexBytes '72'
$sig2 = HexBytes '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00'
if (Test-InfrixEd25519 -PublicKey $pk2 -Message $msg2 -Signature $sig2) {
  Write-Host 'PASS: RFC 8032 Test 2 vector verifies'
} else { Write-Host 'FAIL: RFC 8032 Test 2 vector did NOT verify'; $fail++ }

# 3. Tampered message must fail closed.
$msgBad = HexBytes '73'
if (-not (Test-InfrixEd25519 -PublicKey $pk2 -Message $msgBad -Signature $sig2)) {
  Write-Host 'PASS: tampered message rejected'
} else { Write-Host 'FAIL: tampered message was accepted'; $fail++ }

# 4. The real committed release signature under the pinned key (if the dist fixture is present).
$distCandidates = @(
  (Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'infrix-cli-dist-v0.1.1'),
  (Join-Path (Split-Path -Parent $here) 'infrix-cli-dist-v0.1.1')
)
$dist = $distCandidates | Where-Object { Test-Path (Join-Path $_ 'infrix_0.1.1_checksums.txt') } | Select-Object -First 1
if ($dist) {
  $sums = [System.IO.File]::ReadAllBytes((Join-Path $dist 'infrix_0.1.1_checksums.txt'))
  $sigRaw = [System.Convert]::FromBase64String((Get-Content (Join-Path $dist 'infrix_0.1.1_checksums.txt.ed25519.sig') -Raw).Trim())
  $pub = [System.Convert]::FromBase64String('KayNyxm3HuYpCkyi24G2rWXWiXJji0KktABtI2gDui8=')
  if (Test-InfrixEd25519 -PublicKey $pub -Message $sums -Signature $sigRaw) {
    Write-Host 'PASS: real release checksums signature verifies under the pinned key'
  } else { Write-Host 'FAIL: real release checksums signature did NOT verify'; $fail++ }
  # Tamper the checksums -> must fail.
  $sumsBad = $sums.Clone(); $sumsBad[0] = $sumsBad[0] -bxor 0xFF
  if (-not (Test-InfrixEd25519 -PublicKey $pub -Message $sumsBad -Signature $sigRaw)) {
    Write-Host 'PASS: tampered release checksums rejected'
  } else { Write-Host 'FAIL: tampered release checksums accepted'; $fail++ }
} else {
  Write-Host 'SKIP: release dist fixture not present next to the repo'
}

if ($fail -ne 0) { throw "$fail Ed25519 native-verifier assertion(s) failed" }
Write-Host 'ALL native Ed25519 verifier assertions passed'
