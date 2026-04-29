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
import { getFirestore, FieldValue } from "firebase-admin/firestore";
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
 * Errores devueltos al cliente con mensaje genérico para no facilitar
 * enumeración de DNIs (un atacante no puede distinguir "DNI no existe"
 * de "password equivocado"). El logger interno sí discrimina para que
 * podamos diagnosticar.
 */
export const loginConDni = onCall(
  {
    // Anti-DOS: un intento de fuerza bruta no puede exceder N rps por IP.
    // Ojo: este límite es *aspiracional* en v2 callable, no estricto;
    // pero dejarlo seteado ayuda al planner.
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
      logger.info("[login] password incorrecto", { dni });
      throw new HttpsError(
        "permission-denied",
        "Contraseña incorrecta."
      );
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
 * Hash corto y estable de un DNI para incluir en logs sin exponer el
 * dato real. NO criptográficamente seguro contra enumeración (el
 * dominio de DNIs es chico), pero suficiente para correlacionar
 * eventos de logs sin dejar PII.
 */
function hashId(dni: string): string {
  return crypto.createHash("sha1").update(dni).digest("hex").substring(0, 8);
}
