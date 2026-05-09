# Bumpea la versión en los 3 lugares donde vive:
#   - pubspec.yaml (version: X.Y.Z+N)
#   - lib/core/constants/app_constants.dart (appVersion = 'v X.Y.Z')
#   - windows/runner/main.cpp (título de la ventana)
#
# Uso:
#   .\scripts\bump_version.ps1                    -> sugiere el siguiente patch
#   .\scripts\bump_version.ps1 -Version 1.2.3+45  -> set explícito
#   .\scripts\bump_version.ps1 -DryRun            -> muestra qué cambiaría
#
# Convención: pubspec usa MAJOR.MINOR.PATCH+BUILD (ej. 1.0.8+16). Cada
# bump del patch incrementa también el build (1.0.8+16 → 1.0.9+17).
# El "appVersion" en el constant coincide 1:1 con el patch del pubspec
# (`v MAJOR.MINOR.PATCH`). Antes había un offset legacy `patch + 6`
# que generaba mismatch entre pubspec y UI; sacado 2026-05-08.

param(
    [string]$Version = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot       = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pubspec        = Join-Path $repoRoot 'pubspec.yaml'
$appConstants   = Join-Path $repoRoot 'lib\core\constants\app_constants.dart'
$mainCpp        = Join-Path $repoRoot 'windows\runner\main.cpp'

# --- Leer versión actual de pubspec --------------------------------
$pubLines = Get-Content $pubspec
$verLine  = $pubLines | Where-Object { $_ -match '^version:\s*(\S+)' } | Select-Object -First 1
if (-not $verLine) { throw "No encuentro 'version:' en pubspec.yaml" }
$verActual = ($verLine -replace '^version:\s*', '').Trim()

if (-not ($verActual -match '^(\d+)\.(\d+)\.(\d+)\+(\d+)$')) {
    throw "Version actual '$verActual' no respeta MAJOR.MINOR.PATCH+BUILD."
}
$major   = [int]$matches[1]
$minor   = [int]$matches[2]
$patch   = [int]$matches[3]
$build   = [int]$matches[4]

# --- Decidir versión nueva -----------------------------------------
if ($Version -eq '') {
    $nuevoPatch = $patch + 1
    $nuevoBuild = $build + 1
    $Version    = "$major.$minor.$nuevoPatch+$nuevoBuild"
    Write-Host "Sugerida: $verActual -> $Version" -ForegroundColor Cyan
}

if (-not ($Version -match '^(\d+)\.(\d+)\.(\d+)\+(\d+)$')) {
    throw "Version nueva '$Version' no respeta MAJOR.MINOR.PATCH+BUILD."
}
$nMajor = [int]$matches[1]
$nMinor = [int]$matches[2]
$nPatch = [int]$matches[3]
$nBuild = [int]$matches[4]

# appVersion visible coincide 1:1 con el patch del pubspec
# (decisión 2026-05-08: sacar el offset legacy que históricamente
# era `patch + 6` y generaba mismatch entre pubspec y UI).
$appVer = "v $nMajor.$nMinor.$nPatch"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Bump de version" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  pubspec.yaml      : $verActual -> $Version"
Write-Host "  app_constants.dart: appVersion -> '$appVer'"
Write-Host "  main.cpp (titulo) : 'Coopertrans Movil - $appVer (build $nBuild)'"
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY-RUN] No se modifico ningun archivo." -ForegroundColor Yellow
    exit 0
}

# --- Aplicar cambios ----------------------------------------------
$pubContent = Get-Content $pubspec -Raw
$pubContent = $pubContent -replace "version:\s*\S+", "version: $Version"
Set-Content -Path $pubspec -Value $pubContent -NoNewline -Encoding UTF8

$constContent = Get-Content $appConstants -Raw
$constContent = $constContent -replace "appVersion\s*=\s*'v [^']+'", "appVersion = '$appVer'"
Set-Content -Path $appConstants -Value $constContent -NoNewline -Encoding UTF8

$mainContent = Get-Content $mainCpp -Raw
# Reemplaza el string del titulo. Tolerante con o sin acento, con
# diferentes formatos de version.
$mainContent = $mainContent -replace 'L"Coopertrans M[^"]*"', "L`"Coopertrans Móvil — $appVer (build $nBuild)`""
Set-Content -Path $mainCpp -Value $mainContent -Encoding UTF8

Write-Host "OK. Cambios aplicados." -ForegroundColor Green
Write-Host ""
Write-Host "Proximos pasos:" -ForegroundColor Cyan
Write-Host "  flutter build windows --release"
Write-Host "  git add pubspec.yaml lib/core/constants/app_constants.dart windows/runner/main.cpp"
Write-Host "  git commit -m 'chore: bump version $verActual -> $Version'"
Write-Host "  .\scripts\release_app.ps1"
