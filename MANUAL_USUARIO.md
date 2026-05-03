# Manual de usuario — Coopertrans Móvil

Guía para los usuarios finales de la app. Está dividida por **rol** porque cada uno ve y puede hacer cosas distintas.

> **Nota**: este manual cubre la app desde el punto de vista del usuario. Para temas técnicos (instalación, deploy, infraestructura) ver [`README.md`](README.md) y [`ESTADO_PROYECTO.md`](ESTADO_PROYECTO.md). Para resolver incidentes en producción ver [`RUNBOOK.md`](RUNBOOK.md).

---

## ¿Qué hace la app?

Coopertrans Móvil centraliza la gestión operativa de una empresa de transporte:

- **Personal**: legajos de choferes y administrativos, papeles personales con vencimientos (licencia, preocupacional, ART, etc.).
- **Flota**: tractores y enganches (bateas, tolvas, etc.), vencimientos del vehículo (RTO, seguro, extintores).
- **Asignación**: qué chofer maneja qué tractor + qué enganche.
- **Revisiones**: el chofer carga un comprobante de renovación → el admin aprueba/rechaza.
- **Telemetría Volvo**: km, combustible y autonomía en tiempo real para tractores Volvo.
- **Avisos automáticos por WhatsApp**: el bot avisa a cada chofer cuando un papel está por vencer.
- **Reportes Excel**: flota, novedades de checklist, consumo de combustible.

---

## Perfiles (roles)

La app tiene 4 roles. Cada uno con permisos distintos:

| Rol | Quién es | Qué ve |
|---|---|---|
| **CHOFER** | Empleado de manejo con tractor asignado | Sus vencimientos personales + su unidad asignada (tractor + enganche) |
| **PLANTA** | Empleado sin vehículo (planta, taller, gomería) | Solo sus vencimientos personales |
| **SUPERVISOR** | Mando medio | Gestiona personal/flota/vencimientos/revisiones/bot. NO crea admins |
| **ADMIN** | Control total | Todo lo del SUPERVISOR + crear admins, cambiar roles, ver auditoría |

Cuando un admin crea un nuevo empleado, define su **rol** y **área** (MANEJO/ADMINISTRACION/PLANTA/TALLER/GOMERIA — solo informativo, no afecta permisos).

---

## Cómo iniciar sesión

1. Abrí la app.
2. Ingresá tu **DNI** (sin puntos, solo dígitos) y tu **contraseña**.
3. Tocá **INGRESAR**.

**Si no recordás la contraseña**: pedile al admin que te la resetee desde "Personal" (no hay auto-recovery por mail por ahora — los choferes no tienen email cargado).

**Si te equivocás 5 veces seguidas**: la cuenta queda bloqueada **15 minutos**. Esperá o pedile al admin que limpie el bloqueo manualmente.

---

## ¿Soy CHOFER? — Tu día a día

Pantalla principal después de login:

### Mis Vencimientos

Lista de tus papeles personales (licencia, preocupacional, ART, manejo defensivo, F.931, seguro de vida, sindicato) ordenados por urgencia. Cada item muestra:
- **Días restantes** o "VENCIDO" en color (rojo / naranja / verde).
- **Botón "Subir"** para enviar el comprobante de renovación.

**Cómo renovar un papel**:
1. Tocá el papel.
2. Tipeá la fecha del nuevo carnet (formato `DD/MM/AAAA`).
3. Tocá **Subir comprobante** → elegí foto (cámara o galería) o PDF.
4. Si la foto está bien iluminada, podés tocar **Detectar fecha** y la app la lee sola con OCR (no es 100% confiable — siempre revisá la fecha antes de confirmar).
5. **Confirmar**. La solicitud queda **EN REVISIÓN** hasta que el admin la apruebe.

### Mi Equipo

Muestra el tractor + enganche asignados (si tenés). Para cada uno verás:
- Patente y datos básicos.
- Vencimientos del vehículo.
- Telemetría en tiempo real (solo tractores Volvo): km, % combustible, autonomía estimada.

**Si querés cambiar de unidad**: tocá **Solicitar cambio** → seleccioná la nueva → se manda al admin para que la apruebe. Mientras tanto, seguís con la actual.

### Notificaciones

La app te recuerda los vencimientos próximos con notificaciones push (si las tenés permitidas). Además, el bot te manda un WhatsApp 30, 15, 7, 1 días antes y el día del vencimiento.

**Si querés no recibir más WhatsApp** (opt-out): pedile al admin que active `BOT_OPT_OUT=true` en tu legajo. Las notificaciones push de la app igual te llegan.

---

## ¿Soy ADMIN o SUPERVISOR? — Tu día a día

Después de login ves el **Panel Admin** con KPIs en tiempo real:
- Empleados activos
- Vehículos asignados
- Vencimientos vencidos / próximos a vencer (≤ 7 días, ≤ 30 días)
- Revisiones pendientes (acción requerida)

### Tareas frecuentes

**Aprobar una revisión** (lo más común):
1. Tocá **Revisiones** o el KPI "Revisiones pendientes".
2. Vas a ver una lista de solicitudes con foto/PDF del comprobante.
3. Verificá la fecha y el documento.
4. **Aprobar** o **Rechazar**:
   - Aprobar → la fecha del papel se actualiza, el chofer queda renovado, la solicitud se borra.
   - Rechazar → tipeá motivo (lo ve el chofer). La solicitud se borra.

**Crear un nuevo empleado**:
1. **Personal** → **+ NUEVO**.
2. Completá DNI, nombre (formato APELLIDO NOMBRE), contraseña, rol, área.
3. (Opcional) Apodo si el algoritmo de saludo del bot no toma bien el nombre.
4. (Opcional) Teléfono — necesario si va a recibir avisos por WhatsApp.
5. Guardar.

**Asignar tractor/enganche a un chofer**:
1. **Personal** → tocá el chofer → **Asignación**.
2. Tocá "Tractor asignado" o "Enganche asignado".
3. Elegí una unidad LIBRE de la lista.
4. La unidad pasa a OCUPADO automáticamente.

**Sumar un vehículo nuevo a la flota**:
1. **Flota** → tab del tipo (Tractor, Batea, Tolva, etc.) → **+ NUEVO**.
2. Patente (sin guiones, en mayúsculas), marca, modelo, año, VIN (si es Volvo), KM inicial.
3. Guardar.

**Ver telemetría Volvo de un tractor**:
1. **Flota** → tractores → tap en uno con VIN cargado.
2. Sección **Telemetría**: km, % combustible, autonomía estimada (datos en vivo desde Volvo Connect).
3. Botón **FORZAR SINCRO VOLVO** si querés actualizar al instante.
4. Botón **DIAGNÓSTICO** si los datos no aparecen — muestra el JSON crudo del API y te indica qué campo falta.

**Generar un reporte Excel**:
1. **Reportes** → elegí el tipo:
   - **Flota**: lista completa de unidades con sus vencimientos.
   - **Checklist**: novedades reportadas por choferes.
   - **Consumo**: combustible por unidad en un rango de fechas.
2. La app descarga el `.xlsx` y lo abre con tu Excel/LibreOffice.

**Pausar el bot WhatsApp** (ej. fin de semana largo):
1. **Estado del Bot** → toggle **Kill-switch**.
2. Mientras está pausado, los avisos quedan en cola y se procesan al reanudar.

**Diagnosticar el bot**:
1. **Estado del Bot** → ahí ves heartbeat, cola pendientes/procesando, último error, último ciclo del cron.
2. Si el banner está rojo / sin heartbeat > 2 min, el bot está caído. Ver [`RUNBOOK.md`](RUNBOOK.md).

**Comandos del bot por WhatsApp** (para vos como admin):
Desde tu teléfono mandá al número del bot:
- `/estado` — resumen del bot.
- `/pausar 24h` — pausar X tiempo.
- `/reanudar` — quitar pausa.
- `/forzar-cron` — disparar avisos ahora sin esperar el cron.
- `/ayuda` — ver comandos.

---

## Buscador rápido (Ctrl+K)

Desde **cualquier pantalla**, presioná `Ctrl+K` (Windows) o `Cmd+K` (Mac):
- Buscás por nombre de chofer, patente o trámite.
- Atajo para saltar directo a la ficha sin navegar.
- Funciona offline en cache si ya cargaste la lista una vez.

---

## Términos que vas a ver

| Término | Qué significa |
|---|---|
| **Tractor** | El cabezal motor que tracciona — ej. Volvo FH, Scania |
| **Enganche** | Lo que tracciona el tractor — batea, tolva, bivuelco, tanque, acoplado (legacy) |
| **Patente** | Identificador del vehículo (en doc de Firestore es la clave) |
| **VIN** | Código único de 17 caracteres del tractor — lo necesita Volvo Connect |
| **RTO** | Revisión Técnica Obligatoria del vehículo |
| **Preocupacional** | Examen médico que cada empleado renueva periódicamente (antes era "Psicofísico") |
| **F.931** | Formulario AFIP de aportes (renovación anual) |
| **Service preventivo** | Mantenimiento programado del tractor cada 50.000 km |
| **Cuenta bloqueada** | 5+ intentos de login fallidos seguidos → 15 min de espera |

---

## Si algo no funciona

1. **App lenta o cuelga**: cerrá completamente y reabrí.
2. **Pantalla en blanco después de login**: cerrá la app, esperá 30 seg, volvé a entrar.
3. **No me llegan WhatsApp del bot**: avisale al admin (puede que el bot esté pausado o con error).
4. **Telemetría Volvo dice "Sin datos"**: probá tocar **FORZAR SINCRO VOLVO**. Si sigue sin datos, avisale al admin.
5. **No puedo subir un archivo**: verificá que tenga menos de 10 MB y sea imagen (JPG, PNG) o PDF.
6. **Otro problema**: avisale al admin con un screenshot de la pantalla.

---

## Privacidad

- Tus datos personales (DNI, vencimientos, fotos) se guardan en Firestore (Google Cloud, región São Paulo).
- Los archivos (comprobantes, fotos) se guardan en Firebase Storage.
- El bot manda WhatsApp solo al número que cargó el admin, y solo dentro de horario hábil (lunes a viernes 8:00–18:00 ART, no envía sábados/domingos/feriados nacionales).
- Si querés ejercer tu derecho de acceso/rectificación/baja (Ley 25.326 AR), pedile al admin.
