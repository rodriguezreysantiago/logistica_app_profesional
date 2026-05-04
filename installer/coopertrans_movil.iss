; Inno Setup script para Coopertrans Móvil.
;
; Compilar con `scripts\build_installer.ps1` (toma la versión del
; pubspec.yaml y se la pasa a iscc.exe). NO compilar el .iss directo
; sin pasarle MyAppVersion.
;
; Pre-requisito (una vez en la PC que crea releases):
;   winget install JRSoftware.InnoSetup
;
; Este script asume que el build de Flutter ya está en
; build\windows\x64\runner\Release\ — correr antes:
;   flutter build windows --release

#ifndef MyAppVersion
  #error MyAppVersion no definido. Compilar via scripts\build_installer.ps1
#endif

#define MyAppName       "Coopertrans Movil"
#define MyAppExeName    "coopertrans_movil.exe"
#define MyAppPublisher  "Coopertrans"
#define MyAppURL        "https://github.com/rodriguezreysantiago/logistica_app_profesional"
#define MyAppId         "{{B6F7E8A9-1234-4567-8901-COOPERTRANSMOV}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\CoopertransMovil
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist
OutputBaseFilename=CoopertransMovil-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
WizardResizable=no

; Detectar y actualizar versión instalada limpia. Inno usa AppId como
; clave; si encuentra un install previo con el mismo AppId, lo trata
; como upgrade (cierra la app si está corriendo, reemplaza archivos).
CloseApplications=yes
RestartApplications=no

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear icono en el escritorio"; GroupDescription: "Iconos adicionales:"; Flags: checkedonce

[Files]
; Todo el output del flutter build, incluyendo data\flutter_assets, DLLs, etc.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Iniciar {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Limpiar logs y archivos temporales que la app pueda haber dejado
; en su carpeta install. La data del usuario vive en %APPDATA% y
; no se toca en uninstall (queda intacta para reinstalación futura).
Type: filesandordirs; Name: "{app}\logs"
