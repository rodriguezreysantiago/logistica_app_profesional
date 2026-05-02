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
.\stop_bot.ps1   # auto-eleva UAC, espera grace period 90s
.\start_bot.ps1  # hace git pull + npm install + nssm start
```

`stop_bot.ps1` hace stop ordenado respetando el `grace_shutdown` del bot (deja terminar mensajes en vuelo). `start_bot.ps1` rechaza arrancar si hay cambios sin commitear (proteger producción).

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
| `permission-denied: ...allUsers Cloud Run Invoker missing` | Después de un deploy nuevo, Cloud Run quitó el `allUsers` invoker | `gcloud run services add-iam-policy-binding logincondni --region=us-central1 --member="allUsers" --role="roles/run.invoker"` |
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

## Rollback de un deploy malo

### Cloud Functions

```powershell
# Ver versiones desplegadas
gcloud functions list --regions=us-central1

# Rollback a una versión específica de una function
# (Functions Gen2 corren en Cloud Run — el rollback es por revisión)
gcloud run services update-traffic <function-name> --to-revisions=<previous-revision>=100 --region=us-central1
```

Ejemplo concreto si `loginConDni` se rompe:
```powershell
# Listar revisiones
gcloud run revisions list --service=logincondni --region=us-central1
# Volver a la anterior
gcloud run services update-traffic logincondni --to-revisions=logincondni-00012-abc=100 --region=us-central1
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

### Firestore — backup automático recomendado

**No está activado todavía** (item #7 del backlog del 1-mayo). Lo correcto es activar export programado a GCS:

```powershell
gcloud firestore export gs://<bucket-backups>/$(Get-Date -Format yyyy-MM-dd) `
  --project=<project-id>
```

Programar con Cloud Scheduler una vez al día. Está dentro del free tier para una flota chica.

### Sesión `.wwebjs_auth/`

Esta carpeta es el "estado autenticado" de WhatsApp Web del bot. Si se pierde, hay que reescanear el QR — y como el QR se escanea desde el celular descartable, también hay que tener ese celular disponible.

```powershell
# Backup manual (mientras no esté automatizado):
$fecha = Get-Date -Format yyyy-MM-dd
Compress-Archive `
  -Path C:\Users\santi\logistica_app_profesional\whatsapp-bot\.wwebjs_auth `
  -DestinationPath "C:\Users\santi\Backups\bot_wwebjs_auth_$fecha.zip"
```

Ideal: tarea programada de Windows que corra eso semanalmente y suba el zip a OneDrive.

### `serviceAccountKey.json` y `secrets.json`

Están en **Bitwarden** (vault personal de Santiago). Si Santiago no está disponible, hay que regenerar:

- `serviceAccountKey.json`: Firebase Console → Project Settings → Service accounts → Generate new private key. La key vieja seguirá funcionando hasta que se revoque manualmente.
- `secrets.json`: contenido reconstruible desde el portal Volvo Connect (admin de la cuenta Volvo del cliente).

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
