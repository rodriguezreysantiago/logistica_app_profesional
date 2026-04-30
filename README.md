# S.M.A.R.T. Logística

Sistema de gestión de flota para la empresa de transporte **Vecchi / Sucesión Vecchi** (Bahía Blanca). Maneja personal, flota, vencimientos de papeles, checklists, revisiones, integración con Volvo Connect y un bot de WhatsApp para avisos automáticos.

## Stack

- **App Flutter** 3.x multiplataforma (Windows desktop para admin, Android para choferes; Web compila pero algunos features se desactivan).
- **Firebase**: Firestore (datos), Storage (archivos), Auth con custom token, Cloud Functions Gen2 (Node.js 22), Crashlytics.
- **Bot WhatsApp**: proyecto Node.js separado en `whatsapp-bot/` que escucha la cola en Firestore y envía mensajes con anti-baneo + watchdog + retry + agrupación por chofer.
- **Volvo Connect API**: telemetría de tractores Volvo (odómetro, combustible, mantenimiento) vía Cloud Function proxy.

## Cómo arrancar

### App Flutter

```powershell
# Clonar
git clone https://github.com/rodriguezreysantiago/logistica_app_profesional.git
cd logistica_app_profesional

# Recrear archivos sensibles (NO están en git):
#   - secrets.json            (credenciales Volvo Connect)
#   - serviceAccountKey.json  (solo para scripts de admin)
# Copiarlos desde Bitwarden / Drive privado.

flutter pub get
flutter run -d windows --dart-define-from-file=secrets.json
# (en VS Code F5 ya tiene el flag configurado en .vscode/launch.json)
```

### Bot WhatsApp

```powershell
cd whatsapp-bot
npm install
cp .env.example .env  # editar valores reales
npm start
```

El primer arranque pide escanear un QR desde el celular descartable. La sesión se persiste en `.wwebjs_auth/`.

## Estructura general

```
logistica_app_profesional/
├── lib/                  # App Flutter
│   ├── core/             # services, constants, theme
│   ├── features/         # admin_dashboard, auth, employees, vehicles,
│   │                     # expirations, revisions, reports, whatsapp_bot,
│   │                     # checklist, sync_dashboard, home
│   ├── routing/          # app_router.dart
│   └── shared/           # widgets, utils
├── functions/            # Cloud Functions (TypeScript Node 22)
├── whatsapp-bot/         # Bot Node.js (whatsapp-web.js + firebase-admin)
├── scripts/              # Migraciones one-shot (Python + Node)
├── android/, ios/, web/, windows/
├── firebase.json         # firebase deploy --only firestore:rules / functions
├── firestore.rules
├── storage.rules
└── ESTADO_PROYECTO.md    # Doc de handoff completo
```

## Documentación

**`ESTADO_PROYECTO.md`** es el doc principal — handoff para retomar trabajo en otra máquina o en una conversación nueva con Claude. Incluye:

- Tech stack detallado.
- Arquitectura completa por features.
- Convenciones (orden APELLIDO+NOMBRE, IDs en EMPLEADOS=DNI, etc.).
- Decisiones técnicas con su razón.
- Lo ya hecho por sesiones (sprints, refactors, features Volvo, bot, RBAC, etc.).
- Pendientes / roadmap.
- Setup en máquina nueva.
- Comandos útiles.
- Bugs del sandbox de Cowork con sus workarounds.

Cuando vuelvas en otra sesión, leé esa sección antes de cambiar nada.

## Roles y permisos

4 roles del sistema (custom claim `rol` en JWT) × 5 áreas (descriptivas):

| Rol | Qué hace |
|-----|----------|
| `CHOFER` | Empleado de manejo. Ve sus vencimientos + su unidad asignada. |
| `PLANTA` | Empleado sin vehículo (planta, taller, gomería). Solo vencimientos personales. |
| `SUPERVISOR` | Mando medio. Gestiona personal/flota/vencimientos/revisiones/bot. |
| `ADMIN` | Control total. Crea admins, cambia roles, audita. |

Áreas: `MANEJO`, `ADMINISTRACION`, `PLANTA`, `TALLER`, `GOMERIA`.

Las capabilities cliente viven en `lib/core/services/capabilities.dart`. Los chequeos server-side están en `firestore.rules` con helpers `isAdmin()`, `isSupervisor()`, `isAdminOrSupervisor()`.

## Cloud Functions

- `loginConDni` — auth con DNI + password (bcrypt + rate limit + custom token con claims).
- `auditLogWrite` — bitácora de acciones admin (whitelist server-side).
- `volvoProxy` — proxy autenticado a Volvo Connect API.
- `actualizarRolEmpleado` — cambio de rol que refresca custom claim + libera unidades.
- `telemetriaSnapshotScheduled` — cron cada 6h que escribe a `TELEMETRIA_HISTORICO`.

Deploy:
```powershell
firebase deploy --only functions
firebase deploy --only firestore:rules
firebase deploy --only storage
```

## Bot WhatsApp

Escucha `COLA_WHATSAPP` en Firestore. Cron cada 60 min escanea EMPLEADOS y VEHICULOS, calcula urgencias y encola avisos. Si un chofer tiene 2+ vencimientos para avisar, los agrupa en un solo mensaje (anti-baneo). Tiene:

- Reintentos con backoff exponencial para errores transitorios.
- Watchdog del evento `READY` (resuelve cuelgue del A/B testing de WhatsApp Web).
- Heartbeat cada 60s a `BOT_HEALTH/main` (visible en pantalla "Estado del Bot" de la app).
- Kill-switch desde la app (toggle en pantalla del bot).
- Comandos admin por WhatsApp (`/estado`, `/pausar`, `/reanudar`, `/forzar-cron`, `/ayuda`).
- Modo dry-run (`BOT_DRY_RUN=true`) para testing sin enviar real.

## Convenciones críticas

- **Orden de NOMBRE**: APELLIDO(s) + NOMBRE(s) en mayúsculas. El algoritmo de saludo extrae el primer nombre del segundo token. Para casos donde falla (dos apellidos, segundo nombre), usar el campo `APODO`.
- **DNI = doc.id en EMPLEADOS** (sin formato, solo dígitos).
- **Patente = doc.id en VEHICULOS** (sin guiones, en mayúsculas).
- **Fechas**: formato ISO `YYYY-MM-DD` en Firestore. Parseo manual para evitar shift UTC vs local.

## Licencia

Privado — uso interno de Vecchi.
