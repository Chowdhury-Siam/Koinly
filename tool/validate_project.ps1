param(
  [switch]$SkipTests,
  [switch]$SkipAnalyze,
  [switch]$SkipPubGet,
  [int]$PubGetTimeoutSeconds = 180,
  [int]$AnalyzeTimeoutSeconds = 180,
  [int]$TestTimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $ProjectRoot

function Invoke-ProcessWithTimeout {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][int]$TimeoutSeconds
  )

  Write-Host ""
  Write-Host "Running $Label..."
  Write-Host "$FilePath $($Arguments -join ' ')"

  $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru
  $completed = $process.WaitForExit($TimeoutSeconds * 1000)
  if (-not $completed) {
    try {
      $process.Kill($true)
    } catch {
      $process.Kill()
    }
    throw "$Label timed out after $TimeoutSeconds seconds. The project currently has a very large lib\main.dart; if this keeps happening, split the app into smaller Dart files before treating analyzer timeout as a source error."
  }

  if ($process.ExitCode -ne 0) {
    throw "$Label failed with exit code $($process.ExitCode)."
  }
}

Write-Host "Koinly validation"
Write-Host "Project: $ProjectRoot"
$DartFileCount = @(
  Get-ChildItem -Path "lib","test" -Recurse -Filter "*.dart" -File -ErrorAction SilentlyContinue
).Count
$WorkerNodeModulesPath = Join-Path $ProjectRoot "cloud\worker\node_modules"
$WorkerNodeModulesCount = 0
if (Test-Path $WorkerNodeModulesPath) {
  $WorkerNodeModulesCount = @(
    Get-ChildItem -Path $WorkerNodeModulesPath -Recurse -File -ErrorAction SilentlyContinue
  ).Count
}
Write-Host "Dart files: $DartFileCount"
Write-Host "Worker node_modules files: $WorkerNodeModulesCount"

if (-not $SkipPubGet) {
  Invoke-ProcessWithTimeout `
    -Label "flutter pub get" `
    -FilePath "flutter" `
    -Arguments @("pub", "get") `
    -TimeoutSeconds $PubGetTimeoutSeconds
} else {
  Write-Host "Skipping pub get."
}

if (-not $SkipAnalyze) {
  Invoke-ProcessWithTimeout `
    -Label "flutter analyze --fatal-infos" `
    -FilePath "flutter" `
    -Arguments @("analyze", "--fatal-infos") `
    -TimeoutSeconds $AnalyzeTimeoutSeconds
} else {
  Write-Host "Skipping analyzer."
}

if (-not $SkipTests) {
  Invoke-ProcessWithTimeout `
    -Label "flutter test" `
    -FilePath "flutter" `
    -Arguments @("test") `
    -TimeoutSeconds $TestTimeoutSeconds
} else {
  Write-Host "Skipping tests."
}

Write-Host "Validation complete."
