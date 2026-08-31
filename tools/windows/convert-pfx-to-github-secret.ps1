param(
  [Parameter(Mandatory = $true)]
  [string]$PfxPath
)

if (!(Test-Path $PfxPath)) {
  throw "PFX file was not found: $PfxPath"
}

$resolved = (Resolve-Path $PfxPath).Path
$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($resolved))
$base64 | Set-Clipboard
Write-Host "Copied Base64 PFX value to clipboard. Add it as GitHub secret WINDOWS_CODESIGN_PFX_BASE64."
