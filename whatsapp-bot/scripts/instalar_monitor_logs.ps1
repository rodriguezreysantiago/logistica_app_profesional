# Instala el monitor de logs en la carpeta Startup del user actual.
# Cada vez que el user loguee en Windows, se abre automaticamente la
# ventana de PowerShell con los logs del bot en vivo (tail -f).
#
# Pensado para la PC dedicada al bot - ahi el user logueado se queda
# fijo y la ventana de logs es el "dashboard" principal.
#
# El shortcut:
#  - Apunta a powershell.exe con -NoExit -ExecutionPolicy Bypass.
#  - Corre monitor_logs.ps1 (que hace tail -f de bot.out.log).
#  - Se ubica en %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
#    (ejecuta solo para este user, no afecta otros users de la PC).
#
# Para desinstalar: borrar el .lnk de esa carpeta.
#
# Uso:
#   .\instalar_monitor_logs.ps1
#
# Idempotente: se puede correr de nuevo, sobreescribe el shortcut.

$ErrorActionPreference = 'Stop'

# Path absoluto al monitor_logs.ps1 (queda hardcodeado en el shortcut).
$monitorScript = Join-Path $PSScriptRoot 'monitor_logs.ps1'
if (-not (Test-Path $monitorScript)) {
    Write-Host "ERROR No se encuentra $monitorScript" -ForegroundColor Red
    exit 1
}

# Carpeta Startup del user actual.
$startupDir = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startupDir 'CoopertransBot_Logs.lnk'

# Crear shortcut via WScript.Shell COM.
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($lnkPath)
$shortcut.TargetPath = 'powershell.exe'
$shortcut.Arguments = "-NoExit -ExecutionPolicy Bypass -File `"$monitorScript`""
$shortcut.WorkingDirectory = Split-Path $monitorScript -Parent
$shortcut.WindowStyle = 1  # 1=Normal, 3=Maximized, 7=Minimized
$shortcut.Description = 'Coopertrans Bot - Logs en vivo'
$shortcut.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
$shortcut.Save()

Write-Host ''
Write-Host '====================================================' -ForegroundColor Green
Write-Host '  Monitor de logs INSTALADO' -ForegroundColor Green
Write-Host '====================================================' -ForegroundColor Green
Write-Host ''
Write-Host "  Shortcut: $lnkPath" -ForegroundColor White
Write-Host "  Apunta a: $monitorScript" -ForegroundColor White
Write-Host ''
Write-Host '  Se va a abrir automaticamente cada vez que loguees' -ForegroundColor Cyan
Write-Host '  en este user de Windows.' -ForegroundColor Cyan
Write-Host ''
Write-Host '  Para abrirlo AHORA sin reloguear, corre:' -ForegroundColor Cyan
Write-Host "    Start-Process powershell -ArgumentList '-NoExit','-File','$monitorScript'" -ForegroundColor Gray
Write-Host ''
Write-Host '  Para desinstalar: borrar el .lnk de la carpeta Startup' -ForegroundColor DarkGray
Write-Host "    Remove-Item `"$lnkPath`"" -ForegroundColor DarkGray
Write-Host ''
