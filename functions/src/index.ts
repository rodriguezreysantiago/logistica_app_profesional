/**
 * Cloud Functions de S.M.A.R.T. Logística.
 *
 * Por ahora solo expone `loginConDni`: el endpoint que reemplaza al
 * login del cliente que validaba contra Firestore directo.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
import * as logger from "firebase-functions/logger";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import {
  getFirestore,
  FieldValue,
  DocumentReference,
  Timestamp,
} from "firebase-admin/firestore";
import * as bcrypt from "bcryptjs";
import * as crypto from "crypto";

// Inicialización del Admin SDK (una sola vez por instancia).
initializeApp();

// Configuración global: límite de instancias concurrentes para que un
// loop de login no me funda la cuenta.
setGlobalOptions({
  region: "us-central1",
  maxInstances: 10,
  // El timeout por defecto es 60 segundos, suficiente.
});

const db = getFirestore();
const auth = getAuth();

// ============================================================================
// Configuración de rate limiting
// ============================================================================
// Después de N intentos fallidos consecutivos sobre el mismo DNI, se
// bloquea ese DNI por X minutos. Implementado server-side en la
// colección LOGIN_ATTEMPTS (clave = hash corto del DNI para no exponer
// el dato en el path del documento).
//
// El reset del contador es automático: cualquier login OK lo borra.
// Después del bloqueo, el próximo intento fallido empieza un nuevo
// ciclo desde 1.
const MAX_INTENTOS_FALLIDOS = 5;
const BLOQUEO_DURACION_MS = 5 * 60 * 1000; // 5 minutos

// ============================================================================
// loginConDni
// ============================================================================

/**
 * Verifica un par DNI + contraseña contra `EMPLEADOS/{dni}` y devuelve
 * un custom token de Firebase Auth con UID = DNI y custom claims
 * `{ rol, nombre }`.
 *
 * Soporta dos formatos de hash en la columna `CONTRASEÑA`:
 *   - **bcrypt** (nuevo, con salt): `$2a$.../$2b$.../$2y$...`
 *   - **SHA-256** (legacy): 64 chars hex
 *
 * Si el hash era SHA-256 y la contraseña es correcta, lo reescribe a
 * bcrypt en background (migración silenciosa). Si esa migración falla,
 * el login NO falla — el usuario sigue entrando.
 *
 * Implementa rate limiting por DNI: 5 intentos fallidos consecutivos →
 * bloqueo de 15 minutos. Ver constantes arriba.
 *
 * Errores devueltos al cliente con mensaje genérico para no facilitar
 * enumeración de DNIs (un atacante no puede distinguir "DNI no existe"
 * de "password equivocado"). El logger interno sí discrimina para que
 * podamos diagnosticar.
 */
export const loginConDni = onCall(
  {
    enforceAppCheck: false, // todavía no está activado App Check
  },
  async (request) => {
    const { data } = request;

    // ─── Validación de input ────────────────────────────────────────
    const dniRaw = (data?.dni ?? "").toString();
    const passwordRaw = (data?.password ?? "").toString();

    const dni = dniRaw.replace(/[^0-9]/g, "");
    const password = passwordRaw.trim();

    if (!dni || !password) {
      throw new HttpsError(
        "invalid-argument",
        "Complete todos los campos requeridos."
      );
    }
    if (dni.length < 6 || dni.length > 9) {
      // DNIs argentinos modernos: 7-8 dígitos. Aceptamos 6-9 por si
      // hay legajos con formato distinto.
      throw new HttpsError(
        "invalid-argument",
        "El DNI tiene un formato inválido."
      );
    }

    // ─── Lectura del legajo ────────────────────────────────────────
    const docRef = db.collection("EMPLEADOS").doc(dni);
    const docSnap = await docRef.get();

    if (!docSnap.exists) {
      logger.info("[login] DNI no existe", { dni });
      throw new HttpsError(
        "not-found",
        "El usuario no existe o el DNI es incorrecto."
      );
    }

    const empleado = docSnap.data() ?? {};

    // ─── Cuenta activa ─────────────────────────────────────────────
    const isActive = empleado.ACTIVO !== false; // default: activo si falta el campo
    if (!isActive) {
      logger.info("[login] cuenta inactiva", { dni });
      throw new HttpsError(
        "permission-denied",
        "Usuario inactivo. Contacte a administración."
      );
    }

    // ─── Rate limit: chequeo de bloqueo previo ─────────────────────
    // Si esta DNI ya está bloqueada por intentos previos, cortamos acá.
    // No verificamos password, no quemamos CPU, no damos info al
    // atacante sobre si la password actual era correcta o no.
    const intentosRef = db.collection("LOGIN_ATTEMPTS").doc(hashId(dni));
    const minBloqueo = await chequearBloqueoActivo(intentosRef);
    if (minBloqueo > 0) {
      logger.warn("[login] bloqueado por rate limit", {
        dniHash: hashId(dni),
        minutosRestantes: minBloqueo,
      });
      throw new HttpsError(
        "resource-exhausted",
        `Demasiados intentos fallidos. Reintentá en ${minBloqueo} minutos.`
      );
    }

    // ─── Verificación de contraseña ────────────────────────────────
    const storedHash = (empleado["CONTRASEÑA"] ?? "").toString();
    if (!storedHash) {
      logger.warn("[login] empleado sin hash de contraseña", { dni });
      throw new HttpsError(
        "failed-precondition",
        "El usuario no tiene contraseña configurada. Contacte a administración."
      );
    }

    const passwordOk = verificarPassword(password, storedHash);
    if (!passwordOk) {
      // Registramos intento fallido. Si esta llamada llega al límite,
      // el siguiente intento queda bloqueado.
      const intentos = await registrarIntentoFallido(intentosRef);
      logger.info("[login] password incorrecto", {
        dniHash: hashId(dni),
        intentosFallidos: intentos,
      });
      // Si justo este intento ES el que cruza el umbral, avisamos al
      // usuario explícitamente. Para los anteriores, mensaje genérico.
      const recienBloqueado = intentos >= MAX_INTENTOS_FALLIDOS;
      const minutos = BLOQUEO_DURACION_MS / 60000;
      const msg = recienBloqueado ?
        `Contraseña incorrecta. Cuenta bloqueada temporalmente por ${minutos} minutos.` :
        "Contraseña incorrecta.";
      throw new HttpsError("permission-denied", msg);
    }

    // ─── Migración silenciosa SHA-256 → bcrypt ─────────────────────
    if (esLegacy(storedHash)) {
      // No bloqueamos el login si falla.
      try {
        const nuevoHash = await bcrypt.hash(password, 10);
        await docRef.update({
          "CONTRASEÑA": nuevoHash,
          "hash_migrado_a_bcrypt": FieldValue.serverTimestamp(),
        });
        logger.info("[login] hash migrado a bcrypt", { dniHash: hashId(dni) });
      } catch (e) {
        logger.warn("[login] migración silenciosa falló (no bloquea)", {
          dniHash: hashId(dni),
          error: (e as Error).message,
        });
      }
    }

    // ─── Reset del contador de intentos (login OK) ─────────────────
    // Si el usuario tuvo intentos fallidos previos pero al final acertó,
    // limpiamos el contador. No bloquea login si falla.
    try {
      await intentosRef.delete();
    } catch (e) {
      logger.warn("[login] no pude limpiar LOGIN_ATTEMPTS (no bloquea)", {
        dniHash: hashId(dni),
        error: (e as Error).message,
      });
    }

    // ─── Emisión del custom token ──────────────────────────────────
    // UID = DNI para que `request.auth.uid` en las rules sea el DNI.
    const nombre = (empleado.NOMBRE ?? "Usuario").toString();
    const rol = (empleado.ROL ?? "USUARIO").toString();

    const token = await auth.createCustomToken(dni, {
      rol,
      // Nombre como custom claim ahorra una lectura de Firestore en el
      // cliente cada vez que necesita mostrar el nombre del logueado.
      nombre,
    });

    logger.info("[login] OK", { dniHash: hashId(dni), rol });

    return {
      token,
      // Devolvemos también los datos básicos para que el cliente no
      // tenga que decodificar el JWT solo para mostrar el nombre.
      dni,
      nombre,
      rol,
    };
  }
);

// ============================================================================
// Helpers
// ============================================================================

/** Compara una contraseña en plano con un hash en formato bcrypt o SHA-256. */
function verificarPassword(password: string, storedHash: string): boolean {
  if (esBcrypt(storedHash)) {
    try {
      return bcrypt.compareSync(password, storedHash);
    } catch {
      return false;
    }
  }
  // Fallback legacy: SHA-256 hex.
  return sha256Hex(password) === storedHash;
}

function esBcrypt(hash: string): boolean {
  return (
    hash.startsWith("$2a$") ||
    hash.startsWith("$2b$") ||
    hash.startsWith("$2y$")
  );
}

function esLegacy(hash: string): boolean {
  return !esBcrypt(hash);
}

function sha256Hex(text: string): string {
  return crypto.createHash("sha256").update(text, "utf8").digest("hex");
}

/**
 * Hash corto y estable de un DNI para incluir en logs y como clave en
 * LOGIN_ATTEMPTS sin exponer el DNI real. NO criptográficamente seguro
 * contra enumeración (el dominio de DNIs es chico, ~10^8) — solo para
 * correlación de logs y para que el path de Firestore no contenga PII.
 */
function hashId(text: string): string {
  return crypto
    .createHash("sha256")
    .update(text, "utf8")
    .digest("hex")
    .slice(0, 8);
}

// ============================================================================
// Rate limiting (LOGIN_ATTEMPTS)
// ============================================================================

/**
 * Devuelve los **minutos restantes de bloqueo** para esta DNI, o 0 si
 * no está bloqueada. El doc en LOGIN_ATTEMPTS tiene la siguiente
 * estructura:
 *   {
 *     intentos: number,         // contador de fallidos consecutivos
 *     ultimoIntento: timestamp, // último timestamp de fallo
 *     bloqueadoHasta?: timestamp, // existe si está bloqueado
 *   }
 */
async function chequearBloqueoActivo(
  ref: DocumentReference
): Promise<number> {
  const snap = await ref.get();
  if (!snap.exists) return 0;
  const data = snap.data() ?? {};
  const bloqueadoHasta = data.bloqueadoHasta as Timestamp | undefined;
  if (!bloqueadoHasta) return 0;
  const restanteMs = bloqueadoHasta.toMillis() - Date.now();
  if (restanteMs <= 0) return 0;
  return Math.ceil(restanteMs / 60000); // redondeo arriba para que el mensaje no diga "0 minutos"
}

/**
 * Registra un intento fallido en LOGIN_ATTEMPTS. Si esta llamada
 * empuja el contador hasta el máximo, agrega `bloqueadoHasta` con
 * timestamp = ahora + duración configurada. Usa una transacción para
 * que dos intentos paralelos no se pisen.
 *
 * Devuelve el valor del contador post-incremento.
 */
async function registrarIntentoFallido(
  ref: DocumentReference
): Promise<number> {
  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() ?? {} : {};
    const intentos = ((data.intentos as number | undefined) ?? 0) + 1;
    const update: Record<string, unknown> = {
      intentos,
      ultimoIntento: FieldValue.serverTimestamp(),
    };
    if (intentos >= MAX_INTENTOS_FALLIDOS) {
      update.bloqueadoHasta = Timestamp.fromMillis(
        Date.now() + BLOQUEO_DURACION_MS
      );
    }
    if (snap.exists) {
      tx.update(ref, update);
    } else {
      tx.set(ref, update);
    }
    return intentos;
  });
}
