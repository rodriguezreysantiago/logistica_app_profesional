# Estado del proyecto — S.M.A.R.T. Logística

Documento de handoff para retomar trabajo en otra máquina o en una conversación nueva con Claude. Última actualización: **2026-04-28** (sesión nocturna: refactor cross-platform + sprints 1-5 de UX/calidad).

---

## 1. Qué es la app

App Flutter multiplataforma (Android / iOS / Web / Windows) para gestión de flota de la empresa de transporte **Vecchi / Sucesión Vecchi**, en Bahía Blanca. Maneja:

- **Personal** (choferes y administrativos), con sus papeles vencibles (licencia, preocupacional, ART, manejo defensivo, F.931, seguro de vida, sindicato).
- **Flota**: tractores y enganches (BATEAS, TOLVAS, BIVUELCOS, TANQUES, ACOPLADOS legacy), con sus vencimientos (RTO, Seguro, Extintor Cabina, Extintor Exterior — los 2 extintores solo para tractores).
- **Checklists mensuales** del chofer sobre tractor y enganche.
- **Sistema de revisiones**: el chofer sube fecha + comprobante de un trámite renovado, el admin aprueba/rechaza desde "Revisiones Pendientes".
- **Auditoría de vencimientos** (60 días): admin ve qué documentos están por vencer ordenados por urgencia, con badge de color, y desde ahí puede mandarle WhatsApp pre-armado al chofer responsable.
- **Reportes Excel** de flota y de novedades de checklist.
- **Integración Volvo Connect** para los tractores Volvo: trae odómetro, % combustible, autonomía estimada en km. Sincronización automática cada 60 segundos vía `AutoSyncService`.

## 2. Tech stack

- **Flutter 3.x** + Dart 3.0+
- **Firebase**: Firestore (datos), Storage (archivos), opcionalmente Cloud Messaging (no usado aún).
- **State management**: `provider` con `ProxyProvider`/`ChangeNotifierProxyProvider` cadenas.
- **HTTP**: `dio` (a Volvo Connect API).
- **Auth**: DNI + contraseña hasheada con Bcrypt (con migración silenciosa desde SHA-256 legacy). NO usa Firebase Auth todavía.
- **Otros**: `excel`, `intl`, `flutter_local_notifications`, `image_picker`, `file_picker`, `pdfrx`, `share_plus`, `url_launcher`, `flutter_secure_storage` (no aún), `crypto`/`bcrypt`.
- **Plataformas activas**: Windows desktop (uso del admin desde la oficina) y Android (choferes).

## 3. Arquitectura

```
lib/
├── core/                          # Constantes, servicios cross-feature
│   ├── constants/
│   │   ├── app_constants.dart     # Rutas, colecciones, roles, tipos vehículo
│   │   └── vencimientos_config.dart  # Specs de vencimientos por tipo
│   └── services/
│       ├── auto_sync_service.dart # Cron Volvo (Provider singleton)
│       ├── notification_service.dart
│       ├── prefs_service.dart     # SharedPreferences (sesión actual)
│       └── storage_service.dart
├── features/
│   ├── admin_dashboard/           # Panel de menús del admin
│   ├── auth/                      # Login (DNI + bcrypt)
│   ├── checklist/                 # Checklists mensuales
│   ├── employees/                 # Personal: alta, lista, detalle, perfil
│   ├── expirations/               # Mis Vencimientos / auditoría / editor
│   ├── home/                      # Panel principal post-login
│   ├── reports/                   # Reportes Excel
│   ├── revisions/                 # Sistema de revisión admin/chofer
│   ├── sync_dashboard/            # Observabilidad del AutoSync Volvo
│   └── vehicles/                  # Flota: alta, lista, detalle, telemetría
├── routing/app_router.dart
├── shared/
│   ├── utils/                     # FechaInputFormatter, WhatsAppHelper, formatters
│   └── widgets/                   # AppCard, AppListPage, AppScaffold, fecha_dialog…
├── firebase_options.dart
└── main.dart
```

**Patrón clave para Volvo**: `VolvoApiService` → `VehiculoRepository` → `VehiculoManager` → `VehiculoProvider`. Todo en el provider tree de `main.dart` con `ProxyProvider2`.

## 4. Convenciones importantes (NO romper)

- **Nombres de choferes en Firestore**: campo `NOMBRE` con formato `APELLIDO NOMBRE SEGUNDO_NOMBRE`. El saludo siempre toma `partes[1]` (segundo token = nombre real). Si solo hay un token, usamos saludo genérico para evitar llamar al chofer por apellido.
- **DNIs**: `String` (sin guiones, sin espacios). Es el `documentId` en `EMPLEADOS`.
- **Patentes**: `String` en mayúscula. Son el `documentId` en `VEHICULOS`.
- **Fechas en Firestore**: pueden venir como `Timestamp` (nuevo) o `String` ISO (legacy). El helper `_parseDate` en cada modelo soporta ambos.
- **Campos de vencimiento**: convención `VENCIMIENTO_<NOMBRE>` y `ARCHIVO_<NOMBRE>`. El sistema de revisiones depende de esta convención (`replaceAll('VENCIMIENTO_', 'ARCHIVO_')`).
- **Tipos de vehículo**: definidos en `AppTiposVehiculo` (centralizado). Sumar uno nuevo → solo se edita esa lista.
- **Vencimientos por tipo**: definidos en `AppVencimientos.tractor` y `AppVencimientos.enganche`. Sumar uno nuevo → solo se edita esa lista, las pantallas iteran.
- **Texto de fechas en input**: SIEMPRE usar el helper `pickFecha(...)` (`shared/widgets/fecha_dialog.dart`) que muestra dialog con TextField DD/MM/AAAA. NO usar `showDatePicker` (el cliente lo odia).
- **Roles**: `ADMIN` y `USUARIO` (no "CHOFER").
- **Rutas**: definidas en `AppRoutes` (`app_constants.dart`), no hardcodear strings.

## 5. Decisiones técnicas con su razón

| Decisión | Por qué |
|---|---|
| Auth propia con bcrypt en lugar de Firebase Auth | Heredado. Migración a Firebase Auth pendiente; necesaria para activar `firestore.rules` |
| Firestore queries con `orderBy` en cliente para `AVISOS_VENCIMIENTOS` | Evitar fricción del índice compuesto que Firestore pediría crear manualmente |
| `AutoSyncService` en provider tree | Su lifecycle (start/stop) lo maneja Provider, no el state del root widget |
| Volvo Connect via `additionalContent=VOLVOGROUPSNAPSHOT` | Sin ese flag el response NO trae `fuelLevel` ni `estimatedDistanceToEmpty` |
| `estimatedDistanceToEmpty` lo busca en `snapshotData.volvoGroupSnapshot` | El path real para diésel; los `chargingStatusInfo` son para EVs |
| Click-to-Chat (`wa.me`) en lugar de Twilio | Empresa chica, no se justifica costo de WhatsApp Business API por ahora |
| Campo "Preocupacional" en UI, campos `VENCIMIENTO_PREOCUPACIONAL` en Firestore | Migración completa hecha el 2026-04-28 vía `scripts/migrar_psicofisico_a_preocupacional.py` |

## 6. Lo que ya está hecho

### Auditoría inicial (completa)
- Reporte: `AUDITORIA_2026-04-28.md`
- Hallazgos críticos resueltos: credenciales Volvo hardcodeadas (sacadas), `secrets.json` confirmado fuera de git, `mounted` checks en formularios.
- Hallazgos pendientes: `firestore.rules` no existe (requiere migrar a Firebase Auth primero).

### Features nuevas
- **Telemetría Volvo en pantalla del chofer y admin**: odómetro, % combustible (con barra), autonomía km. Solo se muestran en tractores con datos válidos.
- **Panel diagnóstico Volvo** (botón 🐛 en ficha del vehículo): muestra request, status, JSON crudo, análisis de campos críticos (✓/✗).
- **Sync Dashboard** ampliado: eventos por unidad (último 50), histórico de ciclos (último 15), botón "ejecutar ahora", motivos de skip detallados.
- **Tipos de vehículo nuevos**: BIVUELCO, TANQUE (suman a BATEA, TOLVA, ACOPLADO legacy).
- **Vencimientos nuevos en tractores**: Extintor Cabina, Extintor Exterior. Centralizados en `AppVencimientos`.
- **MAIL** y **TELÉFONO** editables en gestión de personal y visibles en mi perfil.
- **Foto/PDF reemplazable** desde admin para los papeles del chofer (sin pasar por flujo de revisión).
- **Botón "Avisar por WhatsApp"** en cada vencimiento en auditoría: arma URL `wa.me` con mensaje pre-armado según días restantes y firma "_mensaje automático del sistema_".
- **Historial de avisos por vencimiento**: colección `AVISOS_VENCIMIENTOS` registra cada envío. Bloque colapsable en el editor muestra contador + último.
- **Reporte Checklist abre en Excel directo** en Windows (antes solo compartía).
- **Calendario reemplazado por input DD/MM/AAAA**: dialog compacto con validación inline.
- **Migración total `Psicofísico` → `Preocupacional`**: campos en Firestore renombrados, código actualizado, propiedades del modelo, mensajes de WhatsApp actualizados.
- **Refactor cross-platform de uploads (sesión 2026-04-28 PM)**: `StorageService.subirArchivo` ahora trabaja con `Uint8List` + nombre original en lugar de `dart:io.File` (usa `putData` en vez de `putFile`). Todos los callers (`user_mi_perfil`, `revision_service`, `vencimiento_editor_sheet`, `admin_personal_lista`, `admin_vehiculo_form`, `user_mis_vencimientos`) pasan ahora `xfile.readAsBytes()` o `FilePicker(withData: true)`. Resultado: la app compila y corre en Chrome / Web sin crashear en flujos de subida. `flutter analyze` → 0 issues.
- **Reportes Excel con guard de Web**: `report_flota` y `report_checklist` muestran snackbar "solo disponibles en Windows y Android" en `kIsWeb` antes de tocar `dart:io`.
- **Permisos Android 13+**: agregados `POST_NOTIFICATIONS` (runtime permission para `flutter_local_notifications`) y `CAMERA` + `<uses-feature>` opcional al `AndroidManifest.xml`.

### Sprints 1-5 de UX y calidad (2026-04-28 PM)

**Sprint 1 — Confirmaciones destructivas + feedback de éxito**
- Nuevo `AppConfirmDialog` (`shared/widgets/app_confirm_dialog.dart`) reutilizable con modo `destructive: true` (botón rojo).
- DESVINCULAR equipo de chofer ahora pide confirmación destructiva con copy clara + emite snackbar de éxito tras `batch.commit`.
- RECHAZAR revisión ahora pide confirmación destructiva (antes borraba el comprobante del chofer del Storage sin avisar).
- Auditados todos los `update`/`set`/`delete`/`batch.commit` del admin: alta de chofer, alta de vehículo, edición de campos, aprobar revisión, etc., ya tenían feedback adecuado.

**Sprint 2 — Sistema unificado de feedback e inputs**
- `AppFeedback` (`shared/utils/app_feedback.dart`) — paleta semántica (`success`, `error`, `warning`, `info`) con ícono + color + duración consistentes. Versión `*On(messenger, msg)` para casos post-await.
- `AppLoadingDialog` (`shared/widgets/app_loading_dialog.dart`) — modal de "cargando…" con `show(context)` / `hide(navigator)`.
- `DigitOnlyFormatter` (`shared/utils/digit_only_formatter.dart`) — filtro de dígitos con `maxLength` opcional. Aplicado a DNI, CUIL, TELÉFONO, año de fabricación, KM en todos los formularios. La red real contra paste / desktop, no solo `keyboardType: number`.
- 46 SnackBars dispersos migrados a `AppFeedback`. 2 loadings ad-hoc migrados a `AppLoadingDialog`. `keyboardType: emailAddress` en mail.

**Sprint 3 — Pulido visual y constantes**
- "Nuevo Legajo" → "Nuevo chofer" en el form de alta.
- Tooltips en FABs (admin de personal y flota).
- Iconografía de vencimientos unificada a `Icons.event_note` en 5 lugares.
- `AppColors` (`shared/constants/app_colors.dart`) — paleta centralizada (semánticos + accent + background/surface + text). Documentado: usar `Theme.of(context)` para colores del tema; `AppColors` para colores semánticos puntuales; **no** hardcodear `Colors.greenAccent` en código nuevo.

**Sprint 4 — Quick wins de productividad**
- **Foto del vehículo**: campo `ARCHIVO_FOTO` en `VEHICULOS`. Avatar circular en `_VehiculoCard` (mismo patrón que `_EmpleadoCard`). Bloque de "Cambiar foto / Agregar foto" en el form de edición.
- **Búsqueda Ctrl+K**: nuevo `CommandPalette` (`shared/widgets/command_palette.dart`) estilo VS Code. Indexa choferes y vehículos con fetch one-shot, filtro local mientras tipeás. Atajo `Ctrl+K` / `Cmd+K` en `admin_shell.dart` + IconButton de lupa en la AppBar. Funciones públicas top-level `abrirDetalleChofer(context, dni)` y `abrirDetalleVehiculo(context, patente, data)` para que features externos puedan abrir detalles.
- **Calendario de vencimientos**: package `table_calendar: ^3.1.2`. Pantalla `admin_vencimientos_calendario_screen.dart` con vista mensual, badge contador por día con color según urgencia (rojo ≤7d, naranja ≤30d, verde >30d). Tap en día abre la lista de vencimientos del día. Nueva ruta `/vencimientos_calendario` + tile primero en el menú.
- **OCR de comprobantes**: package `google_mlkit_text_recognition: ^0.13.1`. `OcrService` (`shared/utils/ocr_service.dart`) con `detectarFecha(path)` solo en Android/iOS. Estrategia: regex multi-formato (`/`, `-`, `.`) + filtra años 2020-2050 + devuelve la **fecha más lejana** (la de vencimiento, no la de emisión). Botón "Detectar fecha desde foto" en el dialog del chofer cuando `OcrService.soportado`.

**Sprint 5 — Calidad y trazabilidad**
- **`AuditLog`** (`core/services/audit_log_service.dart`): bitácora de acciones del admin en colección `AUDITORIA_ACCIONES`. Helper `registrar(accion, entidad, entidadId, detalles)` con enum `AuditAccion` cerrado. Fire-and-forget. Integrado en alta de chofer, alta de vehículo, edición de campo, asignar/desvincular equipo, aprobar/rechazar revisión.
- **Crashlytics + `AppLogger`** (`core/services/app_logger.dart`): dep `firebase_crashlytics: ^4.1.3`. `AppLogger.init()` engancha `FlutterError.onError` y `PlatformDispatcher.onError` solo en Android/iOS; en Web/Windows cae a `debugPrint`. En debug `setCrashlyticsCollectionEnabled(false)`. Métodos `recordError(error, stack, reason, fatal)` y `log(msg)` para `try/catch` puntuales. `main.dart` actualizado.
- **Tests unitarios**: 38 tests verdes. `password_hasher_test.dart` (8), `aviso_vencimiento_builder_test.dart` (13), `ocr_service_test.dart` (14), `widget_test.dart` placeholder. `flutter analyze` → 0 issues. `flutter test` → all passed.

### Bugs arreglados destacados
- DNI vacío al solicitar cambio de equipo (`findAncestorStateOfType` fallaba dentro de bottom sheet → propagación explícita).
- Aprobar revisión con campos vacíos crashearba (`document path must be a non-empty string`) → guards defensivos + auto-borrado de solicitudes corruptas.
- Backspace en input de fecha "no funcionaba" en Windows → cursor del formatter ahora se preserva en posición lógica.
- Volvo no devolvía combustible/autonomía → faltaba `additionalContent` en el query y los paths anidados estaban mal.
- `Scrollbar` sin controller en JSON viewer del diagnóstico → controller dedicado.

## 7. Pendientes / roadmap

### Bloqueante de plataforma — iOS
- **`ios/` no existe en el repo**. La app no es compilable para iPhone hoy. Para habilitarlo:
  1. Conseguir una Mac (compilar iOS no se puede desde Windows; ni siquiera con codemagic / cloud build se evita el setup inicial).
  2. Cuenta Apple Developer ($99/año) si se quiere distribuir.
  3. `flutter create --platforms=ios .` desde la raíz del proyecto.
  4. Bajar `GoogleService-Info.plist` de Firebase Console (proyecto `logisticaapp-e539a` → iOS app) y dejarlo en `ios/Runner/`.
  5. Editar `ios/Runner/Info.plist` con los permisos: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `LSApplicationQueriesSchemes` (para `wa.me` con `url_launcher`).
  6. `Podfile`: `platform :ios, '13.0'` o superior (Firebase requiere ≥13).
  7. Cambiar el bundle ID a algo real, no `com.example.*` (ej. `ar.com.smartlogistica.flota`).

### Próximo paso lógico
- **Activar Crashlytics nativo en Android** (mientras tanto el AppLogger cae a debugPrint sin romper). Sumar:
  - En `android/build.gradle.kts`: `classpath 'com.google.firebase:firebase-crashlytics-gradle:3.0.2'`.
  - En `android/app/build.gradle.kts`: `apply plugin: 'com.google.firebase.crashlytics'`.
  - Probar lanzando una excepción manual desde la app de release.
- **Dashboard / panel home del admin** con métricas vivas (choferes activos, unidades, vencimientos próximos, revisiones pendientes, % checklists OK del último mes). Cuando arranca el día el admin ve "estado de la operación" sin tener que abrir cada sección. Costo medio (1-2 días), impacto alto.
- **Mails automáticos escalonados** por vencimientos (30/15/7 días + diario al vencer). Requiere:
  - Plan Blaze de Firebase (Cloud Functions con scheduler).
  - Proveedor: SendGrid (free 100/día) o Resend (free 3000/mes) o SMTP de Workspace.
  - Destinatario: aún por definir (chofer, admin, ambos).

### Roadmap medio plazo (auditoría)
1. Migrar a **Firebase Auth** (custom token desde Cloud Function) para poder habilitar `firestore.rules`. **Bloqueante** de varios items: vista de invitado del dueño, rate limiting confiable, firestore.rules reales.
2. **Rate limiting** en login (Cloud Function + colección `LOGIN_ATTEMPTS`).
3. Mover credenciales Volvo Connect a Cloud Function proxy (hoy se inyectan vía `--dart-define-from-file=secrets.json`, OK para dev).
4. **`flutter_secure_storage`** para sesión en lugar de SharedPreferences plano.
5. Refactor: `admin_personal_lista_screen.dart` (1200+ líneas con audit log y formatters; sigue creciendo).
6. **Modo offline para checklist** del chofer (sqflite/Hive + cola de sync). Útil en ruta sin señal.
7. **Biometría para login del chofer** (`local_auth`, huella en mobile).
8. **Vista de invitado del dueño** — link público read-only con dashboard. Requiere Firebase Auth primero.

### Roadmap UI/UX largo
- **Push notifications agendadas** al chofer ("Tu licencia vence en 5 días") sin necesidad de WhatsApp del admin. `flutter_local_notifications` ya está instalado.
- **Búsqueda Ctrl+K**: extender para indexar revisiones pendientes (hoy solo choferes y vehículos).
- **`AppColors`** — migración incremental: cada vez que se toque un archivo, reemplazar `Colors.greenAccent` / `Colors.redAccent` etc. por las constantes centralizadas.

### Roadmap largo plazo (Volvo)
- **Anti-robo nocturno** con `wheelBasedSpeed > 0` fuera de horario operativo + push notification al admin.
- **Mantenimiento preventivo** vía endpoint VDDS `serviceDistance`.
- **Alertas de conducción** (descanso, conducción continua excedida) — requiere taquógrafo digital activo en los camiones.

## 8. Setup en una máquina nueva

### Pre-requisitos
- Flutter SDK 3.0+
- Python 3.10+ (solo si vas a correr scripts de migración)
- Cuenta Firebase del proyecto `logisticaapp-e539a`
- Editor: VS Code con extensiones Dart + Flutter

### Pasos
```bash
# 1. Clonar y entrar
git clone <url-del-repo> logistica_app_profesional
cd logistica_app_profesional

# 2. Recrear archivos sensibles (NO están en git, copiá desde Bitwarden / Drive privado)
#    - secrets.json     (credenciales Volvo Connect)
#    - serviceAccountKey.json  (solo si vas a correr scripts Python de admin)

# 3. Instalar dependencias Flutter
flutter pub get

# 4. (Opcional) Instalar deps Python para scripts admin
pip install firebase-admin

# 5. Correr la app (Windows)
flutter run -d windows --dart-define-from-file=secrets.json
# (en VS Code F5 ya tiene el flag configurado en .vscode/launch.json)
```

### Archivos sensibles que necesitás recrear
- `secrets.json` — formato en `secrets.example.json`. Contiene `VOLVO_USERNAME` y `VOLVO_PASSWORD`.
- `serviceAccountKey.json` — bajar de Firebase Console → Project Settings → Service Accounts → Generate new private key.

## 9. Cómo retomar contexto en Claude / Cowork

Si abrís una conversación nueva en otra máquina (Cowork no sincroniza historial entre desktops), **pegá el siguiente prompt al iniciar** para que tenga el contexto:

> Hola Claude. Vengo trabajando en una app Flutter de gestión de flota llamada **logistica_app_profesional** (S.M.A.R.T. Logística, empresa Vecchi en Bahía Blanca). Antes de empezar, leé `ESTADO_PROYECTO.md` y `AUDITORIA_2026-04-28.md` que están en la raíz del repo — ahí tenés el contexto completo: arquitectura, convenciones, lo que está hecho, lo que queda pendiente y las decisiones tomadas con sus razones. Trabajamos siguiendo esas convenciones (input de fecha DD/MM/AAAA, helper `pickFecha`, listas centralizadas en `AppVencimientos` y `AppTiposVehiculo`, mensajes con firma "_mensaje automático del sistema_", etc). El próximo paso pendiente es <X>. ¿Listo para arrancar?

Reemplazá `<X>` con lo que quieras hacer ese día.

## 10. Comandos útiles que uso seguido

```bash
# Correr la app en debug
flutter run -d windows --dart-define-from-file=secrets.json

# Build de release Windows
flutter build windows --release --dart-define-from-file=secrets.json

# Análisis estático
flutter analyze

# Migración Firestore (idempotente, soporta --dry-run)
python scripts/migrar_psicofisico_a_preocupacional.py --dry-run

# Ver últimos commits
git log --oneline -10
```

---

*Generado el 2026-04-28 — actualizar este archivo cuando se completen pendientes grandes o se sumen features importantes.*
