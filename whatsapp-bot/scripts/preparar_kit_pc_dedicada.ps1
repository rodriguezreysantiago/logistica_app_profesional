# Prepara una carpeta en el escritorio con TODO lo que necesitas para
# instalar el bot WhatsApp en una PC dedicada nueva (modo 24/7).
#
# La carpeta resultante (~629 MB, casi todo .wwebjs_auth) se copia a
# pendrive / OneDrive / lo-que-sea y se descomprime en la PC nueva
# en el path indicado en el LEEME.txt.
#
# Que arma:
#
#   bot-pc-dedicada/
#   ├── LEEME.txt                 ← guía rápida
#   ├── serviceAccountKey.json    ← creds Firebase
#   ├── .env                      ← config bot
#   └── .wwebjs_auth/             ← sesión WhatsApp (evita reescaneo)
#
# El repo del bot NO se empaqueta — la PC nueva lo clona con
# `git clone` (ver LEEME.txt). Solo los 3 secretos que NO están en git.
#
# Que hace el script:
#
#   1. Detiene el servicio CoopertransMovilBot (sino .wwebjs_auth está
#      lockeada por el process Node y no se puede copiar).
#   2. Copia los 3 secretos a la carpeta destino con robocopy /B
#      (backup mode = acceso a archivos del LocalSystem).
#   3. Genera LEEME.txt con los pasos exactos a correr en la PC nueva.
#   4. Vuelve a arrancar el servicio (deja todo como estaba).
#
# Tiempo estimado: 1-3 min (depende de la velocidad del disco; los
# 629 MB de .wwebjs_auth son la mayor parte).
#
# Requiere ejecutar como Administrador (para detener el servicio +
# acceder a archivos del LocalSystem).
#
# Uso:
#   1. PowerShell como Administrador.
#   2. Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   3. cd <ruta>\whatsapp-bot
#   4. .\scripts\preparar_kit_pc_dedicada.ps1
#
# Flags opcionales:
#   -DestinoPath <path>   Override del destino (default: <Desktop>\bot-pc-dedicada).
#   -Force                Sobreescribir destino si ya existe (sin pregunta).
#   -SinDetenerBot        NO detener el bot (más rápido pero la copia de
#                          .wwebjs_auth puede saltarse archivos lockeados).

[CmdletBinding()]
param(
    [string]$DestinoPath,
    [switch]$Force,
    [switch]$SinDetenerBot
)

$ErrorActionPreference = 'Stop'
$serviceName = 'CoopertransMovilBot'

# --- 1. Verificar admin --------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: ejecutar como Administrador." -ForegroundColor Red
    Write-Host "(necesario para detener el servicio + leer archivos de LocalSystem)" -ForegroundColor Yellow
    exit 1
}

# --- 2. Resolver paths ---------------------------------------------
$botRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path (Join-Path $botRoot '..')).Path
if (-not $DestinoPath) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $DestinoPath = Join-Path $desktop 'bot-pc-dedicada'
}

$srcWwebjs       = Join-Path $botRoot '.wwebjs_auth'
$srcEnv          = Join-Path $botRoot '.env'
$srcServiceAcc   = Join-Path $repoRoot 'serviceAccountKey.json'

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "PREPARANDO KIT PC DEDICADA - Bot WhatsApp" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Repo bot:    $botRoot"
Write-Host "Destino:     $DestinoPath"
Write-Host ""

# --- 3. Verificar que existan los archivos -------------------------
$faltantes = @()
if (-not (Test-Path $srcWwebjs))     { $faltantes += '.wwebjs_auth/ (sesión WhatsApp)' }
if (-not (Test-Path $srcEnv))        { $faltantes += '.env (config bot)' }
if (-not (Test-Path $srcServiceAcc)) { $faltantes += 'serviceAccountKey.json (creds Firebase)' }
if ($faltantes.Count -gt 0) {
    Write-Host "ERROR: faltan archivos en el repo:" -ForegroundColor Red
    $faltantes | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

# --- 4. Manejo del destino -----------------------------------------
if (Test-Path $DestinoPath) {
    if ($Force) {
        Write-Host "WARN: destino existe. Borrando (--Force)..." -ForegroundColor Yellow
        Remove-Item -Path $DestinoPath -Recurse -Force
    } else {
        Write-Host "ERROR: la carpeta destino ya existe:" -ForegroundColor Red
        Write-Host "  $DestinoPath" -ForegroundColor Yellow
        Write-Host "Ejecutar con -Force para sobreescribir, o borrarla a mano." -ForegroundColor Yellow
        exit 1
    }
}
New-Item -ItemType Directory -Path $DestinoPath -Force | Out-Null

# --- 5. Detener bot si está corriendo ------------------------------
$botEstaba = $false
if (-not $SinDetenerBot) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Host "[1/4] Deteniendo $serviceName temporalmente..." -ForegroundColor Cyan
        Stop-Service -Name $serviceName -ErrorAction Stop
        Start-Sleep -Seconds 3   # gracia para que libere los handles
        $botEstaba = $true
        Write-Host "  OK bot detenido (volveré a arrancarlo al final)" -ForegroundColor Green
    } else {
        Write-Host "[1/4] Bot ya estaba detenido — sigo." -ForegroundColor DarkGray
    }
} else {
    Write-Host "[1/4] -SinDetenerBot: NO detengo el bot (riesgo: archivos lockeados)" -ForegroundColor Yellow
}

# --- 6. Copiar archivos --------------------------------------------
Write-Host ""
Write-Host "[2/4] Copiando archivos al kit..." -ForegroundColor Cyan

# .env y serviceAccountKey son chicos: Copy-Item alcanza.
Copy-Item -Path $srcEnv        -Destination (Join-Path $DestinoPath '.env')
Copy-Item -Path $srcServiceAcc -Destination (Join-Path $DestinoPath 'serviceAccountKey.json')
Write-Host "  OK .env + serviceAccountKey.json" -ForegroundColor Green

# .wwebjs_auth: 629 MB con archivos lockeables. Robocopy /B (backup
# mode) ignora ACLs y locks transitorios. /MIR mira la copia
# completa, /R:1 /W:1 reintentos rápidos, /NFL /NDL /NJH /NJS modo
# silencioso. /XJ excluye junctions (no debería haber, pero por las
# dudas).
$destWwebjs = Join-Path $DestinoPath '.wwebjs_auth'
Write-Host "  Copiando .wwebjs_auth/ (~629 MB, tarda 1-2 min)..." -ForegroundColor Cyan
$rc = robocopy $srcWwebjs $destWwebjs /MIR /B /R:1 /W:1 /NFL /NDL /NJH /NJS /XJ /NP
# Robocopy: 0=nada, 1=copiados, 2=extras, 3=copiados+extras. Códigos
# >= 8 son errores reales. <8 es OK.
if ($LASTEXITCODE -ge 8) {
    Write-Host "  ERROR: robocopy falló con código $LASTEXITCODE" -ForegroundColor Red
    if ($botEstaba) { Start-Service -Name $serviceName }
    exit 1
}
$copiadoSize = [math]::Round(
    (Get-ChildItem -Path $destWwebjs -Recurse -File -ErrorAction SilentlyContinue |
     Measure-Object Length -Sum).Sum / 1MB,
    1
)
Write-Host "  OK .wwebjs_auth/ ($copiadoSize MB copiados)" -ForegroundColor Green

# --- 7. Generar LEEME.txt -------------------------------------------
Write-Host ""
Write-Host "[3/4] Generando LEEME.txt..." -ForegroundColor Cyan

$leeme = @'
================================================================
KIT PC DEDICADA - Bot WhatsApp Coopertrans Movil
================================================================

Que hay en esta carpeta:
  - serviceAccountKey.json   Credenciales Firebase (secret).
  - .env                     Config del bot (secret).
  - .wwebjs_auth/            Sesion WhatsApp YA escaneada
                             (evita tener que reescanear el QR).

================================================================
PASO A PASO EN LA PC NUEVA
================================================================

1) Instalar Node.js 18+ y Git for Windows
   - https://nodejs.org
   - https://git-scm.com/download/win
   Despues abrir un PowerShell NUEVO y verificar:
       node --version
       git --version

2) Clonar el repo en C:\
   PowerShell normal:
       cd C:\
       git clone https://github.com/rodriguezreysantiago/logistica_app_profesional.git coopertrans_movil
       cd coopertrans_movil\whatsapp-bot
       npm install

   (npm install baja Chromium ~150 MB, tarda varios min la 1ra vez.)

3) Copiar los 3 archivos de esta carpeta al repo clonado:
       serviceAccountKey.json   →  C:\coopertrans_movil\
       .env                     →  C:\coopertrans_movil\whatsapp-bot\
       .wwebjs_auth\            →  C:\coopertrans_movil\whatsapp-bot\

   IMPORTANTE: la sesion .wwebjs_auth ya esta escaneada — al copiarla
   el bot arranca sin pedir QR. NO BORRARLA.

4) Instalar el servicio en modo 24/7
   PowerShell COMO ADMINISTRADOR:
       cd C:\coopertrans_movil\whatsapp-bot
       Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
       .\scripts\instalar_servicio.ps1 -Auto

5) Configurar Windows para 24/7
   PowerShell COMO ADMINISTRADOR:
       .\scripts\setup_pc_24x7.ps1

6) Instalar el AUTO-UPDATE (recomendado)
   PowerShell COMO ADMINISTRADOR:
       .\scripts\instalar_auto_update.ps1

   Esto agrega una Scheduled Task que cada 5 min:
     - Hace git fetch + git pull si hay commits nuevos en whatsapp-bot/**
     - npm install si package.json cambio
     - Restart-Service CoopertransMovilBot
     - Smoke test post-restart
   A partir de aca, NO hace falta entrar mas a esta PC para deployar
   cambios del bot — solo se pushea desde la PC de trabajo y se
   actualiza solo en < 5 min.

   Log del auto-update: logs\auto_update.log

7) Verificar que arranco
       Get-Service CoopertransMovilBot       # Status: Running
       Get-Content logs\bot.out.log -Tail 30 # buscar "WhatsApp listo para enviar"
       Get-ScheduledTask -TaskName CoopertransMovilBotAutoUpdate  # Ready

================================================================
APAGAR EL BOT EN LA PC VIEJA
================================================================

ANTES de arrancar el bot en la PC nueva, asegurate de detenerlo en
la PC vieja para que no corran 2 a la vez (sino se duplican los
mensajes y WhatsApp puede banear el numero):

   Stop-Service CoopertransMovilBot

Y para que NO arranque al proximo boot de la PC vieja:
   Set-Service CoopertransMovilBot -StartupType Manual

================================================================
DOCUMENTACION COMPLETA
================================================================

docs\SETUP_PC_DEDICADA_BOT.md (en el repo)

Incluye troubleshooting, backup automatico de la sesion semanal,
acceso remoto, antivirus, UPS, etc.
'@

$leemePath = Join-Path $DestinoPath 'LEEME.txt'
$leeme | Out-File -FilePath $leemePath -Encoding utf8

Write-Host "  OK LEEME.txt" -ForegroundColor Green

# --- 8. Re-arrancar bot si estaba corriendo -------------------------
Write-Host ""
if ($botEstaba) {
    Write-Host "[4/4] Re-arrancando $serviceName..." -ForegroundColor Cyan
    Start-Service -Name $serviceName
    Start-Sleep -Seconds 3
    $svc = Get-Service -Name $serviceName
    if ($svc.Status -eq 'Running') {
        Write-Host "  OK bot corriendo de nuevo" -ForegroundColor Green
    } else {
        Write-Host "  WARN bot no arranco — Status=$($svc.Status). Revisar logs." -ForegroundColor Yellow
    }
} else {
    Write-Host "[4/4] No habia que re-arrancar el bot." -ForegroundColor DarkGray
}

# --- 9. Resumen ---------------------------------------------------
$totalSize = [math]::Round(
    (Get-ChildItem -Path $DestinoPath -Recurse -File -ErrorAction SilentlyContinue |
     Measure-Object Length -Sum).Sum / 1MB,
    1
)

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "OK KIT LISTO" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Carpeta:    $DestinoPath" -ForegroundColor White
Write-Host "Tamaño:    $totalSize MB" -ForegroundColor White
Write-Host ""
Write-Host "Contenido:" -ForegroundColor Cyan
Get-ChildItem -Path $DestinoPath | ForEach-Object {
    if ($_.PSIsContainer) {
        $sz = [math]::Round(
            (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
             Measure-Object Length -Sum).Sum / 1MB,
            1
        )
        Write-Host "  $($_.Name)/   ($sz MB)" -ForegroundColor White
    } else {
        $sz = [math]::Round($_.Length / 1KB, 1)
        Write-Host "  $($_.Name)   ($sz KB)" -ForegroundColor White
    }
}
Write-Host ""
Write-Host "Próximos pasos:" -ForegroundColor Yellow
Write-Host "  - Copiar la carpeta a un pendrive / OneDrive / Drive" -ForegroundColor White
Write-Host "  - Llevarla a la PC dedicada y seguir el LEEME.txt" -ForegroundColor White
Write-Host ""
Write-Host "Comprimirla a zip (opcional, para subir a Drive más rápido):" -ForegroundColor Cyan
$zipPath = "$DestinoPath.zip"
Write-Host "  Compress-Archive -Path '$DestinoPath\*' -DestinationPath '$zipPath' -Force" -ForegroundColor White
