# Migración a Firebase Auth — guía de deploy y testing

Branch: `feature/firebase-auth`. Antes de mergear a `main` hay que desplegar la function, probar el login y luego desplegar las rules.

---

## 1. Pre-requisitos en Firebase Console

Verificá (deberían estar listos):

1. **Plan Blaze** activado (sí — confirmado).
2. **Authentication** habilitado: Build → Authentication → Get started.
3. **Sign-in method → Custom auth system**: aparece como opción interna, no requiere setup explícito (custom tokens son el método).

## 2. Deploy de la Cloud Function

Una sola vez por máquina, instalá `firebase-tools` si no está:

```bash
npm install -g firebase-tools
firebase login   # te abre el browser para autenticar
```

Después en la raíz del proyecto:

```bash
cd functions
npm install      # baja firebase-admin, firebase-functions, bcryptjs, ts
cd ..
firebase deploy --only functions:loginConDni
```

Esto compila el TypeScript, hace lint y sube la function. Va a tardar ~1-2 minutos la primera vez (Firebase tiene que crear el bucket de Cloud Functions, asignar IAM, etc).

Cuando termina te muestra la URL del callable. **No la necesitás copiar** — el cliente Flutter llama por nombre con `httpsCallable('loginConDni')`.

## 3. Probar la function antes de desplegar las rules

Crítico para no romper la app en producción.

### 3.a Test desde la consola de Firebase (rápido)

1. Firebase Console → Functions → `loginConDni` → Logs.
2. Abrí un terminal nuevo y corré la app contra production:
   ```powershell
   flutter run -d windows --dart-define-from-file=secrets.json
   ```
3. Probá login con un chofer real. Mirá los logs de la function:
   - Debería decir `[login] OK { dniHash: '...', rol: 'USUARIO' }`.
   - Si dice `[login] DNI no existe` o `[login] password incorrecto`, ajustá la cuenta de prueba.
4. Si entra correctamente, abrí Authentication → Users en la consola: deberías ver un usuario nuevo con UID = el DNI.

### 3.b Test del fallback SHA-256

Si querés verificar que la migración silenciosa funciona, buscá en `EMPLEADOS` algún chofer que tenga `CONTRASEÑA` con 64 chars hex (SHA-256 viejo). Logueá con su contraseña real. Mirá:
- En logs: `[login] hash migrado a bcrypt`.
- En Firestore: `EMPLEADOS/{dni}` ahora tiene `CONTRASEÑA` empezando con `$2a$` o `$2b$`, y el campo `hash_migrado_a_bcrypt` con el timestamp.

## 4. Deploy de las rules (firestore + storage)

**Una vez que la function funcione y al menos un user logue OK:**

```bash
firebase deploy --only firestore:rules,storage
```

Esto reemplaza las rules abiertas por las nuevas con `isAdmin()` y `request.auth.uid`.

⚠️ **Si hay choferes con la app abierta cuando hacés esto**, sus sesiones probablemente se rompen porque su `currentUser` puede ser null. Recomendado: hacer el deploy fuera del horario operativo (madrugada o domingo) y avisar a los admins por WhatsApp que pueden tener que cerrar sesión y volver a entrar una vez.

## 5. Verificación post-deploy

En la app:

1. **Login como admin**: tiene que entrar y poder ver todas las pantallas.
2. **Login como chofer**: tiene que entrar y solo ver lo suyo.
3. **Crear chofer nuevo**: el admin va a "Gestión de Personal → Nuevo chofer", lo crea, después intenta loguear con esa cuenta.
4. **Auditoría de vencimientos**: el admin entra, ve los vencimientos, abre uno y manda WhatsApp. La escritura a `AVISOS_VENCIMIENTOS` tiene que funcionar.
5. **Sync Volvo**: el AutoSync tiene que poder seguir escribiendo a `VEHICULOS` y `TELEMETRIA_HISTORICO` (porque el admin está logueado como ADMIN).

Si algo falla con error tipo `permission-denied`:
- Mirar los logs de Firestore en Firebase Console → Firestore Database → Usage.
- Cruzar con las rules para ver qué `match` no se cumple.
- Si la regla esperaba `isAdmin()` pero el user logueado tiene rol distinto, el problema está en su custom claim — re-loguear soluciona.

## 6. Mergear a main

Cuando todo está OK:

```bash
git add .
git commit -m "feat(auth): migrar a Firebase Auth con custom token + cerrar rules"
git push -u origin feature/firebase-auth

# En GitHub: abrir PR feature/firebase-auth → main, mergear.

# Localmente:
git checkout main
git pull
git branch -d feature/firebase-auth
```

## 7. Rollback si algo sale muy mal

**Plan B si la app deja de funcionar después del deploy:**

```bash
# Volver al commit anterior del repo
git checkout main
git revert <hash del merge>
git push

# Restaurar las rules abiertas (las que estaban antes de esta branch)
git checkout HEAD~1 -- firestore.rules storage.rules
firebase deploy --only firestore:rules,storage
```

La function `loginConDni` puede quedar deployada — no rompe nada porque el `AuthService` viejo no la llama.

## 8. Costos esperados

- **Firebase Auth**: $0 hasta 50.000 MAU (estás en ~60). Margen de 800x.
- **Cloud Functions invocaciones**: ~1.800/mes para 60 users con 30 logins/mes. Free tier es 2.000.000.
- **Cloud Functions GB-segundos**: la function tarda ~300ms y usa ~256MB. ~12.000 GB-s/mes. Free tier es 400.000.

**Costo proyectado: USD 0/mes.**

Configurá un budget alert en Firebase Console → Usage and billing → Set budget → USD 5/mes para detectar cualquier desvío.

---

*Última actualización: 2026-04-29.*
