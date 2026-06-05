# Test IDCloudHost S3 public file access.
# Run from PowerShell:  .\test-idcloudhost.ps1
# This script will prompt for credentials then upload+verify a test file.

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Config (sesuaikan kalau beda)
# ---------------------------------------------------------------------------
$Endpoint  = 'https://s3.idcloudhost.com'
$Bucket    = 'moccilabs'
$Prefix    = 'patchfly'
$Region    = 'auto'
$TestKey   = "$Prefix/test/patchfly-public-test.txt"

# ---------------------------------------------------------------------------
# Pretty output
# ---------------------------------------------------------------------------
function Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function OK($msg)      { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn($msg)    { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Fail($msg)    { Write-Host "[X] $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# Check AWS CLI
# ---------------------------------------------------------------------------
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
  Fail "aws CLI not found. Install: winget install Amazon.AWSCLI"
}

# ---------------------------------------------------------------------------
# Get credentials
# ---------------------------------------------------------------------------
Step "IDCloudHost S3 credentials"
$AccessKey = Read-Host "  Access Key ID"
$SecureSecret = Read-Host "  Secret Access Key" -AsSecureString
$SecretKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureSecret)
)
$env:AWS_ACCESS_KEY_ID     = $AccessKey
$env:AWS_SECRET_ACCESS_KEY = $SecretKey
$env:AWS_DEFAULT_REGION    = $Region
OK "Credentials set (in-memory only, not saved)"

# ---------------------------------------------------------------------------
# Step 1: List bucket (verify access + bucket exists)
# ---------------------------------------------------------------------------
Step "Step 1/4: Verify bucket '$Bucket' exists and is reachable"
try {
  aws s3 ls "s3://$Bucket/" --endpoint-url $Endpoint | Out-Null
  OK "Bucket accessible"
} catch {
  Fail "Cannot access bucket '$Bucket'. Causes: wrong creds, bucket doesn't exist, or wrong endpoint.`n  Error: $_"
}

# ---------------------------------------------------------------------------
# Step 2: Create + upload test file with public-read ACL
# ---------------------------------------------------------------------------
Step "Step 2/4: Upload test file with public-read ACL"
$TmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "patchfly-test-$(Get-Random).txt"
"Patchfly IDCloudHost public ACL test - $(Get-Date -Format o)" | Out-File $TmpFile -Encoding ASCII -NoNewline
Write-Host "  File: $TmpFile" -ForegroundColor Gray

try {
  aws s3 cp $TmpFile "s3://$Bucket/$TestKey" `
    --endpoint-url $Endpoint `
    --acl public-read 2>&1 | Out-Null
  OK "Upload succeeded (with --acl public-read)"
} catch {
  Remove-Item $TmpFile -ErrorAction SilentlyContinue
  Fail "Upload failed: $_"
}

# ---------------------------------------------------------------------------
# Step 3: Verify file is publicly accessible (NO auth)
# ---------------------------------------------------------------------------
Step "Step 3/4: Test public access (no auth)"
$PublicUrl = "$Endpoint/$Bucket/$TestKey"
Write-Host "  URL: $PublicUrl" -ForegroundColor Gray
try {
  $resp = Invoke-WebRequest -Uri $PublicUrl -Method Head -UseBasicParsing -ErrorAction Stop
  if ($resp.StatusCode -eq 200) {
    OK "HTTP 200 - file is publicly accessible!"
  } else {
    Warn "HTTP $($resp.StatusCode) - unexpected"
  }
} catch {
  $code = $_.Exception.Response.StatusCode.value__
  if (-not $code) { $code = 'unknown' }
  Fail "HTTP $code - file is NOT publicly accessible.`n  This means IDCloudHost blocks public ACLs. Fallback to R2/MinIO."
}

# ---------------------------------------------------------------------------
# Step 4: Cleanup
# ---------------------------------------------------------------------------
Step "Step 4/4: Cleanup"
aws s3 rm "s3://$Bucket/$TestKey" --endpoint-url $Endpoint 2>&1 | Out-Null
Remove-Item $TmpFile -ErrorAction SilentlyContinue
OK "Test file deleted"

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  IDCloudHost public file access WORKS!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Buka https://github.com/fatmuh/patchfly/settings/secrets/actions" -ForegroundColor Gray
Write-Host "  2. Tambah 2 secrets:" -ForegroundColor Gray
Write-Host "       AWS_ACCESS_KEY_ID     = $AccessKey" -ForegroundColor Gray
Write-Host "       AWS_SECRET_ACCESS_KEY = <your secret key>" -ForegroundColor Gray
Write-Host "  3. Push tag:" -ForegroundColor Gray
Write-Host "       cd D:/Personal/patchfly/patchfly" -ForegroundColor Gray
Write-Host "       git tag v0.0.1 HEAD" -ForegroundColor Gray
Write-Host "       git push origin v0.0.1" -ForegroundColor Gray
Write-Host "  4. Cek workflow: https://github.com/fatmuh/patchfly/actions" -ForegroundColor Gray
Write-Host ""
