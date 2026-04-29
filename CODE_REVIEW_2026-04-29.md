# Code Review profundo — 2026-04-29

Revisión de bugs de lógica sobre todo el proyecto (cliente Flutter, Cloud Functions, bot Node.js). Hecho por 4 agentes especializados en paralelo, deduplicado y priorizado.

**Resumen:**

| Severidad | Cantidad |
|---|---|
| 🔴 Crítico | 7 |
| 🟠 Alto | 11 |
| 🟡 Medio | 10 |
| 🟢 Bajo | 4 |

---

## 🔴 CRÍTICO — Arreglar antes de cerrar la sesión

### C1. `PrefsService.init()` no se espera antes del primer build
**Archivo:** `lib/main.dart` + flujo general.
**Problema:** Si algún widget lee `PrefsService.dni` (getter sync) antes de que `init()` complete, recibe string vacío. El cache en memoria todavía tiene los defaults (`''`). Pasa típicamente en LoginScreen leyendo `lastDni`.
**Fix:** Verificar que `await PrefsService.init()` se llame **antes** de `runApp()`. Si ya está, agregar un guard: que `init()` sea idempotente y mantenga un completer que cualquier acceso pueda esperar.

### C2. `LoginScreen` autofocus falla si init() todavía no terminó
**Archivo:** `lib/features/auth/screens/login_screen.dart:42`
**Problema:** Lee `PrefsService.lastDni` en `initState()` que es sync. Si es la primera vez en la sesión y el disco está lento, devuelve `''` y el campo nunca recibe el último DNI.
**Fix:** Hacer `await` de `PrefsService.init()` en `main.dart` antes de `runApp()`.

### C3. Race condition: fast path Volvo no obtiene `serviceDistance`
**Archivo:** `lib/features/vehicles/services/vehiculo_manager.dart:99-143` (`_executeSync`)
**Problema:** Si `_buscarEnCache(vin)` devuelve odómetro válido, retorna sin llamar `traerTelemetria()`. Esto significa que `serviceDistanceKm` queda `null` y `_evaluarMantenimiento(null)` sale en línea 200 sin actualizar nada. Un tractor que cruzó a vencido **no genera notificación**.
**Fix:** Forzar siempre `traerTelemetria()` al menos para tractores Volvo, o hacer una segunda llamada solo para `serviceDistance` cuando se toma el fast path.

### C4. Botón "Service hecho" no limpia `MANTENIMIENTOS_AVISADOS`
**Archivo:** `lib/features/vehicles/screens/admin_mantenimiento_screen.dart:507-511`
**Problema:** El dialog actualiza `ULTIMO_SERVICE_KM` y `ULTIMO_SERVICE_FECHA` en `VEHICULOS`, pero NO toca `MANTENIMIENTOS_AVISADOS/{patente}`. El badge del shell sigue mostrando VENCIDO hasta el próximo ciclo de AutoSync (60s).
**Fix:** Después del update a `VEHICULOS`, hacer `set/merge` en `MANTENIMIENTOS_AVISADOS/{patente}` con `ultimo_estado: 'OK'` y `ultimo_service_distance_km: AppMantenimiento.intervaloServiceKm`.

### C5. `EmpleadoActions.unidad` puede dejar unidad fantasma en OCUPADO
**Archivo:** `lib/features/employees/services/empleado_actions.dart:476-490` (`procesarCambio`)
**Problema:** El `batch.commit()` marca la unidad nueva como OCUPADO y actualiza el empleado. **Después** del batch, hace un `update()` separado para liberar la unidad anterior. Si ese update falla (red, permisos, doc inexistente), **la unidad anterior queda OCUPADO indefinidamente** sin que nadie la pueda asignar.
**Fix:** Incluir el update de la unidad anterior dentro del mismo `batch` antes del commit. Atómico o nada.

### C6. Bot WhatsApp: fuera de horario congela toda la cola por 15 min
**Archivo:** `whatsapp-bot/src/index.js:66-75` (`procesarSiguiente`)
**Problema:** Cuando detecta que NO es horario hábil, hace `await sleep(15 min)` con `procesando=true`. Mientras duerme, ningún otro doc puede procesarse aunque hayan llegado nuevos. Si entran 50 docs durante esos 15 min, todos esperan inútilmente.
**Fix:** Antes del sleep, hacer `procesando = false` y `return` (no recolar). El polling siguiente lo va a re-detectar cuando ya sea horario hábil.

### C7. Bot WhatsApp: idempotencia de service rota en límite de 50k km
**Archivo:** `whatsapp-bot/src/cron.js:356-360`
**Problema:** Cuando no hay `ULTIMO_SERVICE_KM` manual, el bot ancla el ciclo con `Math.floor(KM_ACTUAL / 50000) * 50000`. Cuando un tractor pasa de 49999 km a 50001 km, el ancla cambia de `0` a `50000` → el id del histórico es distinto → se manda **otro aviso** del mismo nivel sin que se haya regularizado nada.
**Fix:** Si `ULTIMO_SERVICE_KM` no está cargado, no encolar avisos (o encolar solo "vencido" cuando `serviceDistance ≤ 0`). El admin debería cargar el último service para que la idempotencia funcione bien. Alternativamente, anclar al múltiplo redondeado de KM_ACTUAL — pero generaría rebotes en el límite.

---

## 🟠 ALTO

### A1. Migración SharedPreferences → Secure: bool null se serializa como `"null"`
**Archivo:** `lib/core/services/prefs_service.dart:100-102`
**Problema:** `viejoIsLogged.toString()` cuando es `null` da `"null"` (string), que después no matchea con `loggedRaw == 'true'`. Tabarra del cache quedaría inconsistente.
**Fix:** `if (viejoIsLogged != null) { _secure.write(... viejoIsLogged.toString()); }`. Ya hay guards similares para los strings — falta para el bool.

### A2. `intentos` en LOGIN_ATTEMPTS — type coercion frágil
**Archivo:** `functions/src/index.ts:327` (`registrarIntentoFallido`)
**Problema:** Cast `as number | undefined` sin validar tipo real. Si el campo viene como string (corrupción/migración), la comparación `intentos >= MAX_INTENTOS_FALLIDOS` puede dar resultados inesperados.
**Fix:** Forzar `Number(data.intentos ?? 0)` antes de comparar.

### A3. `auditLogWrite` acepta `detalles: null` y graba campo null en Firestore
**Archivo:** `functions/src/index.ts:836-852`
**Problema:** El cliente nunca debería mandar `detalles: null` (omite el campo cuando está vacío), pero la function lo acepta silenciosamente y escribe `detalles: null` ocupando espacio. Inconsistencia client/server.
**Fix:** Validación más estricta: `if (detalles != null && typeof detalles === 'object' && !Array.isArray(detalles) && Object.keys(detalles).length > 0)`.

### A4. `RoleGuard` lee rol del cache (no del JWT actual)
**Archivo:** `lib/shared/widgets/guards/role_guard.dart:19-29`
**Problema:** Usa `PrefsService.rol` del cache. Si un admin cambia el rol de un usuario en EMPLEADOS, ese usuario sigue accediendo a pantallas admin hasta que se loguee de nuevo (~1h máx, hasta que expire el JWT).
**Comentario:** Está documentado como decisión consciente en ESTADO_PROYECTO. Si se quiere endurecer, usar `currentUser.getIdTokenResult(true)` para forzar refresh.
**Fix opcional:** Listener a cambios de EMPLEADOS, o revalidar el token cada N minutos cuando hay actividad.

### A5. Plan B vs API mixto — datos stale sin versioning
**Archivo:** `lib/features/vehicles/services/vehiculo_repository.dart:68-98`
**Problema:** Si Volvo activa `serviceDistance` el día Y, tenemos dos fuentes posibles: API y manual. La pantalla prioriza manual sobre API; pero si el manual es viejo, prioriza dato incorrecto sobre uno fresco del API.
**Fix:** Sumar campos `SERVICE_DISTANCE_FUENTE` (`'API'|'MANUAL'`) y `SERVICE_DISTANCE_AT` (timestamp). La pantalla elige por timestamp más reciente. O simplificar: si el API entrega el campo, **siempre** ganarle al manual.

### A6. `_evaluarMantenimiento` no se llama cuando admin marca "service hecho"
**Archivo:** `lib/features/vehicles/services/vehiculo_manager.dart:196-255`
**Problema:** Igual que C4 desde otro ángulo. El estado en `MANTENIMIENTOS_AVISADOS` queda desactualizado.
**Fix:** Después del update desde "Service hecho", forzar reevaluación. O implementar el fix C4 que es escribir directo el estado OK.

### A7. `AdminRevisiones._procesarDecision` — cierra sheet antes de confirmar éxito
**Archivo:** `lib/features/revisions/screens/admin_revisiones_screen.dart:321-387`
**Problema:** Cierra el sheet con `navigator.pop()` ANTES del `delete()` o sin esperar confirmación. Si el delete falla, el admin ve "operación aprobada" pero el doc sigue ahí.
**Fix:** Hacer el delete primero, después del éxito cerrar sheet y mostrar feedback. Y solo registrar AuditLog tras éxito real.

### A8. Bot WhatsApp: match de teléfono por sufijo es vulnerable
**Archivo:** `whatsapp-bot/src/message_handler.js:56-64`
**Problema:** Si dos choferes tienen los últimos 10 dígitos iguales (caso raro pero posible con números cortos o sin código de país), `endsWith` matchea contra el primero del loop. Documentos del segundo se atribuyen al primero.
**Fix:** Match exacto contra teléfono normalizado, no por sufijo.

### A9. Bot WhatsApp: shutdown grace 10s < delay 60s
**Archivo:** `whatsapp-bot/src/index.js:234-253`
**Problema:** Si el admin reinicia el bot mientras un envío está en delay (de 15-60s), 10s no alcanzan. El proceso se mata, el doc queda en `PROCESANDO` para siempre.
**Fix:** Subir grace a `DELAY_MAX_MS + 10000` (~70s). O al recibir SIGTERM, marcar el doc en proceso de vuelta a `PENDIENTE` antes de salir.

### A10. `aviso_service_builder.build()` no valida NaN/null
**Archivo:** `whatsapp-bot/src/aviso_service_builder.js:43-44`
**Problema:** Si `serviceDistanceKm` es NaN o `patente` es null, genera mensajes tipo "el tractor null necesita SERVICE en NaN km".
**Fix:** Guard inicial: `if (!patente || !Number.isFinite(serviceDistanceKm)) return null` y manejar el null en el caller.

### A11. `AdminBotBandejaScreen` `limit(50)` sin paginación
**Archivo:** `lib/features/whatsapp_bot/screens/admin_bot_bandeja_screen.dart:159-164`
**Problema:** Si hay 100+ respuestas ambiguas sin procesar, las primeras 50 nunca se ven (orderBy descending). El admin puede creer que está al día.
**Fix:** Indicar visualmente "+ N pendientes más antiguos" cuando hay más de 50. O paginación con cursor.

---

## 🟡 MEDIO

### M1. Race condition en chequeo de bloqueo del login
**Archivo:** `functions/src/index.ts:145-153` (`loginConDni`)
**Problema:** Lectura de `LOGIN_ATTEMPTS` fuera de transacción. Dos requests paralelos pueden saltar el bloqueo si pegan en el momento exacto.
**Fix:** Mover el check al inicio de `runTransaction`.

### M2. `AuthGuard` initialData puede ser null aunque haya sesión persistida
**Archivo:** `lib/shared/widgets/guards/auth_guard.dart:65`
**Problema:** En Android/iOS Firebase Auth tarda ~500ms en cargar la sesión. `currentUser` en initial puede ser null y dispara redirect al login antes del grace period.
**Fix:** Ya hay grace period de 1.5s para Windows. Verificar que aplica a todas las plataformas, no solo desktop.

### M3. `storage_service.subirArchivo` rethrow pierde tipo original
**Archivo:** `lib/core/services/storage_service.dart:57-59`
**Problema:** Wrap todas las excepciones como `Exception('Error en FirebaseStorage: $e')`. Pierde info para diagnóstico (timeout vs permisos vs server error).
**Fix:** `rethrow` original, o preservar `e.runtimeType` en el mensaje.

### M4. Circuit breaker de VolvoApiService nunca se resetea
**Archivo:** `lib/features/vehicles/services/volvo_api_service.dart:121-216`
**Problema:** Tras 3 fails de auth, `_consecutive401` queda en 3 hasta el próximo 200. Si las credenciales se quedan caducadas, el cliente queda con circuit abierto hasta restart manual.
**Fix:** Reset cada N minutos (ej. 60min), o al volver a foreground (lifecycle).

### M5. `telemetriaSnapshotScheduled` aborta sin retry si flota vacía
**Archivo:** `functions/src/index.ts:608-610`
**Problema:** Si Volvo devuelve `vehicleStatuses: []`, el cron sale sin escribir nada. No diferencia "no hay datos" de "Volvo respondió mal".
**Fix:** Agregar retry con backoff (3 intentos) antes de abortar.

### M6. `actualizarTelemetria` check `> 2` después de timestamp
**Archivo:** `lib/features/vehicles/services/vehiculo_repository.dart:88`
**Problema:** El check `if (updates.length <= 2) return` está después de agregar `ULTIMA_SINCRO` y `SINCRO_TIPO`. Si solo hay esos dos campos (ningún dato útil), no escribe **nada**, ni el timestamp.
**Fix:** Si la idea era "no escribir si no hay datos nuevos", está bien. Si la idea era "actualizar siempre el timestamp aunque no haya datos", cambiar el check.

### M7. `_resolverServiceDistance` no valida `ULTIMO_SERVICE_KM > KM_ACTUAL`
**Archivo:** `lib/features/vehicles/screens/admin_mantenimiento_screen.dart:174-190`
**Problema:** Si admin carga manualmente un valor mayor que el odómetro actual (typo), el cálculo da resultado positivo grande pero sin sentido. Badge muestra OK con "150.000 km al próximo".
**Fix:** En `serviceDistanceDesdeManual`, devolver null si `ultimoServiceKm > kmActual`.

### M8. `_aprobarDocumento` validación incompleta
**Archivo:** `lib/features/revisions/screens/admin_revisiones_screen.dart:448-453`
**Problema:** Valida `idDoc.isEmpty || idDestino.isEmpty || campoVencimiento.isEmpty`. Falta `coleccion.isEmpty`.
**Fix:** Sumar al `if`.

### M9. Bot WhatsApp: zona horaria hardcoded en `enHorarioHabil`
**Archivo:** `whatsapp-bot/src/humano.js:21`
**Problema:** Usa `getHours()` local del server. Si el server cambia de zona o no es ART, los avisos salen a horas raras.
**Fix:** Documentar que el server tiene que estar en zona Argentina, o leer zona explícita de `.env`.

### M10. Bot WhatsApp: cron reconstruye índice de empleados cada ciclo
**Archivo:** `whatsapp-bot/src/cron.js:155-171`
**Problema:** Para flotas grandes (1000+) consume cuota Firestore. No es un bug, es ineficiencia.
**Fix opcional:** Cachear con TTL.

---

## 🟢 BAJO

### B1. `notification_service.mostrarAvisoAdmin` ID no determinístico
**Archivo:** `lib/core/services/notification_service.dart:189`
**Problema:** Usa `DateTime.now().millisecondsSinceEpoch.remainder(100000)`. Si se llama dos veces para el mismo evento, el admin ve dos notificaciones.
**Fix:** Hash determinístico por día/evento.

### B2. `MantenimientoBadge` round() puede esconder cruce de umbral
**Archivo:** `lib/features/vehicles/widgets/mantenimiento_badge.dart:53`
**Problema:** Si `serviceDistanceKm = 4999.9`, `clasificar()` devuelve `atencion` (≤5000) pero el badge muestra "5000 km". Coherente pero puede confundir si se compara con el chip resumen.
**Fix:** Usar `floor()` o `ceil()` consistentemente, o aclarar con texto.

### B3. `_tiempoRelativo` no maneja fechas futuras en card
**Archivo:** `lib/features/vehicles/screens/admin_mantenimiento_screen.dart:548-562`
**Problema:** Si el admin pone una fecha futura por error, devuelve "fecha futura" pero el resto de la card sigue normal.
**Fix:** Validar en el dialog de "Service hecho" que la fecha ≤ hoy.

### B4. `aviso_builder.extraerPrimerNombre` retorna null si solo hay un token
**Archivo:** `whatsapp-bot/src/aviso_builder.js:126-133`
**Problema:** Si el `NOMBRE` es solo "PEREZ" sin nombre, devuelve null y el saludo es "Hola" sin nombre. Cosmético.
**Fix:** No es bug, es el comportamiento intencional para evitar saludar con apellido.

---

## Priorización de fixes

**Hacer YA (esta semana):**
- C1, C2 — race conditions de PrefsService (puede causar logout fantasma)
- C3, C4, A6 — bugs de mantenimiento Volvo (que recién implementamos hoy)
- C5 — `EmpleadoActions.unidad` (corrupción de estado de flota)
- C6 — bot fuera de horario (afecta envíos)
- A7 — revisiones (consistencia de datos)

**Antes de poner el bot en producción real:**
- C7 — idempotencia service del bot
- A8 — match de teléfono
- A9 — grace period del shutdown
- A10, A11 — UX del bot (paginación, validaciones)

**Eventualmente:**
- A1-A5 — issues menores de migración y rate limit
- M1-M10 — race conditions edge case e ineficiencias
- B1-B4 — cosméticos
