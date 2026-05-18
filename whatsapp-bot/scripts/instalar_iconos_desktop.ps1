# Crea 2 iconos en el escritorio del user actual:
#   - "Iniciar Bot WhatsApp"  -> ejecuta scripts\start_bot.ps1
#   - "Detener Bot WhatsApp"  -> ejecuta scripts\stop_bot.ps1
#
# Pensado para la PC dedicada al bot: en lugar de abrir PowerShell y
# tipear comandos, el operador hace doble click en el escritorio.
#
# Los shortcuts vienen con el flag "Run as Administrator" porque
# Start/Stop-Service requiere admin (sino el script interno hace un
# segundo UAC prompt y queda feo).
#
# El icono visual es de la libreria estandar de Windows (imageres.dll)
# para que se vea consistente con el resto del sistema:
#   - Play verde para Iniciar
#   - Stop rojo para Detener
#
# Idempotente: se puede correr de nuevo, sobreescribe los .lnk.
#
# USO:
#   .\instalar_iconos_desktop.ps1
#
# DESINSTALAR: borrar los 2 .lnk del escritorio.

$ErrorActionPreference = 'Stop'

# Paths -------------------------------------------------------------
$scriptsDir = $PSScriptRoot
$startScript = Join-Path $scriptsDir 'start_bot.ps1'
$stopScript = Join-Path $scriptsDir 'stop_bot.ps1'

foreach ($s in @($startScript, $stopScript)) {
    if (-not (Test-Path $s)) {
        Write-Host "ERROR no encuentro $s" -ForegroundColor Red
        exit 1
    }
}

$desktopDir = [Environment]::GetFolderPath('Desktop')
$lnkStart = Join-Path $desktopDir 'Iniciar Bot WhatsApp.lnk'
$lnkStop = Join-Path $desktopDir 'Detener Bot WhatsApp.lnk'

Write-Host ''
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host '  ICONOS DE ESCRITORIO - Bot WhatsApp' -ForegroundColor Cyan
Write-Host '====================================================' -ForegroundColor Cyan

# Helper: crea un .lnk + le pega el flag RunAsAdmin -----------------
#
# El flag "Run as Administrator" NO se puede setear via WScript.Shell
# directamente. La tecnica estandar es:
#   1. Crear el shortcut normal con WScript.Shell.
#   2. Leer los bytes del .lnk.
#   3. Setear bit 0x20 en el byte 0x15 (parte de LinkFlags) que es el
#      "RunAsUser" flag del formato MS-SHLLINK.
#   4. Escribir los bytes de vuelta.
#
# Probado y funcional en Windows 10/11.
function New-AdminShortcut {
    param(
        [Parameter(Mandatory)] [string]$LnkPath,
        [Parameter(Mandatory)] [string]$ScriptPath,
        [Parameter(Mandatory)] [string]$IconResource,
        [Parameter(Mandatory)] [string]$Description
    )
    # Crear shortcut basico
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($LnkPath)
    $shortcut.TargetPath = 'powershell.exe'
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $shortcut.WorkingDirectory = Split-Path $ScriptPath -Parent
    $shortcut.WindowStyle = 1  # Normal
    $shortcut.Description = $Description
    $shortcut.IconLocation = $IconResource
    $shortcut.Save()

    # Setear flag RunAsAdmin
    $bytes = [System.IO.File]::ReadAllBytes($LnkPath)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($LnkPath, $bytes)
}

# Crear "Iniciar Bot WhatsApp" --------------------------------------
Write-Host ''
Write-Host '[1/2] Creando "Iniciar Bot WhatsApp.lnk"...' -ForegroundColor Cyan
try {
    New-AdminShortcut `
        -LnkPath $lnkStart `
        -ScriptPath $startScript `
        -IconResource 'imageres.dll,98' `
        -Description 'Inicia el servicio CoopertransMovilBot (requiere admin)'
    Write-Host "  OK $lnkStart" -ForegroundColor Green
} catch {
    Write-Host "  FAIL $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Crear "Detener Bot WhatsApp" --------------------------------------
Write-Host ''
Write-Host '[2/2] Creando "Detener Bot WhatsApp.lnk"...' -ForegroundColor Cyan
try {
    New-AdminShortcut `
        -LnkPath $lnkStop `
        -ScriptPath $stopScript `
        -IconResource 'imageres.dll,100' `
        -Description 'Detiene el servicio CoopertransMovilBot (requiere admin)'
    Write-Host "  OK $lnkStop" -ForegroundColor Green
} catch {
    Write-Host "  FAIL $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '====================================================' -ForegroundColor Green
Write-Host '  ICONOS INSTALADOS' -ForegroundColor Green
Write-Host '====================================================' -ForegroundColor Green
Write-Host ''
Write-Host '  Ya tenes 2 iconos en el escritorio:' -ForegroundColor White
Write-Host '    - Iniciar Bot WhatsApp  (icono play verde)' -ForegroundColor Green
Write-Host '    - Detener Bot WhatsApp  (icono stop rojo)' -ForegroundColor Red
Write-Host ''
Write-Host '  Doble click en cada uno te pide UAC (admin) y ejecuta' -ForegroundColor Cyan
Write-Host '  el script correspondiente. Iniciar tambien abre una' -ForegroundColor Cyan
Write-Host '  ventana con los logs en vivo.' -ForegroundColor Cyan
Write-Host ''
Write-Host '  Para desinstalar: borrar los .lnk del escritorio.' -ForegroundColor DarkGray
Write-Host ''
