# Estado del proyecto — S.M.A.R.T. Logística

Documento de handoff para retomar trabajo en otra máquina o en una conversación nueva con Claude. Última actualización: **2026-04-29** (auditoría de seguridad profunda + fixes + rotación de key Firebase + limpieza git history + `firestore.rules`/`storage.rules`).

Sesiones recientes:
- **2026-04-29 (esta)** — auditoría de seguridad: rotación de key, limpieza git, fixes en bot (sanitización path, match estricto teléfono, backoff exponencial, grace shutdown), `firestore.rules`/`storage.rules`, AppConfirmDialog migrado a AppColors.
- **2026-04-28 (PM/noche)** — refactor cross-platform + sprints 1-8: UX/calidad + dashboard + reporte consumo con histórico + bot de WhatsApp Fase 1-3.
- **2026-04-28 (mañana)** — auditoría inicial (`AUDITORIA_2026-04-28.md`).

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

### Sprint 6 — Quick wins de mobile + dashboard del admin (2026-04-28 PM/noche)

**Crashlytics nativo en Android**
- Plugin gradle activado en `android/settings.gradle.kts` (`com.google.firebase.crashlytics 3.0.2`) y aplicado en `android/app/build.gradle.kts`. Junto con `AppLogger` ya cableado, los crashes de producción suben al panel de Firebase. En debug sigue siendo no-op.

**Ctrl+K extendido a revisiones**
- `CommandPalette` ahora indexa también `REVISIONES` además de `EMPLEADOS` y `VEHICULOS`. Tap → `abrirDetalleRevision(...)` (función pública nueva).
- Hint del input cambiado a "Buscar chofer, vehículo o trámite…".

**Push notifications agendadas para vencimientos del chofer**
- Sumado `timezone: ^0.9.4`. `NotificationService` inicializa zona `America/Argentina/Buenos_Aires`. Métodos `cancelarTodosLosRecordatorios()` y `agendarRecordatoriosVencimientos(List<VencimientoAviso>)`.
- Por cada vencimiento futuro, programa 4 notificaciones locales (30/15/7/1 días antes). IDs deterministas con djb2.
- `UserMisVencimientosScreen` reagenda al abrir. Fire-and-forget en Web/desktop.

**Dashboard del admin** (panel "Inicio" del shell)
- Rediseño de `admin_panel_screen.dart`: saludo personalizado + fecha de hoy + grid de **6 KPIs en vivo**:
  1. Choferes activos. 2. Unidades en flota + asignadas. 3. Trámites pendientes. 4. Vencidos (rojo). 5. Vencen ≤ 7 días. 6. Vencen ≤ 30 días.
- Tappables, navegan a la sección. `_Stats.from(...)` combina los 3 streams.

### Sprint 7 — Reporte de Consumo + snapshots históricos

**Reporte de Consumo de Combustible** (Excel con 2 hojas)
- `ReportConsumoService` (`features/reports/services/report_consumo.dart`).
- Dialog: rango DESDE/HASTA con `pickFecha` (default mes en curso) + checkboxes de columnas.
- Hoja **DETALLE**: tabla con todas las unidades + header informativo arriba.
- Hoja **RANKING**: top 10 más consumidoras del período con barra Unicode `█████` proporcional al máximo (truco "in-cell bar chart" porque `excel: ^4.0.6` no soporta charts nativos).
- Las celdas distinguen visualmente: período → valor numérico; acumulado → texto `"123 (acum.)"`. Ranking solo incluye unidades con período real.

**Snapshots históricos en TELEMETRIA_HISTORICO**
- `VehiculoRepository.guardarSnapshotsDiarios(cacheVolvo)`: cruza VIN→patente, escribe doc por unidad por día con id `{patente}_{YYYY-MM-DD}`. Last-write-wins. Batch write.
- `AutoSyncService` llama después de cada ciclo exitoso (cada 60s). Idempotente.
- `ReportConsumoService` lee `TELEMETRIA_HISTORICO` con query rango ampliado `[desde-30d, hasta+1d]`. Por cada unidad busca snapshot ≤ desde (inicio) y ≤ hasta (fin), calcula `litros_periodo = fin - inicio`. Si no hay datos suficientes, modo acumulado con marca `"(acum.)"`.

### Sprint 8 — Bot de WhatsApp Fases 1-3

Subcarpeta `whatsapp-bot/` con bot Node.js + `whatsapp-web.js`. Ver **sección 8** para setup completo.

**Fase 1 — Manual** (la app encola; el bot envía con delay anti-baneo):
- `WhatsAppColaService` en la app — escribe a `COLA_WHATSAPP` con metadata para auditoría.
- Botón "AUTOMÁTICO" en `vencimiento_editor_sheet.dart` al lado del manual. `_resolverDestinatario()` extraído.
- `AdminWhatsAppColaScreen` (`/whatsapp_cola`): contadores por estado + lista de los últimos 100 con timestamps, retry para ERROR, eliminar para PENDIENTE/ERROR.
- Bot Node.js (`whatsapp-bot/src/`): firebase-admin + wwebjs con `LocalAuth`, escucha `COLA_WHATSAPP`, valida horario hábil, delay 15-60s, envía, marca ENVIADO con `wa_message_id` o ERROR.

**Fase 2 — Cron automático** (`AUTO_AVISOS_ENABLED=true`):
- `cron.js` cada `CRON_INTERVAL_MINUTES` (60) recorre EMPLEADOS y VEHICULOS, calcula urgencia (preventivo 16-30d / recordatorio 8-15d / urgente 1-7d / hoy 0d), filtra por `AVISOS_AUTOMATICOS_HISTORICO` (idempotencia), construye con `aviso_builder.js` (port del Dart) y encola.
- Vencidos NO se procesan (queda como mejora futura).

**Fase 3 — Respuestas que se convierten en revisiones** (`AUTO_RESPUESTAS_ENABLED=true`):
- `message_handler.js` registra listener `message`. Filtra grupos/status/propios. Identifica chofer cruzando teléfono con `EMPLEADOS`.
- Asociación con aviso: prioridad al **quote** (`wa_message_id`), fallback a único aviso reciente ≤72h, sino → `RESPUESTAS_BOT_AMBIGUAS`.
- Media → Firebase Storage en `RESPUESTAS_BOT/{dni}_{ts}.{ext}`.
- Fecha extraída del texto con `fecha_extractor.js` (port del `OcrService`).
- Crea `REVISIONES` con `origen: 'BOT_WHATSAPP'`. Admin aprueba/rechaza desde la pantalla habitual.
- Ambiguos → `AdminBotBandejaScreen` (`/bot_bandeja`): preview + lista de candidatos + botón "Convertir en revisión" con sheet de selección + batch atómico.

### Sesión 2026-04-29 — Auditoría de seguridad y fixes

**Hallazgos críticos cerrados**:
- 🔴 **`serviceAccountKey.json` en git history** (commit `58a72ff`): la private key de Firebase Admin estaba accesible para cualquiera con acceso al repo.
  - **Acción 1**: rotada vía Firebase Console (eliminada la key vieja `15a96f5b...`, generada nueva). La key vieja queda invalidada en cualquier lado donde haya quedado.
  - **Acción 2**: historial git limpiado con `git-filter-repo --invert-paths --path serviceAccountKey.json --force`. 45 commits reescritos. `git log --all --full-history -- serviceAccountKey.json` ya no devuelve nada.
  - **Acción 3**: force-push al remote (GitHub repo privado `rodriguezreysantiago/logistica_app_profesional`) para que el historial remoto también quede limpio.
  - **Backup pre-cleanup**: `../backup-pre-cleanup.git` (mirror del repo antes de filter-repo).
- 🔴 **Sin `firestore.rules` ni `storage.rules`**: ambas creadas en raíz del repo. Bloquean escritura desde cliente a colecciones que solo el bot debería tocar (`AVISOS_AUTOMATICOS_HISTORICO`, `RESPUESTAS_BOT/...` en Storage). Catch-all `if false` al final para que cualquier colección nueva quede bloqueada por default. **Pendiente**: `firebase deploy --only firestore:rules,storage`.

**Fixes en el bot**:
- **`message_handler._resolverChofer`**: cambiado match por sufijo de 8 dígitos por match estricto (exacto o uno termina con el otro con mínimo 10 dígitos). Cierra vulnerabilidad de spoofing donde dos números no relacionados con últimos 8 dígitos iguales matcheaban.
- **`message_handler._subirMedia`**: sanitiza `dni` con `replace(/[^0-9]/g, '')` antes de construir path Storage. Defense-in-depth contra path traversal.
- **`whatsapp.tieneWhatsApp`**: ya no traga errores. Devuelve `false` solo cuando WhatsApp confirma que el número no existe (terminal). Si hay timeout/sesión caída → relanza para que el caller decida reintentar. Antes confundía "no tiene WhatsApp" con "WhatsApp no respondió".
- **`whatsapp.js`**: reconexión con backoff exponencial (1s → 2s → 4s → 8s → 16s, máximo 5 intentos). Después sale para que el supervisor reinicie limpio. Reset del contador cuando `ready`. Antes podía hacer "100 reconexiones por minuto" si WhatsApp cerraba la sesión repetidamente.
- **`index.js` shutdown**: SIGINT/SIGTERM espera hasta 10 segundos a que termine el envío en curso antes de `process.exit`. Evita dejar docs en `PROCESANDO`.
- **`index.js` retry**: si `tieneWhatsApp` lanza, devuelve el doc a `PENDIENTE` para que el listener vuelva a intentar (no se queda en ERROR permanente por timeout transient).
- **`cron.js`**: índice inverso `choferByPatente` pre-computado al inicio del ciclo. Lookups O(1) en vez de iterar empleados por cada vencimiento.
- **`aviso_builder.build`**: `destinatarioNombre` saneado con `replace(/\s+/g, ' ').trim().slice(0, 40)`. Evita que un nombre con saltos rompa el formato.

**Fixes en la app**:
- **`AppConfirmDialog`**: migrado de `Colors.redAccent`/`Colors.greenAccent`/`Colors.green` a `AppColors.accentRed` / `AppColors.accentGreen` / `AppColors.success`. Empieza la migración incremental que estaba en el roadmap.

**Falsos positivos del audit (descartados)**:
- "Stream subscription leak en `admin_panel_screen.dart:71`" — el código ya cancela el subscription antes de reasignar.
- "DNI logueado en plain text" — `auth_service.dart` ya hashea con `dni.hashCode`.
- "`secrets.json` commiteado" — `git log` confirma que nunca se commiteó.

**Verificación final**: `flutter analyze` → 0 issues. `flutter test` → 38 verdes. `node --check` en los 6 archivos del bot tocados → OK.

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
- **Desplegar `firestore.rules` y `storage.rules`** (ya creadas en raíz): probar primero en el simulador de Firebase Console y después `firebase deploy --only firestore:rules,storage`. Bloquea escritura desde cliente a colecciones que solo el bot debería tocar.
- **Validar el bot de WhatsApp en producción** durante unos días con `AUTO_AVISOS_ENABLED=false` y `AUTO_RESPUESTAS_ENABLED=false` (solo Fase 1 — envío manual desde la app). Cuando el ritmo de envío y el comportamiento del número descartable inspire confianza, activar Fase 2 y 3.
- **Configurar autostart del bot en la PC de oficina** (Task Scheduler de Windows o `nssm` — ver sección 8) para que el bot levante solo cuando se prende la PC y reinicie ante caídas.
- **Mails automáticos escalonados** como complemento del bot (defensa en profundidad). Requiere:
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

## 8. Bot de WhatsApp — guía completa

> ⚠️ **Aviso operativo**. WhatsApp prohíbe explícitamente bots no oficiales (TOS). El número que usás para automatizar puede ser baneado sin aviso. **Usar solo con un número descartable** que NO sea el de la oficina principal. Si Meta detecta el patrón y banea, conseguimos otro chip y volvemos a vincular — `.wwebjs_auth/` se invalida y el bot pide QR de nuevo.

### 8.1 Cómo funciona

```
[App Flutter]                    [Firestore]                 [Bot Node.js]
admin → "AUTOMÁTICO"   →    COLA_WHATSAPP/                 escucha la cola
                              { telefono,                ←  toma cada PENDIENTE
                                mensaje,                     espera 15-60s
                                estado: PENDIENTE }    →    envía vía wwebjs
                                                            marca ENVIADO/ERROR

cada 60min (cron, Fase 2)    EMPLEADOS, VEHICULOS  ←   recorre vencimientos
                                                       calcula urgencia
                              AVISOS_AUTOMATICOS_HIST  →  filtra ya-enviados
                              COLA_WHATSAPP            ←  encola los nuevos

chofer responde   →   bot recibe (Fase 3)         →   sube foto a Storage
con foto al aviso     identifica chofer/aviso         extrae fecha del texto
                      por quote o contexto reciente   crea REVISIONES o
                                                      RESPUESTAS_BOT_AMBIGUAS
```

La app **no** habla directo con WhatsApp. Solo escribe a Firestore. Si el bot está caído, los mensajes quedan PENDIENTE y se envían cuando vuelve.

### 8.2 Pre-requisitos

- **Node.js 18+** instalado.
- **`serviceAccountKey.json`** (el mismo que usan los scripts Python).
- **Teléfono Android/iPhone descartable** con WhatsApp y un chip que NO sea el de la oficina.

### 8.3 Setup paso a paso

```powershell
cd C:\Users\santi\logistica_app_profesional\whatsapp-bot

# Instalar dependencias (~5 min la primera vez — baja Chromium)
npm install

# Copiar .env de ejemplo y editar
copy .env.example .env
copy ..\serviceAccountKey.json serviceAccountKey.json
notepad .env
```

En el `.env`:
```env
FIREBASE_CREDENTIALS_PATH=./serviceAccountKey.json
FIREBASE_PROJECT_ID=logisticaapp-e539a

# Empezar SIN avisos automáticos ni respuestas auto
AUTO_AVISOS_ENABLED=false
AUTO_RESPUESTAS_ENABLED=false

WORKING_HOURS_START=8
WORKING_HOURS_END=21
DELAY_MIN_MS=15000
DELAY_MAX_MS=60000
CRON_INTERVAL_MINUTES=60
```

### 8.4 Primera ejecución (escanear QR)

```powershell
npm start
```

Aparece QR ASCII. Escanealo desde WhatsApp del teléfono descartable: `Ajustes → Dispositivos vinculados → Vincular un dispositivo`. La sesión queda guardada en `.wwebjs_auth/` y no hay que volver a escanear.

### 8.5 Pre-cargar contactos (anti-baneo)

Antes de avisos masivos, **agendá los teléfonos de los choferes en los contactos del teléfono descartable**. WhatsApp es más permisivo con contactos guardados.

### 8.6 Calentar el número

Antes de poner en producción, mandar mensajes manuales por 2-3 días desde el número del bot. Un número silencioso que de repente manda 30 mensajes es la señal más fuerte de bot.

### 8.7 Activar Fase 2 (cron de avisos automáticos)

```env
AUTO_AVISOS_ENABLED=true
```

Reiniciar bot. En logs:
```
[INFO] Cron de avisos automáticos HABILITADO (cada 60 min).
```

Cada hora escanea Firestore, calcula urgencia (preventivo / recordatorio / urgente / hoy), filtra por `AVISOS_AUTOMATICOS_HISTORICO` (idempotencia) y encola en `COLA_WHATSAPP`. Cada (chofer, papel, urgencia, fechaVenc) se manda una sola vez.

### 8.8 Activar Fase 3 (respuestas → revisiones)

```env
AUTO_RESPUESTAS_ENABLED=true
```

El bot recibe mensajes, identifica chofer (cruce con EMPLEADOS por teléfono), asocia con aviso vía quote o contexto reciente ≤72h, descarga foto a Storage, extrae fecha del texto, crea `REVISIONES` con `origen: 'BOT_WHATSAPP'`. Si ambiguo, va a `RESPUESTAS_BOT_AMBIGUAS` y aparece en pantalla "Bandeja del Bot".

### 8.9 Autostart en Windows

**Task Scheduler** (sin instalar nada):
- Trigger: `When the computer starts`
- Program: `C:\Program Files\nodejs\node.exe`
- Arguments: `src/index.js`
- Start in: `C:\Users\santi\logistica_app_profesional\whatsapp-bot`
- Settings → Restart on failure cada 1 min × 3 intentos

**`nssm`** (recomendado, más robusto):
```powershell
choco install nssm
nssm install SmartLogisticaWhatsAppBot "C:\Program Files\nodejs\node.exe"
# UI: AppDirectory, AppParameters: src/index.js, Auto-restart 5000ms
nssm start SmartLogisticaWhatsAppBot
```

### 8.10 Diagnóstico

- **Pantalla "Cola de WhatsApp"** en la app: ENVIADO / PROCESANDO / ERROR / PENDIENTE con timestamps.
- **Pantalla "Bandeja del Bot"**: respuestas que no se pudieron asociar.
- Colección `AVISOS_AUTOMATICOS_HISTORICO`: qué generó el cron.
- Logs del proceso (consola o archivo si redirigís stdout).

### 8.11 Limitaciones

- Sin OCR sobre la foto (solo regex sobre el texto).
- Sin diálogo interactivo. Si hay ambigüedad → bandeja manual.
- Vencidos no se procesan automáticamente en Fase 2.
- Solo papeles del chofer, no cambios de equipo.

---

## 9. Setup en una máquina nueva

### Pre-requisitos
- Flutter SDK 3.0+
- Node.js 18+ (para el bot — ver sección 8)
- Python 3.10+ (solo si vas a correr scripts de migración)
- Cuenta Firebase del proyecto `logisticaapp-e539a`
- Editor: VS Code con extensiones Dart + Flutter

### Pasos
```powershell
# 1. Clonar y entrar
git clone <url-del-repo> logistica_app_profesional
cd logistica_app_profesional

# 2. Recrear archivos sensibles (NO están en git, copiá desde Bitwarden / Drive privado)
#    - secrets.json              → credenciales Volvo Connect
#    - serviceAccountKey.json    → Firebase Admin SDK (para scripts y bot)

# 3. Instalar dependencias Flutter
flutter pub get

# 4. (Opcional) Instalar deps Python para scripts admin
pip install firebase-admin

# 5. Correr la app (Windows)
flutter run -d windows --dart-define-from-file=secrets.json

# 6. (Opcional) Setup del bot — ver sección 8 para detalle
cd whatsapp-bot
npm install
copy .env.example .env
copy ..\serviceAccountKey.json serviceAccountKey.json
npm start  # primera vez: escanear QR
```

### Archivos sensibles que necesitás recrear
- `secrets.json` — formato en `secrets.example.json`. `VOLVO_USERNAME` y `VOLVO_PASSWORD`.
- `serviceAccountKey.json` — bajar de Firebase Console → Service Accounts → Generate new private key. Va en raíz Y en `whatsapp-bot/`.
- `whatsapp-bot/.env` — copiar de `.env.example`.
- `whatsapp-bot/.wwebjs_auth/` — se genera al escanear QR. NO está en git (cookies de sesión).

## 10. Cómo retomar contexto en Claude / Cowork

Si abrís una conversación nueva en otra máquina (Cowork no sincroniza historial entre desktops), **pegá el siguiente prompt al iniciar** para que tenga el contexto:

> Hola Claude. Vengo trabajando en una app Flutter de gestión de flota llamada **logistica_app_profesional** (S.M.A.R.T. Logística, empresa Vecchi en Bahía Blanca). Tiene además un bot de WhatsApp en `whatsapp-bot/` (Node.js + whatsapp-web.js). Antes de empezar, leé `ESTADO_PROYECTO.md` y `AUDITORIA_2026-04-28.md` — ahí tenés contexto completo: arquitectura, convenciones, lo que está hecho, lo que queda pendiente y las decisiones tomadas. Trabajamos siguiendo esas convenciones (input de fecha DD/MM/AAAA con `pickFecha`, listas centralizadas en `AppVencimientos`/`AppTiposVehiculo`, feedback con `AppFeedback`, confirmaciones destructivas con `AppConfirmDialog`, audit log en acciones críticas, mensajes de WhatsApp con firma "_mensaje automático del sistema_", port del builder de avisos sincronizado entre Dart y JS). El próximo paso pendiente es <X>. ¿Listo para arrancar?

Reemplazá `<X>` con lo que quieras hacer ese día.

## 11. Comandos útiles que uso seguido

### App Flutter

```powershell
# Correr la app en debug
flutter run -d windows --dart-define-from-file=secrets.json

# Correr en Chrome (Web)
flutter run -d chrome --dart-define-from-file=secrets.json

# Build de release Windows
flutter build windows --release --dart-define-from-file=secrets.json

# Análisis estático y tests
flutter analyze
flutter test

# Migración Firestore (idempotente, soporta --dry-run)
python scripts/migrar_psicofisico_a_preocupacional.py --dry-run
```

### Bot de WhatsApp

```powershell
cd whatsapp-bot

# Primer arranque (escanear QR)
npm install
npm start

# Operación normal
npm start

# Re-escanear QR (si el número fue baneado o cambiaste de chip)
Remove-Item -Recurse -Force .wwebjs_auth
npm start
```

### Firebase (deploy de rules)

```bash
# Pre-requisito una vez:
npm install -g firebase-tools
firebase login

# Deploy de rules
firebase deploy --only firestore:rules
firebase deploy --only storage
firebase deploy --only firestore:rules,storage   # ambos juntos

# Probar en simulador antes de deploy:
# Firebase Console → Firestore → Rules → Playground
```

### Rotación de service account (cuando hace falta)

```
1. Firebase Console → Project Settings → Service Accounts.
2. Click en `firebase-adminsdk-fbsvc@...`.
3. Pestaña KEYS → Add Key → Create new key (JSON) → guardar.
4. Reemplazar `serviceAccountKey.json` en raíz Y en `whatsapp-bot/`.
5. Reiniciar el bot, verificar que arranca sin errores.
6. Volver a la consola → en la fila de la key vieja → ⋮ → Delete.
```

### Limpiar key del git history (después de rotar)

```powershell
pip install git-filter-repo

# Backup
git clone --mirror . ../backup-pre-cleanup.git

# Limpiar (filter-repo borra el remote por seguridad — hay que re-agregarlo)
& "C:\Users\santi\AppData\Roaming\Python\Python314\Scripts\git-filter-repo.exe" --invert-paths --path serviceAccountKey.json --force

# Verificar limpio
git log --all --full-history -- serviceAccountKey.json   # debe estar vacío

# Re-agregar remote y forzar push
git remote add origin https://github.com/<usuario>/<repo>
git push --force --all origin
git push --force --tags origin
```

### Git

```bash
# Ver últimos commits
git log --oneline -15

# Recordar qué cambió en la última sesión
git log --since='1 day ago' --stat
```

---

*Última actualización: 2026-04-29 — auditoría de seguridad + rotación de key + git history limpio + `firestore.rules`/`storage.rules` + fixes en bot. Actualizar este archivo cuando se completen pendientes grandes o se sumen features importantes.*
