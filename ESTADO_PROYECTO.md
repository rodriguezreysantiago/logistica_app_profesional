# Estado del proyecto — S.M.A.R.T. Logística

Documento de handoff para retomar trabajo en otra máquina o en una conversación nueva con Claude. Última actualización: **2026-04-29** (revisión profunda post-pull desde casa, completado documentación de bot WhatsApp + sesión seguridad + sprints 4-8 + refactor `_Actualizar` → `EmpleadoActions` + AUDITORIA_ACCIONES movido al server).

Sesiones recientes:
- **2026-04-29 (medianoche)** — `flutter_secure_storage` para `PrefsService`: migrados `dni`/`nombre`/`rol`/`isLoggedIn`/`lastDni` desde `SharedPreferences` (texto plano) al almacén seguro nativo (DPAPI en Windows, Keychain en iOS, KeyStore + EncryptedSharedPreferences en Android). API pública sigue **sync** (cache en memoria al `init()`) — los 13 call sites no cambian. Migración one-shot idempotente desde SharedPreferences viejo al primer arranque después del upgrade.
- **2026-04-29 (noche tarde)** — `AUDITORIA_ACCIONES` movido al server: nueva Cloud Function callable `auditLogWrite` (Gen2, valida rol ADMIN del JWT + whitelist de acciones/entidades + límite 10KB en `detalles`). `AuditLogService` cliente reescrito para llamar al callable via Dio + Bearer ID token (mismo patrón que `loginConDni`/`volvoProxy`, fire-and-forget). Rule de `AUDITORIA_ACCIONES` cerrada a `read: if isAdmin(); write: if false`. **Deployado y operativo** (functions + rules + IAM `allUsers` invoker en Cloud Run). Probado: edición de chofer registra correctamente con `admin_dni`/`admin_nombre` tomados del JWT.
- **2026-04-29 (noche)** — refactor `admin_personal_lista_screen.dart`: extracción de `_Actualizar` (clase namespace) → `lib/features/employees/services/empleado_actions.dart` como `EmpleadoActions`. Archivo lista pasa de 1295 a 727 líneas. `flutter analyze` limpio. Workaround del bug del sandbox (null bytes residuales tras Edit grande) aplicado vía `python3 + rstrip(b'\x00')`.
- **2026-04-29 (PM tarde)** — branch `feature/firebase-auth`: setup Cloud Functions + `loginConDni` callable + adaptación de `AuthService` + `AuthGuard` con doble check + cierre real de `firestore.rules`/`storage.rules` con `request.auth.uid` y `isAdmin()` por custom claim.
- **2026-04-29 (PM)** — revisión profunda del estado real tras pull, completado este documento con módulos no documentados (bot WhatsApp, audit log, OCR, calendario).
- **2026-04-29 (mañana)** — auditoría de seguridad: rotación de key Firebase, limpieza git history, fixes en bot Node.js (sanitización path, match estricto teléfono, backoff exponencial, grace shutdown), `firestore.rules` + `storage.rules` publicadas.
- **2026-04-28 (PM/noche)** — refactor cross-platform + sprints 1-8: UX/calidad + dashboard + reporte consumo con histórico + bot de WhatsApp Fase 1-3.
- **2026-04-28 (mañana)** — auditoría inicial (`AUDITORIA_2026-04-28.md`).

---

## 1. Qué es la app

App Flutter multiplataforma (Android / iOS / Web / Windows) para gestión de flota de la empresa de transporte **Vecchi / Sucesión Vecchi**, en Bahía Blanca. Maneja:

- **Personal** (choferes y administrativos), con sus papeles vencibles (licencia, **preocupacional**, ART, manejo defensivo, F.931, seguro de vida, sindicato).
- **Flota**: tractores y enganches (BATEAS, TOLVAS, BIVUELCOS, TANQUES, ACOPLADOS legacy), con sus vencimientos (RTO, Seguro, Extintor Cabina, Extintor Exterior — los 2 extintores solo para tractores). Foto del vehículo opcional.
- **Checklists mensuales** del chofer sobre tractor y enganche.
- **Sistema de revisiones**: el chofer sube fecha + comprobante de un trámite renovado, el admin aprueba/rechaza desde "Revisiones Pendientes".
- **Auditoría de vencimientos** (60 días): admin ve qué documentos están por vencer ordenados por urgencia, con badge de color, y desde ahí puede mandarle WhatsApp pre-armado (Click-to-Chat) al chofer. También vista de **calendario mensual**.
- **Bot WhatsApp automatizado** (proyecto Node.js externo, escucha la cola en Firestore): el admin encola → el bot envía con anti-throttle → el chofer responde con foto del comprobante → el bot intenta asociarlo automáticamente, y si no puede, lo deja en una bandeja para que el admin lo despache.
- **Reportes Excel**: flota, novedades de checklist y consumo (con histórico real si disponible).
- **Integración Volvo Connect** para los tractores Volvo: trae odómetro, % combustible, autonomía estimada en km. Sincronización automática cada 60 segundos vía `AutoSyncService`. Snapshot diario a `TELEMETRIA_HISTORICO` para el reporte de consumo.
- **Búsqueda global Ctrl+K** estilo VS Code para encontrar choferes / unidades / trámites.

## 2. Tech stack

- **Flutter 3.x** + Dart 3.0+
- **Firebase**: Firestore (datos), Storage (archivos), Crashlytics (errores en mobile), Cloud Messaging (no usado aún).
- **State management**: `provider` con `ProxyProvider`/`ChangeNotifierProxyProvider` cadenas.
- **HTTP**: `dio` (a Volvo Connect API).
- **Auth**: Firebase Auth con custom token. La Cloud Function `loginConDni` (en `functions/src/index.ts`) recibe DNI+password, valida server-side contra `EMPLEADOS` (bcrypt o SHA-256 legacy con migración silenciosa) y emite un custom token con `uid = DNI` y custom claims `{ rol, nombre }`. El cliente hace `signInWithCustomToken(token)`.
- **Calendario**: `table_calendar: ^3.1.x`.
- **OCR**: `google_mlkit_text_recognition` on-device (Android/iOS solamente).
- **Otros**: `excel`, `intl`, `flutter_local_notifications`, `image_picker`, `file_picker`, `pdfrx`, `share_plus`, `url_launcher`, `crypto`/`bcrypt`, `timezone`, `path_provider`, `shared_preferences`, `ffi`/`win32` (transitivas Windows).
- **Plataformas activas**: Windows desktop (admin desde la oficina) y Android (choferes). Web compila pero los reportes Excel se desactivan ahí (toca `dart:io`).
- **Bot WhatsApp**: proyecto Node.js separado en `whatsapp-bot/` con `firebase-admin`, lee/escribe Firestore vía Admin SDK (bypasea las rules).

## 3. Arquitectura

```
logistica_app_profesional/
├── lib/
│   ├── core/
│   │   ├── constants/
│   │   │   ├── app_constants.dart          # Rutas, colecciones, roles, tipos vehículo
│   │   │   └── vencimientos_config.dart    # Specs de vencimientos por tipo
│   │   ├── services/
│   │   │   ├── app_logger.dart             # Logger central (Crashlytics en mobile)
│   │   │   ├── audit_log_service.dart      # Bitácora AUDITORIA_ACCIONES
│   │   │   ├── auto_sync_service.dart      # Cron Volvo (Provider singleton)
│   │   │   ├── notification_service.dart
│   │   │   ├── prefs_service.dart          # SharedPreferences (sesión)
│   │   │   └── storage_service.dart        # Subida a Storage (cross-platform)
│   │   └── theme/app_theme.dart
│   ├── features/
│   │   ├── admin_dashboard/                # Panel admin + shell con Ctrl+K
│   │   ├── auth/                           # Login (DNI + bcrypt)
│   │   ├── checklist/                      # Checklists mensuales
│   │   ├── employees/                      # Personal
│   │   ├── expirations/                    # Vencimientos + auditoría + calendario
│   │   ├── home/                           # Panel principal post-login
│   │   ├── reports/                        # Reportes Excel (flota / checklist / consumo)
│   │   ├── revisions/                      # Sistema de revisión admin/chofer
│   │   ├── sync_dashboard/                 # Observabilidad del AutoSync Volvo
│   │   ├── vehicles/                       # Flota + diagnóstico Volvo
│   │   └── whatsapp_bot/                   # Cola y bandeja del bot Node.js
│   ├── routing/app_router.dart
│   ├── shared/
│   │   ├── constants/app_colors.dart       # Paleta semántica
│   │   ├── utils/
│   │   │   ├── app_feedback.dart           # SnackBars semánticos
│   │   │   ├── digit_only_formatter.dart
│   │   │   ├── fecha_input_formatter.dart  # DD/MM/AAAA
│   │   │   ├── formatters.dart             # AppFormatters (fechas, CUIL, KM, días)
│   │   │   ├── ocr_service.dart            # ML Kit on-device
│   │   │   ├── password_hasher.dart        # Bcrypt + SHA-256 dual
│   │   │   ├── upper_case_formatter.dart
│   │   │   └── whatsapp_helper.dart        # wa.me click-to-chat
│   │   └── widgets/
│   │       ├── app_*                       # AppCard, AppListPage, AppScaffold...
│   │       ├── app_confirm_dialog.dart     # Confirmaciones (modo destructivo)
│   │       ├── app_loading_dialog.dart     # Modal "cargando..."
│   │       ├── command_palette.dart        # Búsqueda Ctrl+K
│   │       ├── fecha_dialog.dart           # pickFecha(...)
│   │       └── guards/                     # AuthGuard, RoleGuard, AdminGuard
│   ├── firebase_options.dart
│   └── main.dart                           # Provider tree completo
├── whatsapp-bot/                           # PROYECTO NODE.JS SEPARADO
│   ├── src/
│   ├── package.json
│   └── README.md
├── scripts/                                # Scripts Python (migraciones, carga inicial)
├── firestore.rules                         # Reglas de seguridad Firestore
├── storage.rules                           # Reglas de seguridad Storage
├── firebase.json
├── secrets.json                            # NO en git — credenciales Volvo
├── secrets.example.json
├── serviceAccountKey.json                  # NO en git — admin SDK
├── pubspec.yaml
├── ESTADO_PROYECTO.md                      # ESTE archivo
└── AUDITORIA_2026-04-28.md
```

**Patrón Volvo**: `VolvoApiService` → `VehiculoRepository` → `VehiculoManager` → `VehiculoProvider` (todos en provider tree de `main.dart` con `ProxyProvider2`).

**Patrón bot WhatsApp**: `[App Flutter]` escribe a `Firestore: COLA_WHATSAPP` → `[Bot Node.js]` con Admin SDK escucha cambios → procesa con anti-throttle → manda WhatsApp → si el chofer responde con comprobante, el bot intenta auto-asociarlo o lo deja en `RESPUESTAS_BOT_AMBIGUAS` para que el admin despache desde la bandeja.

## 4. Convenciones importantes (NO romper)

### Datos
- **Nombres de choferes**: campo `NOMBRE` con formato `APELLIDO NOMBRE SEGUNDO_NOMBRE`. El saludo siempre toma `partes[1]` (nombre real). Si solo hay un token, saludo genérico.
- **DNIs**: `String` sin guiones/espacios. `documentId` en `EMPLEADOS`.
- **Patentes**: `String` mayúscula. `documentId` en `VEHICULOS`.
- **Teléfonos**: helper `WhatsAppHelper._normalizarNumeroAr` acepta varios formatos AR (con/sin 0, con/sin 15, con/sin +54).
- **Fechas en Firestore**: `Timestamp` (nuevo) o `String` ISO (legacy). Helper `_parseDate` en cada modelo.
- **Campos de vencimiento**: convención `VENCIMIENTO_<NOMBRE>` y `ARCHIVO_<NOMBRE>`. El sistema de revisiones depende de esto (`replaceAll('VENCIMIENTO_', 'ARCHIVO_')`).

### Centralizaciones (sumar tipos nuevos solo en estas listas)
- **Tipos de vehículo**: `AppTiposVehiculo` en `app_constants.dart`.
- **Vencimientos por tipo**: `AppVencimientos.tractor` y `.enganche` en `vencimientos_config.dart`.
- **Roles**: `ADMIN` y `USUARIO` (no "CHOFER").
- **Rutas**: `AppRoutes` en `app_constants.dart`, no hardcodear strings.
- **Colores semánticos**: `AppColors.success/error/warning/info/...`. **NO** hardcodear `Colors.greenAccent`. Para colores del tema usar `Theme.of(context)`.

### UI/UX
- **Inputs de fecha**: SIEMPRE `pickFecha(...)` (`shared/widgets/fecha_dialog.dart`). NO usar `showDatePicker` (cliente lo odia).
- **SnackBars**: SIEMPRE `AppFeedback.success/error/warning/info(context, msg)`. Para post-await: `successOn(messenger, msg)`.
- **Loading modal**: `AppLoadingDialog.show(context, mensaje?)` / `AppLoadingDialog.hide(navigator)`.
- **Confirmaciones**: `AppConfirmDialog.show(...)` con `destructive: true` para acciones de riesgo.
- **Inputs numéricos**: agregar `DigitOnlyFormatter` en `inputFormatters` además de `keyboardType` (cubre paste y desktop).
- **Búsqueda**: `Ctrl+K` (Cmd+K en Mac) abre `CommandPalette`. Para abrir detalles desde otros features usar `abrirDetalleChofer(context, dni)` o `abrirDetalleVehiculo(context, patente, data)`.

### Logging y auditoría
- **Errores**: `AppLogger.recordError(error, stack, reason: ..., fatal: false)`. En mobile va a Crashlytics; en desktop solo `debugPrint`.
- **Logs de info**: `AppLogger.log(mensaje)` reemplaza `debugPrint` esparcidos.
- **Acciones admin**: `AuditLog.registrar(accion: ..., entidad: ..., entidadId: ..., detalles: {...})`. Es fire-and-forget; nunca bloquea.

## 5. Decisiones técnicas con su razón

| Decisión | Por qué |
|---|---|
| Firebase Auth con **custom token** (no email/password) | Los choferes no tienen email cargado pero sí DNI+password. La function valida server-side y emite un JWT con `uid = DNI` y rol como custom claim — `request.auth.uid` en las rules es el DNI directo |
| **Rol como custom claim** en el JWT (no en cada regla) | Evita una lectura extra de Firestore por cada regla evaluada. Si admin cambia el rol de un user, ese user mantiene el claim viejo hasta el próximo login (~1 hora máx). Aceptable |
| Cloud Function en Node.js | Consistencia con el bot WhatsApp, mismo runtime y mismo `firebase-admin` |
| Firestore queries con `orderBy` en cliente para `AVISOS_VENCIMIENTOS` | Evitar fricción del índice compuesto que Firestore pediría crear manualmente |
| `AutoSyncService` en provider tree | Su lifecycle (start/stop) lo maneja Provider, no el state del root widget |
| Volvo Connect via `additionalContent=VOLVOGROUPSNAPSHOT` | Sin ese flag el response NO trae `fuelLevel` ni `estimatedDistanceToEmpty` |
| `estimatedDistanceToEmpty` lo busca en `snapshotData.volvoGroupSnapshot` | El path real para diésel; los `chargingStatusInfo` son para EVs |
| Bot WhatsApp en Node.js separado, no Twilio | Se monta en un servidor del cliente con `whatsapp-web.js`. Costo cero, pero requiere mantener una sesión QR escaneada y un proceso vivo |
| Click-to-Chat (`wa.me`) para avisos manuales del admin | Complementa al bot: cuando el admin quiere mandar algo puntual sin pasar por la cola |
| `StorageService` con `Uint8List` + `putData` | `dart:io.File` no funciona en Web. El refactor hace los uploads cross-platform |
| Reportes Excel con guard de `kIsWeb` | El package `excel` toca `dart:io` para guardar; en Web mostraría error. Se muestra snackbar |
| OCR opcional con propiedad `soportado` | ML Kit solo Android/iOS. En Web/Windows el botón "Detectar fecha" se oculta |
| Campo "Preocupacional" tanto en UI como en Firestore | Migración completa hecha el 2026-04-28 vía `scripts/migrar_psicofisico_a_preocupacional.py` |

## 6. Lo que ya está hecho

### 6.1 Auditoría inicial (28 abril mañana)
Reporte: `AUDITORIA_2026-04-28.md`. Resueltos: credenciales Volvo hardcodeadas, `secrets.json` confirmado fuera de git, `mounted` checks en formularios, `unawaited` en lugares clave.

### 6.2 Refactor cross-platform + features Volvo (28 abril PM)
- Telemetría Volvo en pantalla del chofer y admin (odómetro, % combustible con barra, autonomía km).
- Panel diagnóstico Volvo (botón 🐛 en ficha del vehículo): muestra request, status, JSON crudo, análisis de campos críticos (✓/✗).
- Sync Dashboard ampliado: eventos por unidad (último 50), histórico de ciclos (último 15), botón "ejecutar ahora", motivos de skip detallados.
- Tipos de vehículo: BIVUELCO, TANQUE.
- Vencimientos nuevos en tractores: Extintor Cabina, Extintor Exterior.
- MAIL y TELÉFONO editables en gestión de personal y visibles en mi perfil.
- Foto/PDF reemplazable desde admin para los papeles del chofer (sin pasar por flujo de revisión).
- Botón "Avisar por WhatsApp" en cada vencimiento en auditoría con mensaje pre-armado según días restantes.
- Historial de avisos por vencimiento (`AVISOS_VENCIMIENTOS`) con bloque colapsable en el editor.
- Reporte Checklist abre Excel directo en Windows.
- Calendario reemplazado por input DD/MM/AAAA con validación inline.
- **Migración total `Psicofísico` → `Preocupacional`** en código y Firestore vía script Python idempotente.
- **Refactor cross-platform de uploads**: `StorageService.subirArchivo` con `Uint8List` + `putData`. Todos los callers actualizados. App compila y corre en Web sin crashear en flujos de subida.
- Reportes Excel con guard de Web.
- Permisos Android 13+: `POST_NOTIFICATIONS`, `CAMERA`, `<uses-feature>` opcional.

### 6.3 Sprints 1-3 de UX/calidad (28 abril PM)
- **Sprint 1**: `AppConfirmDialog` + confirmaciones destructivas en DESVINCULAR equipo y RECHAZAR revisión. Auditoría de feedback en todos los `update`/`set`/`delete` del admin.
- **Sprint 2**: `AppFeedback` (SnackBars semánticos), `AppLoadingDialog`, `DigitOnlyFormatter`. 46 SnackBars dispersos migrados, 2 loadings ad-hoc consolidados, `keyboardType: emailAddress` en mail.
- **Sprint 3**: pulido visual ("Nuevo Legajo" → "Nuevo chofer", tooltips en FABs, iconografía vencimientos unificada a `Icons.event_note`), `AppColors` centralizada.

### 6.4 Sprint 4 — Quick wins de productividad (28 abril PM)
- **Foto del vehículo**: campo `ARCHIVO_FOTO` en VEHICULOS. Avatar circular en `_VehiculoCard`. Bloque "Cambiar foto" en form de edición.
- **Búsqueda Ctrl+K**: `CommandPalette` indexa choferes + vehículos + revisiones con fetch one-shot, filtro local. Atajo en `admin_shell.dart` + IconButton en AppBar. Funciones `abrirDetalleChofer/Vehiculo/Revision` para uso desde otros features.
- **Calendario de vencimientos**: pantalla `admin_vencimientos_calendario_screen.dart` con `table_calendar`. Vista mensual con dots por urgencia (rojo ≤7 días, naranja 8-30, verde >30). Tap en día muestra lista; tap en ítem abre `VencimientoEditorSheet`.

### 6.5 Sprints 5-8 (28 abril noche) — Bot de WhatsApp y reporte de consumo
- **Reporte de consumo Excel** (`report_consumo.dart`): dialog para rango de fechas + columnas. Estrategia dual: si hay snapshots en `TELEMETRIA_HISTORICO` calcula consumo REAL del período; si no, fallback a `accumulatedData.totalFuelConsumption` y marca "(acum.)". Dos hojas: DETALLE + RANKING (top 10 con barras Unicode).
- **Snapshot diario de telemetría**: el AutoSync escribe a `TELEMETRIA_HISTORICO` (en futuro debería migrar al bot/Cloud Function).
- **Bot WhatsApp Fase 1**: encolar avisos manuales del admin a `COLA_WHATSAPP`. Bot Node.js procesa con anti-throttle. Pantalla `admin_whatsapp_cola_screen.dart` para ver estado (PENDIENTE/PROCESANDO/ENVIADO/ERROR) y reintentar/eliminar.
- **Bot WhatsApp Fase 2**: avisos automáticos por vencimientos. El bot programa los envíos según días restantes (30/15/7/1/0/-X) con idempotencia (colección `AVISOS_AUTOMATICOS_HISTORICO`).
- **Bot WhatsApp Fase 3**: bandeja de respuestas ambiguas (`admin_bot_bandeja_screen.dart`). Cuando el chofer manda foto sin contexto claro, el bot la deja con OCR ya aplicado y el admin elige a qué papel asociarla → se convierte en revisión.

### 6.6 Auditoría de seguridad (29 abril mañana)
- **Rotación de key Firebase**: la `private_key_id` anterior se revocó. Nuevo `serviceAccountKey.json` distribuido fuera de git.
- **Limpieza git history**: borrados commits viejos que tenían secretos hardcodeados con `git filter-repo`. Force-push al remoto (por eso la divergencia que tuvimos).
- **Firestore.rules + Storage.rules**: publicadas. Dejan abiertas las colecciones operacionales (read/write) porque la app no usa Firebase Auth, pero bloquean específicamente:
  - `AVISOS_AUTOMATICOS_HISTORICO` (write false — solo bot via Admin SDK).
  - `RESPUESTAS_BOT_AMBIGUAS` (write false — solo bot).
  - `RESPUESTAS_BOT/{archivo}` en Storage (write false — solo bot sube fotos recibidas).
  - Fallback `match /{document=**} { allow read, write: if false; }` para cualquier colección NO listada → si agregás una nueva sin sumarla a las rules, se rompe.
- **Fixes en bot Node.js**: sanitización de path (evita `../`), match estricto de teléfono, backoff exponencial en reintentos, grace shutdown (espera mensajes en vuelo antes de cerrar).
- **`AppConfirmDialog`** migrado a `AppColors` (antes hardcodeaba colores).

### 6.7 Servicios de logging y auditoría (28 abril PM)
- **`AppLogger`** en `lib/core/services/app_logger.dart`: `init()` engancha `FlutterError.onError` y `PlatformDispatcher.onError`. `log()`, `recordError()` con destino según plataforma (Crashlytics en mobile, debugPrint en desktop/web).
- **`AuditLogService`** en `lib/core/services/audit_log_service.dart`: enum `AuditAccion` con 12 casos (crear/editar chofer/vehículo, asignar/desvincular equipo, aprobar/rechazar revisión, cambiar foto, reemplazar papel). Escribe a `AUDITORIA_ACCIONES` con admin DNI/nombre, timestamp, detalles. Fire-and-forget — si falla, no bloquea.

### 6.8 OCR para detectar fechas (Sprint bot)
- **`OcrService`** en `lib/shared/utils/ocr_service.dart`: `detectarFecha(path)` con Google ML Kit on-device. Regex para `DD/MM/YYYY`, `DD-MM-YYYY`, `DD.MM.YYYY`. Devuelve la fecha más lejana en el futuro (asume que el último vencimiento es el de renovación). Property `soportado` para ocultar UI en Web/Windows.

## 7. Pendientes / roadmap

### Migración Firebase Auth (branch `feature/firebase-auth`) — ✅ COMPLETADA 2026-04-29
- ✅ Cloud Function `loginConDni` callable Gen2 deployada en us-central1 (Node.js 20 + bcrypt server-side).
- ✅ `AuthService` llama vía **HTTPS directo con Dio** (no `cloud_functions` plugin) porque ese plugin no tiene implementación nativa para Windows desktop. El protocolo callable (`{"data": ...}` request, `{"result": ...}` response) se maneja a mano.
- ✅ `AuthGuard` con doble check (PrefsService + FirebaseAuth.currentUser).
- ✅ `firestore.rules` y `storage.rules` reescritas con `isAdmin()` por custom claim — DEPLOYADAS.
- ✅ Probado en producción: admin login + chofer login + migración silenciosa SHA-256→bcrypt.

**Gotchas críticos encontrados durante el deploy** (anotar para próximas funciones Gen2):

1. **Cloud Build SA permissions**: en proyectos Firebase post-abril 2024, la SA por default `<PROJECT_NUMBER>-compute@developer.gserviceaccount.com` no recibe permisos automáticos. Hay que asignarle como mínimo: `Cloud Functions Developer`, `Cloud Run Admin`, `Service Account User`, `Cloud Build Service Account`, y `Editor` (o roles equivalentes más finos).
2. **`allUsers` invoker**: las Functions Gen2 NO son invocables públicamente por default (a diferencia de Gen1). Para callables públicos como `loginConDni`, hay que agregar `allUsers` con rol **`Cloud Run Invoker`** en Cloud Run permissions (no en la pantalla de Functions, no aparece "Cloud Functions Invoker" — Gen2 corre sobre Cloud Run).
3. **`signBlob` permission para `createCustomToken`**: la SA de runtime necesita el rol **`Service Account Token Creator`** **sobre sí misma**. Sin esto, `auth.createCustomToken()` falla con `iam.serviceAccounts.signBlob denied`.
4. **`cloud_functions` Dart package no soporta Windows**: si se agrega y se importa, tira `Unable to establish connection on channel: dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call`. Solución: llamar la function por HTTPS plano con Dio respetando el protocolo callable.

### Hardening de seguridad — ✅ COMPLETADO 2026-04-29 PM
1. ✅ **Rate limiting** en login: 5 intentos fallidos consecutivos → bloqueo 5 min. Implementado en `loginConDni` con colección `LOGIN_ATTEMPTS/{dniHash}` (clave hasheada para no exponer DNI). Reset automático al login OK. Rule: `write: if false`.
2. ✅ **Volvo credentials → Secret Manager** + Cloud Function `volvoProxy` (callable, requiere admin auth). El cliente Flutter llama al proxy por HTTPS con Bearer ID-token; el proxy valida `request.auth.token.rol === 'ADMIN'`, agrega Basic Auth Volvo y forwardea. Operaciones: `flota`, `telemetria`, `kilometraje`, `estadosFlota`. Secrets seteados con `firebase functions:secrets:set VOLVO_USERNAME/VOLVO_PASSWORD`.
3. ✅ **TELEMETRIA_HISTORICO movido al server**: `telemetriaSnapshotScheduled` corre cada 6h, llama `/vehicle/vehiclestatuses?latestOnly=true` (NO `/vehicle/vehicles` — bug latente del original que no traía telemetría real), escribe doc idempotente por `{patente}_{YYYY-MM-DD}` con `engineTotalFuelUsed/1000` (mL→L) y `hrTotalVehicleDistance/1000` (m→km). Rule: `write: if false`.
4. ✅ **Cloud Functions runtime → Node.js 22** (Node 20 deprecation = 2026-04-30, decommission = 2026-10-30). Bumpeado en `firebase.json` y `functions/package.json`.
5. ✅ **Auto-login + recordar último DNI**: `PrefsService.lastDni` sobrevive al logout para precargar el campo. `AuthGuard` reescrito como StatefulWidget con grace period de 1.5s (Firebase Auth en Windows desktop emite `null` primero y el user persistido ~500-1500ms después; sin grace period, el guard bouncea al login antes de tiempo). `_PassField`/`_DniField` usan `autofocus: true` idiomático (no `requestFocus` desde initState que dispara assertion `RenderBox was not laid out` en Windows).

### Roadmap medio plazo pendiente
1. ✅ **Refactor `admin_personal_lista_screen.dart`** — COMPLETADO 2026-04-29 noche. `_Actualizar` extraído a `lib/features/employees/services/empleado_actions.dart` como `EmpleadoActions`. Archivo lista pasa de 1295 a 727 líneas (-568). API pública preservada (`dato`/`fotoPerfil`/`documento`/`unidad`). `flutter analyze` limpio. El enum `_FuenteArchivoChofer` quedó privado al archivo nuevo. Convive con `EmpleadoService` (CRUD puro de Firestore, otra capa).
2. ✅ **`flutter_secure_storage`** — COMPLETADO 2026-04-29 medianoche. `PrefsService` migrado a `flutter_secure_storage: ^9.2.2` con cache en memoria para preservar API sync. Migración one-shot idempotente desde SharedPreferences viejo (limpia las claves al copiar). Backend nativo por plataforma (DPAPI/Keychain/KeyStore). Pendiente: `flutter pub get` + `flutter analyze` + probar login/logout en Windows.
3. ✅ **Mover `AUDITORIA_ACCIONES` al server** — COMPLETADO Y DEPLOYADO 2026-04-29 noche tarde. Cloud Function callable `auditLogWrite` (Gen2 en `functions/src/index.ts`). Cliente reescrito en `lib/core/services/audit_log_service.dart` para llamar via Dio + Bearer ID token. Rule cerrada a `write: if false`. Whitelist server-side de 11 acciones permitidas + 3 entidades. `admin_dni`/`admin_nombre` se toman del JWT (no del cliente, así no se pueden falsificar). **Pendiente único**: agregar `allUsers` Cloud Run Invoker al servicio `auditlogwrite` para que clientes Flutter puedan invocarlo:
   ```powershell
   gcloud run services add-iam-policy-binding auditlogwrite `
     --region=us-central1 --member="allUsers" --role="roles/run.invoker"
   ```
   (Sin esto la app va a recibir 403 al intentar auditar acciones.)

### Roadmap largo plazo (Volvo)
- **Anti-robo nocturno**: `wheelBasedSpeed > 0` fuera de horario operativo + push notification al admin.
- **Mantenimiento preventivo** vía endpoint VDDS `serviceDistance`.
- **Alertas de conducción** (descanso, conducción continua excedida) — requiere taquógrafo digital activo en los camiones.

### Decisiones del backlog (sin urgencia)
- Reemplazar `AVISOS_VENCIMIENTOS.streamHistorial` server-side con índice compuesto si llega a haber miles de avisos.
- Migrar `notification_service` a FCM (push real) cuando se sumen choferes con la app móvil.

## 8. Setup en una máquina nueva

### Pre-requisitos
- Flutter SDK 3.0+
- Python 3.10+ (solo para scripts de migración)
- Cuenta Firebase del proyecto `logisticaapp-e539a`
- Editor: VS Code con extensiones Dart + Flutter

### Pasos
```powershell
# 1. Clonar
git clone <url-del-repo> logistica_app_profesional
cd logistica_app_profesional

# 2. Recrear archivos sensibles (NO están en git)
#    - secrets.json            (credenciales Volvo Connect)
#    - serviceAccountKey.json  (solo para scripts de admin)
# Copiarlos desde Bitwarden / Drive privado

# 3. Instalar dependencias Flutter
flutter pub get

# 4. (Opcional) Para scripts Python
pip install firebase-admin

# 5. Correr la app (Windows)
flutter run -d windows --dart-define-from-file=secrets.json
# (en VS Code F5 ya tiene el flag configurado en .vscode/launch.json)
```

### Archivos sensibles que necesitás recrear
| Archivo | Para qué | Cómo |
|---|---|---|
| `secrets.json` | Credenciales Volvo Connect | Plantilla en `secrets.example.json`. Contenido en Bitwarden. |
| `serviceAccountKey.json` | Admin SDK Firebase para scripts y bot | Generar en Firebase Console → Project Settings → Service accounts → Generate new private key. |

## 9. Cómo retomar contexto en Claude / Cowork

Cowork no sincroniza historial entre desktops. Para una conversación nueva (otra máquina, o nuevo Claude), pegale al iniciar:

> Hola Claude. Vengo trabajando en una app Flutter de gestión de flota llamada **logistica_app_profesional** (S.M.A.R.T. Logística, empresa Vecchi en Bahía Blanca). Antes de empezar, leé `ESTADO_PROYECTO.md` y `AUDITORIA_2026-04-28.md` que están en la raíz del repo — ahí tenés el contexto completo: arquitectura, convenciones, lo que está hecho, lo que queda pendiente y las decisiones tomadas con sus razones. Trabajamos siguiendo esas convenciones (input de fecha DD/MM/AAAA con `pickFecha`, listas centralizadas en `AppVencimientos` y `AppTiposVehiculo`, mensajes con firma "_mensaje automático del sistema_", `AppFeedback` para SnackBars, `AppLoadingDialog` para loadings, `AppConfirmDialog` para confirmaciones, `AppColors` en lugar de hardcodear, etc). El próximo paso pendiente es <X>. ¿Listo para arrancar?

Reemplazá `<X>` con lo que quieras hacer ese día.

## 10. Comandos útiles

```powershell
# Correr la app en debug
flutter run -d windows --dart-define-from-file=secrets.json

# Build de release Windows
flutter build windows --release --dart-define-from-file=secrets.json

# Análisis estático
flutter analyze

# Migración Firestore (idempotente, soporta --dry-run)
python scripts/migrar_psicofisico_a_preocupacional.py --dry-run

# Bajar/subir cambios entre máquinas
git pull                           # antes de empezar
git add . ; git commit -m "..."    # cuando termines
git push

# Si la rama divergió por history rewrite (force push) en otra máquina:
git fetch origin
git branch backup-pre-reset
git reset --hard origin/main
git clean -fd
flutter pub get

# Ver últimos commits
git log --oneline -10
```

## 11. Notas operativas que no son obvias

- **El bot Node.js es un proceso vivo separado**: si nadie lo levanta en un servidor, los mensajes de la cola **NO se envían**. La app sola no manda WhatsApp automático — solo encola. Click-to-Chat (`wa.me`) sí funciona porque abre WhatsApp del admin.
- **Las pantallas del bot WhatsApp no están en `app_router.dart`**: el agente sospecha que se acceden desde un menú interno del `admin_shell` o por feature flag. Si querés agregarlas al menú principal, hay que registrar las rutas y sumar tiles en `admin_panel_screen.dart`.
- **`secrets.json` está congelado a una versión vieja de credenciales Volvo**: si Volvo rota el password en su portal, hay que actualizar `secrets.json` y rebuildear la app (no es runtime). Ver email de Volvo en Bitwarden.
- **Si se agrega una colección Firestore nueva**: sumarla a `firestore.rules` ANTES de hacer deploy de la app. El fallback `if false` la cerraría.
- **El primer ciclo del AutoSync corre al instante** al abrir la app (no espera 60 seg). Después cada minuto.
- **Los choferes tienen formato `APELLIDO NOMBRE...`**: el saludo del WhatsApp toma `partes[1]`. Si un legajo viene con ord

## 12. Bugs del sandbox de Cowork (workarounds)

### Síntoma: lectura truncada de archivos grandes

El sandbox Linux de Cowork está montado sobre el filesystem Windows y a
veces queda con una **vista desactualizada** de archivos que se editaron
fuera de la sesión (por VS Code, builds, `flutter pub get`). Síntomas:

- `Read` tool del agent muestra el archivo cortado mid-línea o mid-método.
- `wc -l` desde el sandbox devuelve menos líneas que `Get-Content | Measure-Object -Line` desde PowerShell.
- Edits con el `Edit` tool fallan con "String to replace not found" porque el match no existe en la vista parcial.

### Síntoma: bytes NULL al final del archivo tras un Write

Cuando el agent escribe un archivo más corto que la versión previa,
el `Write` tool a veces no truncar el backing file y queda relleno con
`\x00` al final. El TypeScript/Dart compiler tira *Invalid character*.

### Workarounds que probamos y funcionan

1. **Para reads de archivos > 500 líneas**: usar `python3 -c "with open(...)"` desde Bash. Lee directo del filesystem syscall y suele ver la versión actualizada.
2. **Para writes/edits con riesgo**: usar `python3 << 'EOF' ... EOF` con `read()`/`replace()`/`write()` y al final hacer `data.rstrip(b'\x00').rstrip() + EOL.encode()`. Eso elimina nulos residuales y garantiza un newline final limpio.
3. **Para refactors grandes**: hacelo a mano en VS Code, no le pidas al agent que mueva código entre archivos. El agent puede asistir con instrucciones de qué cortar/pegar.
4. **Verificación periódica**: cuando dudes, pegale `Get-Content archivo.dart | Measure-Object -Line` desde PowerShell y compará con `wc -l` del agent. Si difieren, agarra la vista de PowerShell como autoridad.
5. **Sandbox fresco**: cerrar la conversación de Cowork y abrir una nueva re-monta el filesystem y suele resolver la staleness. Hacerlo entre sesiones grandes (ej. fin de día → mañana siguiente).

### Cómo arrancar una sesión fresca

Al abrir una conversación nueva de Cowork sobre este proyecto:

1. Pedile al agent que ejecute (ejemplo de prompt): *"verificá con python que `lib/features/employees/screens/admin_personal_lista_screen.dart` tiene 1140 líneas en disco. Si es menos, decime y esperamos."*
2. Si el conteo coincide con `Get-Content | Measure-Object -Line`, la vista está fresca y se puede laburar normal.
3. Si difiere, pasale al agent el contenido completo del archivo por chat (vía `Get-Content archivo | Out-Host`) para que opere desde texto explícito en vez de la vista del filesystem.

### Refactor pendiente que se trabó por este bug

- `admin_personal_lista_screen.dart` → extraer `_Actualizar` a `services/empleado_actions.dart`. Ver sección 7. Plan listo, ejecutar en sandbox fresco o a mano.
