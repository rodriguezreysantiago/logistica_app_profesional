# Demo dry-run — Checklist pre-presentación

Antes de mostrarle la app a Vecchi (o de poner cualquier flujo en producción real), pasá por este checklist con la app abierta. Cada flujo está pensado para detectar trabas, mensajes raros, datos inconsistentes o sorpresas que rompan la primera impresión.

**Cómo usarlo**: ejecutá uno por uno, anotá lo que veas raro en una libreta o en el repo, y arreglá antes de la demo.

> Asume sesión iniciada como **admin** (vos), proyecto Firebase activo es `coopertrans-movil` (sa-east1), bot NSSM corriendo. Si algo no anda, revisá `RUNBOOK.md`.

---

## Flujo 1 — Login admin (90 segundos)

1. Abrí la app desde el atajo (`flutter run -d windows` o el `.exe` build).
2. Ingresá tu DNI + password.
3. **Validá**:
   - [ ] Login exitoso en < 5 segundos.
   - [ ] Pantalla de inicio carga sin errores en consola (mirá la terminal del `flutter run`).
   - [ ] Saludo dice tu nombre (no "Sin nombre" ni "Hola, USUARIO").
   - [ ] KPIs (empleados activos, vehículos, vencimientos) muestran números coherentes.
4. **Cerrá sesión** y volvé a entrar para asegurar que el flow de logout funciona.
5. **Probá login con DNI mal**: poné un DNI inexistente. Mensaje debería decir "El usuario no existe o el DNI es incorrecto." (no stack trace).
6. **Probá password mal 5 veces**: la 6ta debería decir "Cuenta bloqueada temporalmente por X minutos." (rate limit funcionando).

---

## Flujo 2 — Personal: crear, editar, asignar (5 min)

1. Ir a **Personal**.
2. Click **+ NUEVO**. Crear un chofer ficticio:
   - DNI inventado (ej. `99999999`).
   - Nombre: `PRUEBA DEMO TEST`.
   - Password.
   - Rol: CHOFER, Área: MANEJO.
   - Demás campos opcionales.
3. **Validá al guardar**:
   - [ ] SnackBar verde "Chofer creado" o similar.
   - [ ] El nuevo chofer aparece en la lista.
4. **Tap en el chofer** → ver detalle. **Validá**:
   - [ ] Datos correctos.
   - [ ] Foto placeholder (ícono).
5. **Editar un dato** (ej. teléfono). Validá SnackBar verde + dato actualizado.
6. **Asignar tractor**: tocar "Tractor asignado" → seleccionar uno libre. Validá:
   - [ ] El tractor pasa a OCUPADO.
   - [ ] El chofer ahora muestra esa patente.
7. **Re-asignar el MISMO tractor**: vuelve a tocar y elegí el mismo. **Importante**: no debe romperse el estado (fix `13bd44c` de la sesión).
8. **Desasignar**: tocar y elegir "—" o "ninguno". El tractor vuelve a LIBRE.
9. **Eliminar el chofer de prueba**.

---

## Flujo 3 — Flota: alta de vehículo + Volvo (5 min)

1. Ir a **Flota** → tab Tractores.
2. **Validá** que se ven los 56 vehículos importados, con sus KPIs (KM, vencimientos).
3. Click **+ NUEVO** → crear un tractor ficticio:
   - Patente: `XX999XX`.
   - Marca/modelo: cualquiera.
   - VIN: dejar vacío (no es Volvo real).
4. Guardar → validar SnackBar OK.
5. **Tap en un tractor REAL Volvo** (con VIN cargado) → ver detalle. **Validá**:
   - [ ] Pestaña / sección **Telemetría**: trae odómetro, % combustible, autonomía.
   - [ ] Si dice "Sin datos" → puede ser que `volvoProxy` falló. Revisar logs.
   - [ ] Botón **FORZAR SINCRO VOLVO**: presionar. Debe actualizar el KM en tiempo real.
6. **Eliminar el tractor de prueba**.

---

## Flujo 4 — Vencimientos: subir comprobante + auditoría (4 min)

1. Ir a **Vencimientos**.
2. **Validá** las 3 sub-pantallas (Choferes, Chasis, Acoplados):
   - [ ] Cada una muestra los vencimientos próximos a vencer (≤ 60 días).
   - [ ] Items ordenados por urgencia (vencidos primero).
   - [ ] Badges con colores correctos (rojo / naranja / verde).
3. **Tap en un vencimiento** → editor sheet. **Validá**:
   - [ ] Fecha actual se muestra.
   - [ ] Botón "Subir comprobante" funciona (file picker).
   - [ ] Cambiar fecha guarda OK.

---

## Flujo 5 — Bot WhatsApp + Estado del Bot (3 min)

1. Ir a **Estado del Bot**.
2. **Validá**:
   - [ ] Banner verde (bot vivo).
   - [ ] Heartbeat reciente (< 2 min).
   - [ ] Cards de cola (pendientes, procesando, enviados, errores) con números coherentes.
   - [ ] Tap en cada card abre la cola filtrada por ese estado.
3. **Probá comando por WhatsApp**: desde tu teléfono mandá `/estado` al número del bot. Validá:
   - [ ] Bot responde con resumen del estado.

---

## Flujo 6 — Reportes Excel (3 min)

1. Ir a **Reportes**.
2. **Validá los 3 reportes**:
   - [ ] **Flota**: descarga Excel. Abrí, verificá que las celdas con fechas dicen `DD/MM/AAAA` (no `YYYY-MM-DD` ni `2026-05-30T...Z`).
   - [ ] **Checklist**: idem.
   - [ ] **Consumo**: rango de fechas, descarga, columnas correctas.

---

## Flujo 7 — Login chofer + ver mis vencimientos (3 min)

1. Logout admin.
2. Login con DNI + password de un chofer real.
3. **Validá**:
   - [ ] Pantalla del chofer ve solo sus datos (no datos de otros).
   - [ ] **Mis Vencimientos** lista los 7 papeles personales.
   - [ ] **Mi Equipo** muestra el tractor + enganche asignados (si tiene).
   - [ ] Telemetría Volvo del tractor visible.

---

## Flujo 8 — Casos borde rápidos

- [ ] Login con password con `ñ` o tilde (caracteres ARG comunes).
- [ ] Subir foto de perfil > 5MB → debería rechazar o redimensionar (no crashear).
- [ ] Cortar Wi-Fi a la mitad de subir un archivo → SnackBar amigable, no stack trace.
- [ ] Pantalla mucho rato sin tocar → cuando volvés, no debe pedir login otra vez (el JWT dura 1h, suficiente).

---

## Si algo se rompe

- Anotá el flujo exacto que reprodujo el bug.
- Mirá la terminal del `flutter run` para errores en consola.
- Si es un SnackBar feo (con `$e` crudo), arreglar usando el helper `AppFeedback.errorTecnicoOn` (ver `lib/shared/utils/app_feedback.dart`).
- Si es performance / lentitud, mirar `RUNBOOK.md` sección "Comandos rápidos de diagnóstico".

## Cuándo NO presentar

Si en este checklist:
- Algún SnackBar muestra texto crudo `FirebaseException(plugin: ...)`
- Algún flujo te tira una pantalla en blanco
- Algún número en KPIs es notoriamente incorrecto
- La telemetría Volvo dice "Sin datos" en tractores que sabes que tienen VIN cargado

→ Resolver antes de la demo. Estos detalles son los que el cliente nota primero.
