param(
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $ProjectRoot "Koinly-clean.zip"
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("koinly-package-" + [System.Guid]::NewGuid().ToString("N"))
$stagingProject = Join-Path $stagingRoot "Koinly-main"

New-Item -ItemType Directory -Force -Path $stagingProject | Out-Null

robocopy $ProjectRoot $stagingProject /E `
  /XD .dart_tool build .git .gradle node_modules outputs `
      android\.gradle android\app\build `
      windows\flutter\ephemeral linux\flutter\ephemeral `
      cloud\worker\node_modules cloud\worker\.wrangler cloud\worker\dist cloud\worker\build `
  /XF *.zip *.log .env .dev.vars | Out-Null

if ($LASTEXITCODE -gt 7) {
  throw "robocopy failed with exit code $LASTEXITCODE"
}

if (Test-Path -LiteralPath $OutputPath) {
  Remove-Item -LiteralPath $OutputPath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($OutputPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  $stagingProjectFullPath = [System.IO.Path]::GetFullPath($stagingProject).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  Get-ChildItem -LiteralPath $stagingProjectFullPath -Recurse -File | ForEach-Object {
    $fileFullPath = [System.IO.Path]::GetFullPath($_.FullName)
    $relativePath = $fileFullPath.Substring($stagingProjectFullPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $entryName = $relativePath.Replace([System.IO.Path]::DirectorySeparatorChar, '/').Replace([System.IO.Path]::AltDirectorySeparatorChar, '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $fileFullPath, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
} finally {
  $zip.Dispose()
}
Remove-Item -LiteralPath $stagingRoot -Recurse -Force

$zip = [System.IO.Compression.ZipFile]::OpenRead($OutputPath)
try {
  Write-Host "Created $OutputPath"
  Write-Host "Entries: $($zip.Entries.Count)"
  Write-Host "Size: $((Get-Item -LiteralPath $OutputPath).Length) bytes"
} finally {
  $zip.Dispose()
}
