# Auditoría de código — Logística App Profesional

**Fecha:** 28 de abril de 2026
**Proyecto:** `logistica_app_profesional` (Flutter multiplataforma · Firebase · Provider)
**Alcance:** seguridad, arquitectura, calidad de código y dependencias
**Archivos analizados:** 61 `.dart` (~13.7k líneas) + configuración

---

## TL;DR — qué arreglar ya

1. **Quemar y rotar las credenciales de Volvo Connect** (`018B1E992E` / `yeBgBh3of3`). Están hardcodeadas en `volvo_api_service.dart:40-41` como fallback y se compilan dentro del APK.
2. **Crear `firestore.rules`**. No existe. La base de datos depende del modo "test" de Firebase, lo que en la práctica deja toda la colección `EMPLEADOS` (DNI + hashes de contraseña + roles) abierta a lectura/escritura.
3. **Agregar `if (!mounted) return;`** antes de cada `Navigator.pop()` y `setState()` post-`await` (varios formularios admin).
4. **Limpiar dependencias muertas**: `http`, `flutter_pdfview`, `csv`, y mover `win32`/`ffi` a plataforma condicional. Reduce el bundle y elimina warnings en Android/iOS.

El resto del informe entra en detalle.

---

## 1. Seguridad

### CRÍTICO — Credenciales Volvo Connect quemadas en el código

**Archivo:** `lib/features/vehicles/services/volvo_api_service.dart:40-46`

```dart
static const String _fallbackUsername = '018B1E992E';
static const String _fallbackPassword = 'yeBgBh3of3';

String get _username =>
    _envUsername.isNotEmpty ? _envUsername : _fallbackUsername;
```

Aunque el código intenta leerlas con `--dart-define-from-file=secrets.json`, el fallback se compila como `const` y queda dentro del binario distribuido. Con `apktool` o `strings` sobre el APK release, cualquiera obtiene las credenciales — y el header `Basic <base64>` se arma con ellas en cada request.

**Acción:**

- Rotar las credenciales en el portal Volvo Connect hoy mismo.
- Eliminar las constantes `_fallbackUsername` / `_fallbackPassword` y hacer que el getter lance `StateError` si no hay env var.
- Mover el flujo a una Cloud Function que actúe como proxy: la app pide datos, la función agrega Basic Auth y devuelve la respuesta. Las credenciales nunca tocan el cliente.

### CRÍTICO — No hay reglas de Firestore

`firestore.rules` no existe en el repo. Si la consola sigue en modo "test", cualquiera con el `projectId` (`logisticaapp-e539a`, visible en `firebase.json` y en `firebase_options.dart`) puede leer y escribir toda la base. Ese `projectId` está en el binario, así que se considera público.

**Acción:** publicar reglas mínimas similares a:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    function isSignedIn() { return request.auth != null; }
    function role() { return get(/databases/$(db)/documents/EMPLEADOS/$(request.auth.uid)).data.ROL; }
    function isAdmin() { return role() == 'ADMIN'; }

    match /EMPLEADOS/{dni} {
      allow read: if isSignedIn() && (request.auth.uid == dni || isAdmin());
      allow write: if isAdmin();
    }
    match /VEHICULOS/{doc=**}    { allow read: if isSignedIn(); allow write: if isAdmin(); }
    match /REVISIONES/{doc=**}   { allow read: if isSignedIn(); allow write: if isAdmin(); }
    match /VENCIMIENTOS/{doc=**} { allow read: if isSignedIn(); allow write: if isAdmin(); }
  }
}
```

Hoy el login es por DNI/contraseña contra Firestore (sin Firebase Auth), así que `request.auth.uid` no está disponible. Antes de aplicar reglas reales hay que pasar a **Firebase Authentication** (custom tokens generados desde una Cloud Function que valida DNI+password). Sin ese paso, las reglas tendrían que ser puramente `if false` para escritura, dejando la app inoperable.

### ALTO — Sesión persistida en SharedPreferences sin cifrar

`lib/core/services/prefs_service.dart` guarda `dni`, `nombre` y `rol` en `SharedPreferences` (XML plano en Android, accesible con root o respaldos ADB). Como además no hay tokens con expiración, una desactivación de usuario en Firestore no expulsa al usuario activo hasta que reinicie sesión.

**Acción:** migrar a `flutter_secure_storage` y agregar `session_expires_at`. Validar contra Firestore al menos al iniciar la app.

### ALTO — DNI logueado en la migración silenciosa de hash

`lib/features/auth/services/auth_service.dart:159`

```dart
debugPrint('🔐 Hash migrado a Bcrypt para DNI: $dni');
```

`debugPrint` solo emite en debug, pero el patrón se repite (`auth_service.dart:130`, `volvo_api_service.dart` con `response.data`, etc.). Cualquier dato personal en logcat es problema regulatorio.

**Acción:** loguear con `dni.hashCode` o solo "usuario migrado correctamente". Considerar Firebase Crashlytics en lugar de `debugPrint` para errores reales (hay 41 ocurrencias en `lib/`).

### ALTO — Login sin rate limiting

`AuthService.login` no contabiliza intentos fallidos. Un script puede iterar DNIs (8 dígitos = 100M, factible con `EMPLEADOS` ya conocidos) hasta dar con el password — y con SHA-256 legacy todavía vivo, los ataques offline son baratos si alguien filtra la colección.

**Acción:** llevar contador `failed_attempts` + `locked_until` en Firestore y bloquear N minutos tras 5 intentos. Idealmente desde una Cloud Function para evitar que el cliente bypasee.

### MEDIO — Migración SHA-256 → Bcrypt sin reintento

La migración silenciosa (`_migrarHashSilencioso`) corre fire-and-forget. Si la red corta, el usuario queda con SHA-256 indefinidamente. No hay flag `pending_migration` ni job batch que la complete.

**Acción:** marcar `needs_bcrypt_migration: true` cuando falle, y correr una Cloud Function semanal que migre los pendientes. Documentar fecha objetivo para apagar el branch SHA-256 de `PasswordHasher.verify`.

### MEDIO — Inconsistencia de campo de estado

`auth_service.dart:94-96` lee `data['ACTIVO']` (bool), pero al crear empleado en `admin_personal_form_screen.dart` se escribe `estado_cuenta: 'ACTIVO'` (string). Hoy quien haga "desactivar" desde la pantalla admin quizá no esté tocando el campo que lee el login.

**Acción:** estandarizar a un único campo (`estado_cuenta` string) y migrar los documentos viejos.

### MEDIO — Sanitización de DNI insuficiente

`replaceAll(RegExp(r'[^0-9]'), '')` deja pasar cualquier longitud. Si bien el `TextField` tiene `maxLength: 8`, eso es UI; el servicio no valida. Conviene rechazar DNIs que no tengan 7-8 dígitos antes de consultar Firestore (ahorra lecturas y reduce enumeration).

### NOTA POSITIVA

- `secrets.json` **nunca fue committeado** (`git log --all --full-history -- secrets.json` no devuelve nada). El `.gitignore` está bien armado para `*.jks`, `*.p12`, `*.key`, `serviceAccountKey.json`, `secrets.json`.
- `PasswordHasher` está bien diseñado: detecta el formato, soporta bcrypt `$2a$/$2b$/$2y$`, hace hash con `logRounds: 10`.

---

## 2. Arquitectura

### Lo que está bien

- **Capas claras** en el feature `vehicles`: `VolvoApiService` → `VehiculoRepository` → `VehiculoManager` → `VehiculoProvider`. La inyección con `ProxyProvider2` y `ChangeNotifierProxyProvider2` en `main.dart:62-90` está hecha correctamente.
- **Modelos tolerantes** (`vehiculo.dart`, `empleado.dart`) con helpers `_parseDate`, `_parseAnio` y `copyWith`. Sobreviven a cambios de schema en Firestore.
- **Provider granular**: `VehiculoProvider` indexa loading/success/error por patente, evitando rebuilds globales.
- **Constantes centralizadas** en `app_constants.dart` (rutas, colecciones, roles) — esto ya elimina la mayoría de magic strings de navegación.
- **Sin importaciones circulares entre features** (verificado con grep cruzado).
- **Guards composables**: `AuthGuard` envuelve a `RoleGuard` en el router.

### Oportunidades

#### `AutoSyncService` acoplado a los providers

`auto_sync_service.dart` recibe directamente `VehiculoProvider` y `SyncDashboardProvider`. Si cambia la firma de `provider.sync(patente, vin)`, rompe el autosync. Conviene definir una interfaz mínima (`SyncTarget`) y registrar el servicio como Provider singleton.

#### `NotificationService.selectNotificationStream` nunca se cierra

```dart
static final StreamController<String?> selectNotificationStream =
    StreamController<String?>.broadcast();
```

`dispose()` se llama en `_LogisticaAppState.dispose()` pero no incluye `selectNotificationStream.close()`. En hot-reload o tests se acumulan controllers — agregar `await selectNotificationStream.close()` en el método.

#### Pantallas demasiado grandes

| Archivo | Líneas |
|---|---|
| `features/employees/screens/admin_personal_lista_screen.dart` | **1006** |
| `features/expirations/screens/user_mis_vencimientos_screen.dart` | 778 |
| `features/vehicles/screens/admin_vehiculo_form_screen.dart` | 725 |
| `features/vehicles/screens/admin_vehiculos_lista_screen.dart` | 645 |

Mezclan widget, estado, queries Firestore y diálogos. Extraer `EmpleadoCard`, `DetalleChofer`, `ListaPorTipo` y un `VehicleFormProvider` para los formularios — el formulario es candidato natural a Provider local.

#### Widgets duplicados en `expirations/`

`vencimiento_item.dart`, `vencimiento_item_card.dart` y `vencimiento_editor_sheet.dart` cubren responsabilidades superpuestas. Consolidar a un único `VencimientoItem` (presentación) + `VencimientoEditorSheet` (interacción).

#### Servicios `static` no se pueden mockear

`PrefsService`, `NotificationService` y `AutoSyncService` son singletons con métodos estáticos. Para tests unitarios conviene exponerlos como Provider/factory.

---

## 3. Calidad de código y bugs

### CRÍTICO — `Navigator.pop()` y `setState()` post-`await` sin chequear `mounted`

Patrón confirmado en:

- `lib/features/employees/screens/admin_personal_form_screen.dart:101`
- `lib/features/employees/screens/admin_personal_lista_screen.dart:742`
- `lib/features/checklist/screens/user_checklist_form_screen.dart:165, 179`
- `lib/features/vehicles/screens/admin_vehiculo_form_screen.dart:314-360`

Si el usuario sale de la pantalla durante el `await`, se gatilla "setState() called after dispose()" o "Looking up a deactivated widget's ancestor". En producción se ve como crashes intermitentes inexplicables.

**Patrón de fix**:

```dart
Future<void> _guardar() async {
  setState(() => _isSaving = true);
  try {
    await repo.guardar(...);
    if (!mounted) return;
    Navigator.of(context).pop();
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(...);
  } finally {
    if (mounted) setState(() => _isSaving = false);
  }
}
```

### ALTO — `as Map<String, dynamic>` sin validar

14 archivos asumen el shape del documento. Ej: `lib/features/vehicles/screens/user_mi_equipo_screen.dart:55,121,194,518` y `lib/shared/widgets/guards/role_guard.dart:51`. Un documento Firestore corrupto (campo nullado, tipo cambiado) tira `TypeError` en lugar de mostrar un error amigable.

```dart
final raw = snapshot.data?.data();
if (raw is! Map<String, dynamic>) return _ErrorTile();
final data = raw;
```

### ALTO — Listeners de Stream no se cancelan antes de re-asignar

`lib/features/admin_dashboard/screens/admin_panel_screen.dart:49-81` reasigna `_revisionesSubscription` sin cancelar la anterior. En reentradas (cambio de rol o re-login) el listener queda colgado leyendo Firestore.

```dart
await _revisionesSubscription?.cancel();
_revisionesSubscription = stream.listen(...);
```

### MEDIO — `try/catch` que solo loguean

`admin_panel_screen.dart:72`, `revision_service.dart:154`, `main_panel.dart:138`. En operaciones críticas (borrar archivo de Storage, limpiar estado al logout) un `debugPrint` + seguir adelante deja la BD inconsistente sin que nadie se entere. Recomendado: re-lanzar o reportar a Crashlytics.

### MEDIO — Falta `finally` en uploads

`admin_vehiculo_form_screen.dart:115-155` `_subirDocumento`: si falla la subida, `_isSaving` queda en `true`. Mover el reset al `finally`.

### Buenas prácticas detectadas

- TextEditingControllers se disponen correctamente (login, formularios admin).
- `mounted` se chequea bien en `login_screen.dart:58`.
- `revision_service.dart:73` hace `rethrow` en lugar de tragar errores.
- `main_panel.dart:133-135` limpia el `Provider` al hacer logout.

---

## 4. Dependencias y configuración

### CRÍTICO — `win32` y `ffi` declarados como deps generales

```yaml
ffi: ^2.1.2
win32: ^5.5.4
```

Son librerías nativas de Windows. La app además compila para Android, iOS y Web (según `firebase_options.dart`). Aunque Dart suele tolerar el import condicional, conviene declarar la restricción explícita:

```yaml
ffi:
  ^2.1.2
  # platforms: { windows: ... }
```

(El soporte oficial para `platforms:` en deps es limitado; la alternativa es factorizar el código Windows en un paquete propio en `packages/win_utils/` y solo importarlo en el target Windows.)

### IMPORTANTE — Paquetes declarados pero no usados

| Paquete | Estado | Acción |
|---|---|---|
| `http: ^1.2.0` | Sin un solo `import 'package:http/...'` | Eliminar (usás `dio`) |
| `flutter_pdfview: ^1.3.2` | Sin imports (usás `pdfrx`) | Eliminar |
| `csv: ^6.0.0` | Sin imports (los reportes son `excel`) | Eliminar si no hay export CSV planeado |

Beneficio: ~300 KB menos en el bundle y menos superficie de mantenimiento.

### MENOR — Assets sub-declarados

Solo está declarado `assets/images/fondo_login.jpg`. Si el proyecto crece, conviene declarar la carpeta entera: `- assets/images/`.

### MENOR — `firebase.json` solo cubre Android

`firebase_options.dart` ya tiene Android, iOS, Web y Windows configurados, así que la app funciona, pero `firebase.json` declara solo Android. Agregar las otras plataformas para que `flutterfire configure` las regenere consistentemente.

### MENOR — `analysis_options.yaml` muy permisivo

Hoy solo incluye `package:flutter_lints/flutter.yaml`. Sumar:

```yaml
linter:
  rules:
    avoid_print: true
    prefer_const_constructors: true
    prefer_const_literals_to_create_immutables: true
    use_build_context_synchronously: true   # detectaría los bugs de mounted
    require_trailing_commas: true
```

`use_build_context_synchronously` te marcaría automáticamente los problemas de la sección 3.

### MENOR — `package.json` y `*.iml` en el repo

`package.json` legítimo (instala `firebase-tools` para deploy), pero `node_modules/` (si llega a aparecer) y `logistica_app_profesional.iml` deberían sumarse al `.gitignore` (ya hay `*.iml` en la lista, conviene chequear que el archivo del root no esté trackeado: `git ls-files | grep iml`).

---

## 5. Plan de remediación sugerido

### Esta semana
1. Rotar credenciales Volvo y eliminar fallback hardcodeado.
2. Publicar `firestore.rules` (junto con la migración a Firebase Auth si todavía no se hizo).
3. Corregir los `Navigator.pop()` y `setState()` post-`await` en los 4 formularios listados.
4. Limpiar `http`, `flutter_pdfview`, `csv` del `pubspec.yaml`.

### Próximas 2-4 semanas
5. Migrar autenticación a Firebase Auth con custom tokens (Cloud Function valida DNI+password, devuelve token).
6. Mover credenciales sensibles al servidor (Cloud Functions como proxy a Volvo).
7. Implementar rate limiting en login (Cloud Function + colección `LOGIN_ATTEMPTS`).
8. Reemplazar `SharedPreferences` por `flutter_secure_storage` para sesión.
9. Cancelar subscriptions antes de reasignar y cerrar `selectNotificationStream`.
10. Activar `use_build_context_synchronously` en `analysis_options.yaml`.

### Backlog
11. Refactor de `admin_personal_lista_screen.dart` (1006 líneas) y `admin_vehiculo_form_screen.dart` (725 líneas).
12. Consolidar widgets duplicados de `expirations/`.
13. Cloud Function batch para terminar la migración SHA-256 → Bcrypt y eliminar el branch legacy.
14. Integrar Firebase Crashlytics y dejar de depender de `debugPrint` para errores reales.

---

## Resumen por severidad

| Severidad | Cantidad | Tema |
|---|---|---|
| Crítico | 4 | Credenciales Volvo, ausencia de rules, `mounted` post-`await`, `win32` cross-platform |
| Alto | 5 | SharedPreferences, rate limiting, DNI en logs, casts inseguros, listeners no cancelados |
| Medio | 6 | Migración hash, validación DNI, campo estado, tries silenciosos, finally faltantes, redundancia HTTP/PDF |
| Menor | 5 | Assets, firebase.json, lints, `csv` no usado, `*.iml` |

---

*Generado el 2026-04-28 como parte de la revisión técnica solicitada.*
