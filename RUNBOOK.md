# RUNBOOK — S.M.A.R.T. Logística

Documento operativo para resolver incidentes en producción. Pensado para que **alguien que no sea Santiago** pueda mantener el sistema funcionando si Santiago no está disponible.

> El [README.md](README.md) es para arrancar el proyecto; el [ESTADO_PROYECTO.md](ESTADO_PROYECTO.md) es contexto histórico. Este archivo es para **apagar incendios**.

---

## Tabla de contenidos

1. [Diagnóstico rápido — ¿qué está roto?](#diagnóstico-rápido)
2. [Bot WhatsApp no envía mensajes](#bot-whatsapp-no-envía-mensajes)
3. [Login no funciona / la app no deja entrar](#login-no-funciona)
4. [Volvo Connect: telemetría sin actualizar](#volvo-connect-telemetría-sin-actualizar)
5. [Rollback de un deploy malo](#rollback-de-un-deploy-malo)
6. [Backup y disaster recovery](#backup-y-disaster-recovery)
7. [Comandos rápidos de diagnóstico](#comandos-rápidos-de-diagnóstico)
8. [Contactos y secretos](#contactos-y-secretos)

---

## Diagnóstico rápido

**Si algo no anda, chequear en este orden:**

| Síntoma | Dónde mirar primero |
|---|---|
| Choferes no reciben WhatsApp | Pantalla "Estado del Bot" en la app → si hace > 2 min sin heartbeat, [bot caído](#bot-whatsapp-no-envía-mensajes) |
| App pide login pero rechaza credenciales válidas | [Cloud Function loginConDni](#login-no-funciona) |
| Tractores Volvo aparecen sin telemetría | [Volvo Connect 401](#volvo-connect-telemetría-sin-actualizar) o ticket de paquete UPTIME |
| Después de un deploy todo se rompe | [Rollback](#rollback-de-un-deploy-malo) |
| `firebase deploy` falla con `eslint no se reconoce` o `No currently active project` | [Pre-checks de deploy](#pre-checks-antes-de-correr-firebase-deploy) |
| `start_bot.ps1` aborta diciendo que hay cambios pero `git diff` está vacío | [Stat dirty del package-lock](#start_botps1-aborta-por-package-lock-modificado-pero-git-diff-está-vacío) |
| Pantalla blanca al abrir la app | Crashlytics en Firebase Console (solo mobile) — desktop solo logs locales |

---

## Bot WhatsApp no envía mensajes

El bot corre como **servicio NSSM en una PC con Windows** (PC casa). El proceso se llama `SmartLogisticaBot`.

### Verificar si el bot está corriendo

```powershell
# Estado del servicio Windows
Get-Service SmartLogisticaBot

# Heartbeat a Firestore (lo que ve la app)
# Pantalla admin > "Estado del Bot" muestra ultimoHeartbeat,
# pcId, cliente WA, cola, último ciclo del cron.
```

Si el heartbeat es de hace > 2 min, el bot está caído **aunque el servicio diga "Running"**: puede estar trabado en initial-load de WhatsApp Web.

### Restart limpio

```powershell
cd C:\Users\santi\logistica_app_profesional\whatsapp-bot
.\scripts\stop_bot.ps1   # auto-eleva UAC, espera grace period 90s
.\scripts\start_bot.ps1  # hace git pull + npm install + nssm start
```

`scripts\stop_bot.ps1` hace stop ordenado respetando el `grace_shutdown` del bot (deja terminar mensajes en vuelo). `scripts\start_bot.ps1` rechaza arrancar si hay cambios sin commitear (proteger producción).

### Si el restart no alcanza

El "calvario operativo" del 1-mayo PM (sec. 6.11.11 del `ESTADO_PROYECTO.md`) dejó esta receta:

```powershell
# 1. Stop service desde PowerShell-Admin
Stop-Service SmartLogisticaBot -Force

# 2. Borrar la sesión rota (requiere admin porque LocalSystem la creó)
Remove-Item C:\Users\santi\logistica_app_profesional\whatsapp-bot\.wwebjs_auth -Recurse -Force

# 3. Borrar cache de Chromium
Remove-Item C:\Users\santi\logistica_app_profesional\whatsapp-bot\.wwebjs_cache -Recurse -Force

# 4. Start service. Va a pedir QR fresco.
Start-Service SmartLogisticaBot

# 5. Mirar logs de NSSM para ver el QR
Get-Content C:\Users\santi\logistica_app_profesional\whatsapp-bot\logs\bot-out.log -Tail 50 -Wait
```

**Importante**: nunca correr `node src/index.js` a mano si el servicio NSSM está activo. Una sesión a la vez. Mezclar ambos quema la sesión persistida.

### Comandos por WhatsApp (sin abrir la PC)

Mandar al **propio número del bot** desde un teléfono que esté en `ADMIN_PHONES` del `.env`:

- `/estado` — resumen de cola, último ciclo, pausa.
- `/pausar [Nh|Nd]` — pausar envíos (opcional duración: `/pausar 24h`).
- `/reanudar` — reanudar.
- `/forzar-cron` — corre el ciclo del cron ahora (no espera 60min).
- `/ayuda` — lista comandos.

Si los comandos no responden y vos sí estás en la whitelist, el bot está **caído** — no es problema de permisos.

### El bot está corriendo pero choferes no responden

Probablemente WhatsApp baneó el número. Síntomas:
- Heartbeat OK pero `cola.PROCESANDO` se acumula.
- Errores tipo "rate limit" en logs.

**Acción inmediata**: pausar el bot (`/pausar 24h`) para no agravar. El número descartable hay que reemplazarlo. Esto es un riesgo conocido de `whatsapp-web.js` no oficial — la migración a WhatsApp Business API oficial está en el roadmap (sec. 13.4 del ESTADO_PROYECTO).

---

## Login no funciona

Síntoma: el usuario tipea DNI + password correctos y la app dice "Error de servidor".

### Chequeo 1 — Cloud Function viva

```powershell
# Logs en tiempo real de loginConDni
firebase functions:log --only loginConDni --lines 50
```

Errores comunes:

| Mensaje | Causa | Fix |
|---|---|---|
| `iam.serviceAccounts.signBlob denied` | SA runtime sin Service Account Token Creator sobre sí misma | Re-aplicar IAM (ver `ESTADO_PROYECTO.md` sec. "Hardening de seguridad") |
| `permission-denied: ...allUsers Cloud Run Invoker missing` | Después de un deploy nuevo, Cloud Run quitó el `allUsers` invoker | `gcloud run services add-iam-policy-binding logincondni --region=southamerica-east1 --member="allUsers" --role="roles/run.invoker"` |
| `resource-exhausted: Demasiados intentos fallidos` | Rate limit pegándole al usuario | Esperar 15 min, o limpiar `LOGIN_ATTEMPTS/{hash(dni)}` desde la consola Firestore |

### Chequeo 2 — Custom claims desactualizadas

Si un usuario fue creado o cambió rol HACE POCO y aún no funciona, es porque el JWT viejo no tiene el claim. Solución: **logout + login** en la app (forza renovar el token).

---

## Volvo Connect telemetría sin actualizar

`telemetriaSnapshotScheduled` corre cada 6h y escribe a `TELEMETRIA_HISTORICO`. Si los datos están viejos:

```powershell
# Ver últimas ejecuciones del scheduled
firebase functions:log --only telemetriaSnapshotScheduled --lines 30
```

Errores comunes:

- **401 Unauthorized**: credenciales Volvo expiraron o cliente las rotó. Recuperar nueva password de Volvo (mirar email del cliente / sec. 8 ESTADO_PROYECTO) y rotar el secret:
  ```powershell
  firebase functions:secrets:set VOLVO_PASSWORD
  # pega la nueva password
  firebase deploy --only functions:telemetriaSnapshotScheduled,functions:volvoProxy
  ```
- **`uptimeData.serviceDistance` undefined**: paquete UPTIME inactivo en la cuenta Volvo. Hay ticket abierto. Mientras tanto el bot usa Plan B (`ULTIMO_SERVICE_KM + 50.000 - KM_ACTUAL`).

---

## Deploy de Cloud Functions

### Pre-checks antes de correr `firebase deploy`

Si nunca deployaste desde esta PC (o pasó tiempo), tres cosas que hay que verificar antes para no chocarse con errores de tooling:

**1. Project alias activo** (`No currently active project`):
```powershell
firebase use logisticaapp-e539a
# → "Now using project logisticaapp-e539a"
```
Queda guardado en `.firebaserc` local de la PC.

**2. Dev dependencies de `functions/` instaladas** (`"eslint" no se reconoce`):
```powershell
cd functions
npm install
cd ..
```
El predeploy hook de `firebase.json` corre `npm run lint` + `npm run build` — sin las dev deps falla a la primera. Una vez al setupear la PC alcanza.

**3. Build local OK** (sanity check antes de quemar el deploy):
```powershell
cd functions
npm run build
cd ..
```
Si `tsc` tira error, el deploy va a fallar igual — mejor verlo acá. Sigue: `flutter analyze` + `flutter test` + `cd whatsapp-bot ; npm test` para confirmar que el repo entero está limpio.

### Comando de deploy

```powershell
# Deploy de UNA function (recomendado para producción)
firebase deploy --only functions:loginConDni

# Deploy de todas las functions del codebase
firebase deploy --only functions

# Deploy de rules + functions juntos (peligroso si rules cambia: puede cortar acceso)
firebase deploy --only firestore:rules,functions
```

### Validación post-deploy obligatoria

**Apenas termine el deploy**, validar:
- Login admin desde la app Flutter en < 5 segundos.
- Login chofer cualquiera, también OK.
- Si alguno falla: rollback inmediato (siguiente sección). No esperar a que se quejen los usuarios.

Errores comunes después de un deploy:
- `iam.serviceAccounts.signBlob denied` → ver tabla en [Login no funciona](#login-no-funciona).
- `permission-denied: ...allUsers Cloud Run Invoker missing` → idem.

---

## Rollback de un deploy malo

### Cloud Functions

```powershell
# Ver versiones desplegadas
gcloud functions list --regions=southamerica-east1

# Rollback a una versión específica de una function
# (Functions Gen2 corren en Cloud Run — el rollback es por revisión)
gcloud run services update-traffic <function-name> --to-revisions=<previous-revision>=100 --region=southamerica-east1
```

Ejemplo concreto si `loginConDni` se rompe:
```powershell
# Listar revisiones
gcloud run revisions list --service=logincondni --region=southamerica-east1
# Volver a la anterior
gcloud run services update-traffic logincondni --to-revisions=logincondni-00012-abc=100 --region=southamerica-east1
```

### Firestore rules

```powershell
# Las rules NO tienen rollback automático.
# Mantener un backup local antes de cada deploy:
cp firestore.rules firestore.rules.backup
firebase deploy --only firestore:rules
# Si algo se rompe:
cp firestore.rules.backup firestore.rules
firebase deploy --only firestore:rules
```

### App Flutter (en producción)

No hay rollback automático para mobile/desktop builds — el usuario tiene que reinstalar la versión anterior. Para desktop la app se distribuye manualmente (`flutter build windows --release`); guardar el `.exe` de la versión estable en OneDrive antes de cada release nueva.

---

## Backup y disaster recovery

Hay dos backups críticos: **Firestore** (datos del negocio) y **`.wwebjs_auth/`** (sesión WhatsApp del bot). Los scripts ya están en el repo; falta programarlos.

### Backup Firestore (`scripts/backup_firestore.ps1`)

**Setup one-time** (hacé esto solo una vez):

```powershell
# 1. Instalar gcloud CLI si no lo tenés:
#    https://cloud.google.com/sdk/docs/install

# 2. Login y proyecto activo:
gcloud auth login
gcloud config set project logisticaapp-e539a

# 3. Crear el bucket de backups (region SA = menor latencia desde AR):
gcloud storage buckets create gs://logisticaapp-backups `
  --project=logisticaapp-e539a `
  --location=southamerica-east1 `
  --uniform-bucket-level-access

# 4. Probar el script una vez manual:
.\scripts\backup_firestore.ps1
# Si OK, debería decir "Backup OK: gs://logisticaapp-backups/2026-..."
```

**Programar** (recomendado: Cloud Scheduler en GCP — corre aunque la PC esté apagada):

```powershell
# Crear job de Cloud Scheduler que invoque el export diariamente a las 03:00 ART:
gcloud scheduler jobs create http firestore-backup-diario `
  --location=southamerica-east1 `
  --schedule="0 3 * * *" `
  --time-zone="America/Argentina/Buenos_Aires" `
  --uri="https://firestore.googleapis.com/v1/projects/logisticaapp-e539a/databases/(default):exportDocuments" `
  --http-method=POST `
  --oauth-service-account-email=<service-account-email> `
  --message-body='{"outputUriPrefix":"gs://logisticaapp-backups"}'
```

(El `<service-account-email>` lo sacás de Firebase Console → Project Settings → Service accounts. Permisos requeridos: `Cloud Datastore Import Export Admin`.)

**Alternativa más simple** si Cloud Scheduler te complica: programar el `.ps1` con Task Scheduler de Windows en la PC casa (ver siguiente sección, mismo patrón).

**Costo**: ~3 centavos USD/mes para una flota chica. El export en sí es gratis; solo paga storage en GCS.

### Backup `.wwebjs_auth/` (`whatsapp-bot/scripts/backup_wwebjs_auth.ps1`)

La sesión es el "estado autenticado" de WhatsApp Web. Si se pierde, hay que reescanear QR desde el celular descartable. El script comprime la carpeta a un zip con timestamp y aplica retención (60 días por default).

**Programar con Task Scheduler** (Windows):

1. Abrir **Programador de tareas** (Task Scheduler).
2. Click en **Crear tarea básica** → nombre: `Backup wwebjs_auth semanal`.
3. **Trigger**: Semanalmente, día y hora a tu elección (recomendado: domingo 03:00 AM).
4. **Acción**: Iniciar un programa.
   - **Programa**: `powershell.exe`
   - **Argumentos**:
     ```
     -NoProfile -ExecutionPolicy Bypass -File "C:\Users\santi\logistica_app_profesional\whatsapp-bot\scripts\backup_wwebjs_auth.ps1"
     ```
5. **Condiciones**: marcar "Despertar el equipo para ejecutar esta tarea" si la PC duerme.
6. **Configuración** → "Si la tarea falla, reintentar cada": 5 minutos, hasta 3 intentos.

**Variables de entorno opcionales** (set en system env vars o pasalas al script):
- `BOT_BACKUP_DIR` — destino del zip. Default `%USERPROFILE%\Backups\bot`.
- `BOT_BACKUP_RETENCION_DIAS` — borra zips más viejos que esto. Default 60.

Para llevar los zips a la nube: el `BOT_BACKUP_DIR` apunta a una subcarpeta dentro de **OneDrive** (que sincroniza solo). Ej:
```powershell
[Environment]::SetEnvironmentVariable('BOT_BACKUP_DIR', "$env:USERPROFILE\OneDrive\Backups\bot", 'User')
```

Logs del backup: `whatsapp-bot/logs/backup.log`.

### `serviceAccountKey.json` y `secrets.json`

Están en **Bitwarden** (vault personal de Santiago). Si Santiago no está disponible, hay que regenerar:

- `serviceAccountKey.json`: Firebase Console → Project Settings → Service accounts → Generate new private key. La key vieja seguirá funcionando hasta que se revoque manualmente.
- `secrets.json`: contenido reconstruible desde el portal Volvo Connect (admin de la cuenta Volvo del cliente).

---

## Sentry — observabilidad

Sentry está integrado en el cliente Flutter. Captura errores y métricas de performance en producción. **El DSN está embebido como `defaultValue`** en `lib/main.dart` (no es un secret crítico — solo permite enviar eventos al proyecto, no leer/borrar datos). Esto significa que **NO necesitás pasar nada** para activarlo: corre activado por default.

### Estado actual

Activo en producción contra el proyecto Sentry de Coopertrans (org `coopertrans` o equivalente). DSN visible en `lib/main.dart`.

### Cómo deshabilitar Sentry temporalmente (dev/local)

```powershell
flutter run -d windows --dart-define=SENTRY_DSN=
```

Pasar `SENTRY_DSN=` (vacío explícito) override el defaultValue → la app corre sin Sentry.

### Cómo rotar el DSN

1. Ir a https://sentry.io → Settings → Projects → tu proyecto → Client Keys (DSN).
2. Generate new key → revoke la vieja.
3. Editar `lib/main.dart`: cambiar el `defaultValue` con el DSN nuevo.
4. Commit + push.

### Cómo cambiar de proyecto Sentry (ej. crear uno nuevo)

1. Crear nuevo proyecto en sentry.io.
2. Copiar el DSN.
3. Editar `lib/main.dart` reemplazando el `defaultValue`.
4. Commit + push.

### Validar en Sentry Console que está funcionando

Corré la app y hacé que tire un error a propósito (ej. login con password mal). En el dashboard Sentry → **Issues** debería aparecer el evento en < 30 segundos. Si no aparece:
- Verificar que el DSN no se haya invalidado.
- Verificar conectividad a `sentry.io` desde la máquina cliente.
- Mirar logs de la app — debería decir `Sentry inicializado (env: production)` al arrancar.

### Configuración actual

- `tracesSampleRate: 0.2` — 20% de transactions trackeadas para perf monitoring. Para una flota chica con uso bajo es razonable; bajar a 0.05 si crece el volumen y los costos de Sentry suben.
- `sendDefaultPii: false` — NO se mandan IPs ni identificadores del usuario sin consentimiento explícito. Importante por compliance AR (Ley 25.326).
- `environment: 'production'` por default — ajustable con `SENTRY_ENV`.

### Cuándo desactivar Sentry

- Durante desarrollo local: `SENTRY_DSN` vacío → modo dev sin Sentry.
- Si sale del free tier (5K events/mes), bajar `tracesSampleRate` o filtrar errores triviales con `beforeSend` en `SentryFlutter.init`.
- Si Sentry falla / cae: la app sigue funcionando (Sentry init fallido no rompe runApp).

### Costo

- Plan free: 5K events/mes. Con flota chica (~57 empleados, errores raros) sobra.
- Si supera, plan Team es ~26 USD/mes.

---

## Otros gotchas operativos (Windows)

### `start_bot.ps1` aborta por package-lock "modificado" pero `git diff` está vacío

Síntoma:
```
ADVERTENCIA: hay cambios sin commitear en el repo:
 M whatsapp-bot/package-lock.json
```
pero al correr `git diff whatsapp-bot/package-lock.json` no muestra nada.

Es un **stat dirty**: `npm install` actualizó el `mtime` del archivo aunque el contenido es idéntico al committeado. Pasa seguido en Windows + npm.

Fix:
```powershell
git restore whatsapp-bot/package-lock.json
git status   # debe decir "working tree clean"
.\whatsapp-bot\scripts\start_bot.ps1
```

`git restore` re-escribe el archivo desde el index. Como el contenido es idéntico, no rompe nada — solo limpia la marca.

### El bot está corriendo pero las notificaciones no llegan a la app

Cliente Flutter: la pantalla "Estado del Bot" muestra heartbeat OK pero los push notifications de admin no llegan. Causa típica: la sesión del admin está cacheando claims viejos. **Logout + login** en la app suele arreglarlo (renueva el JWT con custom claims actuales).

### "Working tree clean" pero `git status` muestra `.claude/` untracked

Eso es el state directory del agent (Claude Code). Está ignorado por `.gitignore` desde el commit `80874b3`. Si igual aparece, tu copia local del repo no tiene ese commit — `git pull` y debería desaparecer.

---

## Comandos rápidos de diagnóstico

```powershell
# === Bot ===
Get-Service SmartLogisticaBot                   # Estado del servicio
Get-Content whatsapp-bot\logs\bot-out.log -Tail 50 -Wait   # Logs en vivo
Get-Content whatsapp-bot\logs\bot-err.log -Tail 50         # Errores

# === Tests (deben pasar antes de cada deploy) ===
flutter test                                    # 58/58 tests cliente
cd whatsapp-bot ; npm test                      # 48/48 tests bot
cd functions ; npm run build                    # tsc limpio

# === Firebase ===
firebase functions:log --lines 100              # logs de TODAS las functions
firebase deploy --only functions:loginConDni    # deploy una sola function
firebase deploy --only firestore:rules          # deploy solo rules

# === Git ===
git log --oneline -20                           # últimos 20 commits
git status -uno                                 # cambios sin .claude/
```

---

## Contactos y secretos

> **Completar antes del primer incidente real**. Estos son los datos que un colaborador necesita para llamar a alguien que sepa.

| Recurso | Dónde / a quién |
|---|---|
| **Santiago** (dueño/dev) | (TODO: agregar teléfono / email) |
| Contacto Vecchi (cliente) | (TODO: agregar contacto del cliente) |
| Bitwarden vault | Cuenta personal de Santiago — `secrets.json`, `serviceAccountKey.json`, password de portal Volvo |
| Firebase Console | https://console.firebase.google.com/project/logisticaapp-e539a |
| GitHub | https://github.com/rodriguezreysantiago/logistica_app_profesional |
| Email Volvo Connect | (TODO: agregar email del contacto técnico de Volvo) |
| Número de WhatsApp del bot | (TODO: agregar número descartable) |
| `ADMIN_PHONES` (whitelist comandos) | En `whatsapp-bot/.env` de la PC casa |

---

## Cómo mantener este documento

- Si resolvés un incidente y **la solución no está acá**, agregala. La próxima persona se ahorra horas.
- Si una sección dice "TODO", es porque no la sabe nadie todavía — completala apenas la sepas.
- No mover esto a Notion ni a Drive. Vive en el repo para que `git blame` muestre quién cambió qué.
