# Empaqueta el build Windows release de la app Flutter y lo publica como
# GitHub Release. Pensado para correr UNA SOLA VEZ por release, en la PC
# donde acabás de buildear.
#
# Pre-requisitos:
#   - flutter build windows --release (corrido antes, deja el output en
#     build/windows/x64/runner/Release/).
#   - gh CLI instalado y autenticado (`gh auth login`).
#   - El número de versión en pubspec.yaml ya bumpeado para este release.
#
# Uso (desde la raíz del repo):
#   .\scripts\release_app.ps1
#   .\scripts\release_app.ps1 -Notes "Fix de cálculo de service preventivo"
#   .\scripts\release_app.ps1 -DryRun

param(
    [string]$Notes = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pubspec  = Join-Path $repoRoot 'pubspec.yaml'
$buildDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'

# --- 1. Leer versión de pubspec.yaml --------------------------------
$pubLines = Get-Content $pubspec
$verLine = $pubLines | Where-Object { $_ -match '^version:\s*(\S+)' } | Select-Object -First 1
if (-not $verLine) { throw "No encuentro 'version:' en pubspec.yaml" }
$version = ($verLine -replace '^version:\s*', '').Trim()
$tag = "v$version"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "RELEASE: $tag" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# --- 2. Verificar gh CLI -------------------------------------------
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    throw "gh CLI no está instalado. Instalar con: winget install GitHub.cli"
}
# Ejecutamos `gh auth status` redirigiendo TODOS los streams a $null.
# Sin esto, los mensajes informativos de gh a stderr disparan excepción
# en PowerShell con $ErrorActionPreference='Stop' y abortan el script.
& gh auth status *>$null
if ($LASTEXITCODE -ne 0) {
    & gh auth status   # ahora sí mostrar el detalle al usuario
    throw "gh CLI no está autenticado. Correr: gh auth login"
}

# --- 3. Verificar que existe el build ------------------------------
$exePath = Join-Path $buildDir 'coopertrans_movil.exe'
if (-not (Test-Path $exePath)) {
    Write-Host "ERROR: no encontre $exePath" -ForegroundColor Red
    Write-Host "Antes de correr este script, hace:" -ForegroundColor Yellow
    Write-Host "  flutter build windows --release" -ForegroundColor Yellow
    exit 1
}

# --- 4. Verificar que el tag no exista ya --------------------------
# Mismo manejo de streams: si el release no existe gh escribe
# "release not found" a stderr (esperable, no es error real para
# nuestro flujo).
& gh release view $tag *>$null
if ($LASTEXITCODE -eq 0) {
    throw "El release $tag ya existe en GitHub. Bumpeá la versión en pubspec.yaml antes."
}

# --- 5. Verificar que el repo está limpio + pusheado ---------------
Push-Location $repoRoot
try {
    $dirty = git status --porcelain
    if ($dirty) {
        Write-Host "ADVERTENCIA: hay cambios sin commitear:" -ForegroundColor Yellow
        Write-Host $dirty
        $confirm = Read-Host "¿Seguir igual? (s/N)"
        if ($confirm -ne 's' -and $confirm -ne 'S') { exit 1 }
    }
    $unpushed = git log --oneline '@{u}..HEAD' 2>$null
    if ($unpushed) {
        Write-Host "ADVERTENCIA: hay $(($unpushed | Measure-Object).Count) commits sin pushear:" -ForegroundColor Yellow
        Write-Host $unpushed
        $confirm = Read-Host "El release apunta al codigo del remoto. ¿Pushear primero? (S/n)"
        if ($confirm -ne 'n' -and $confirm -ne 'N') {
            git push
            if ($LASTEXITCODE -ne 0) { throw "git push falló" }
        }
    }
}
finally { Pop-Location }

# --- 6. Crear zip --------------------------------------------------
$zipName = "coopertrans_movil_$($version -replace '\+','-build').zip"
$zipPath = Join-Path $env:TEMP $zipName

# Sumar VERSION.txt al build (lo lee el launcher)
Set-Content -Path (Join-Path $buildDir 'VERSION.txt') -Value $version -Encoding UTF8

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Write-Host ""
Write-Host "[1/3] Empaquetando $buildDir → $zipName ..." -ForegroundColor Cyan
Compress-Archive -Path "$buildDir\*" -DestinationPath $zipPath -CompressionLevel Optimal
$sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Host "  OK ($sizeMB MB)" -ForegroundColor Green

# --- 7. Crear release en GitHub ------------------------------------
if (-not $Notes) {
    # Notas auto: últimos 5 commits
    Push-Location $repoRoot
    try {
        $log = git log --oneline -5 --no-decorate
        $Notes = "Cambios recientes:`n`n" + ($log | ForEach-Object { "- $_" } | Out-String)
    }
    finally { Pop-Location }
}

if ($DryRun) {
    Write-Host ""
    Write-Host "[DRY-RUN] No publico nada. El release sería:" -ForegroundColor Yellow
    Write-Host "  Tag:      $tag" -ForegroundColor White
    Write-Host "  Asset:    $zipName ($sizeMB MB)" -ForegroundColor White
    Write-Host "  Notes:" -ForegroundColor White
    Write-Host $Notes
    Write-Host ""
    Write-Host "Para publicarlo realmente:" -ForegroundColor Cyan
    Write-Host "  .\scripts\release_app.ps1" -ForegroundColor White
    Remove-Item $zipPath -Force
    exit 0
}

Write-Host ""
Write-Host "[2/3] Creando release $tag en GitHub..." -ForegroundColor Cyan

# Si hay instalador .exe compilado en dist/, lo sumamos como segundo asset.
# Soporta el filename que genera build_installer.ps1 (que reemplaza '+' por '-build').
$versionInno = $version -replace '\+', '-build'
$installerExe = Join-Path $repoRoot "dist\CoopertransMovil-Setup-$versionInno.exe"
$assets = @($zipPath)
if (Test-Path $installerExe) {
    $instMB = [math]::Round((Get-Item $installerExe).Length / 1MB, 1)
    Write-Host "  Sumando instalador: $(Split-Path $installerExe -Leaf) ($instMB MB)" -ForegroundColor Cyan
    $assets += $installerExe
} else {
    Write-Host "  (sin instalador .exe en dist\ — para sumarlo: .\scripts\build_installer.ps1)" -ForegroundColor DarkGray
}

& gh release create $tag $assets --title "Coopertrans Movil $tag" --notes $Notes
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error al crear release. El zip quedó en $zipPath" -ForegroundColor Red
    exit 1
}

# --- 8. Cleanup ----------------------------------------------------
Remove-Item $zipPath -Force

Write-Host ""
Write-Host "[3/3] Release publicado correctamente." -ForegroundColor Green
Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "OK RELEASE $tag" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Las otras PCs van a tomar la actualización la próxima vez" -ForegroundColor Cyan
Write-Host "que el operador haga doble click en el icono 'Coopertrans Móvil'." -ForegroundColor Cyan
