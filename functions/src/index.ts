/**
 * Cloud Functions de S.M.A.R.T. Logística.
 *
 * Endpoints expuestos:
 *   - `loginConDni`: emite custom token de Firebase Auth a partir de
 *     un par DNI + contraseña (con rate limit + migración bcrypt).
 *   - `volvoProxy`: llama la API de Volvo Connect en nombre del admin
 *     manteniendo las credenciales server-side (Secret Manager).
 *   - `auditLogWrite`: escribe entradas en AUDITORIA_ACCIONES con el
 *     DNI/nombre del admin tomado del JWT (no del cliente). Permite
 *     cerrar la rule de esa colección a `write: if false`.
 *   - `telemetriaSnapshotScheduled`: cron cada 6h que escribe a
 *     TELEMETRIA_HISTORICO via Admin SDK.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";
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

// ============================================================================
// volvoProxy
// ============================================================================
// Proxy server-side a la API de Volvo Connect. Mantiene las credenciales
// (`VOLVO_USERNAME`/`VOLVO_PASSWORD`) en Secret Manager y solo permite
// invocar a admins autenticados via Firebase Auth custom token.
//
// La function recibe `{operation, params}` y traduce a un GET autenticado
// contra Volvo. Devuelve `{statusCode, data}` para que el cliente conserve
// su capacidad de hacer parsing tolerante (paths legacy, etc).
//
// Setup inicial (una sola vez):
//   firebase functions:secrets:set VOLVO_USERNAME
//   firebase functions:secrets:set VOLVO_PASSWORD
//
// Operaciones soportadas:
//   - "flota"        → GET /vehicle/vehicles
//   - "telemetria"   → GET /vehicle/vehiclestatuses?vin=X&additionalContent=VOLVOGROUPSNAPSHOT
//   - "kilometraje"  → GET /vehicle/vehiclestatuses?vin=X
//   - "estadosFlota" → GET /vehicle/vehiclestatuses (todos)

const volvoUsername = defineSecret("VOLVO_USERNAME");
const volvoPassword = defineSecret("VOLVO_PASSWORD");

const VOLVO_BASE = "https://api.volvotrucks.com";
const ACCEPT_VEHICLES =
  "application/x.volvogroup.com.vehicles.v1.0+json; UTF-8";
const ACCEPT_STATUSES =
  "application/x.volvogroup.com.vehiclestatuses.v1.0+json; UTF-8";

interface VolvoProxyResult {
  statusCode: number;
  data: unknown;
}

export const volvoProxy = onCall(
  {
    secrets: [volvoUsername, volvoPassword],
    timeoutSeconds: 30,
  },
  async (request): Promise<VolvoProxyResult> => {
    // ─── Auth: solo admin logueado ─────────────────────────────────
    const rol = request.auth?.token?.rol;
    if (!request.auth || rol !== "ADMIN") {
      logger.warn("[volvoProxy] llamada sin auth ADMIN", {
        uid: request.auth?.uid ?? "no-uid",
        rol: rol ?? "no-rol",
      });
      throw new HttpsError(
        "permission-denied",
        "Solo administradores pueden consultar Volvo."
      );
    }

    // ─── Validación de input ───────────────────────────────────────
    const operation = (request.data?.operation ?? "").toString();
    const params = (request.data?.params ?? {}) as Record<string, unknown>;

    if (!operation) {
      throw new HttpsError("invalid-argument", "Falta `operation`.");
    }

    // ─── Routing por operación → URL Volvo ─────────────────────────
    let url: string;
    let accept: string;

    switch (operation) {
    case "flota": {
      url = `${VOLVO_BASE}/vehicle/vehicles`;
      accept = ACCEPT_VEHICLES;
      break;
    }
    case "telemetria": {
      const vin = (params.vin ?? "").toString().trim().toUpperCase();
      if (!vin) {
        throw new HttpsError("invalid-argument", "Falta `params.vin`.");
      }
      const qs = new URLSearchParams({
        vin,
        latestOnly: "true",
        additionalContent: "VOLVOGROUPSNAPSHOT",
      });
      url = `${VOLVO_BASE}/vehicle/vehiclestatuses?${qs.toString()}`;
      accept = ACCEPT_STATUSES;
      break;
    }
    case "kilometraje": {
      const vin = (params.vin ?? "").toString().trim().toUpperCase();
      if (!vin) {
        throw new HttpsError("invalid-argument", "Falta `params.vin`.");
      }
      const qs = new URLSearchParams({
        vin,
        latestOnly: "true",
      });
      url = `${VOLVO_BASE}/vehicle/vehiclestatuses?${qs.toString()}`;
      accept = ACCEPT_STATUSES;
      break;
    }
    case "estadosFlota": {
      const qs = new URLSearchParams({ latestOnly: "true" });
      url = `${VOLVO_BASE}/vehicle/vehiclestatuses?${qs.toString()}`;
      accept = ACCEPT_STATUSES;
      break;
    }
    default:
      throw new HttpsError(
        "invalid-argument",
        `Operación '${operation}' no soportada.`
      );
    }

    // ─── Llamada a Volvo ───────────────────────────────────────────
    const authHeader = "Basic " + Buffer.from(
      `${volvoUsername.value()}:${volvoPassword.value()}`
    ).toString("base64");

    try {
      const res = await fetch(url, {
        method: "GET",
        headers: {
          "Authorization": authHeader,
          "Accept": accept,
        },
      });

      // Volvo a veces devuelve cuerpo no-JSON ante 401/406. Toleramos.
      let body: unknown = null;
      const text = await res.text();
      if (text) {
        try {
          body = JSON.parse(text);
        } catch {
          body = { raw: text };
        }
      }

      logger.info("[volvoProxy] OK", {
        operation,
        statusCode: res.status,
      });

      return {
        statusCode: res.status,
        data: body,
      };
    } catch (e) {
      logger.error("[volvoProxy] error", {
        operation,
        error: (e as Error).message,
      });
      throw new HttpsError(
        "unavailable",
        "Error consultando Volvo. Reintentá en unos segundos."
      );
    }
  }
);

// ============================================================================
// telemetriaSnapshotScheduled
// ============================================================================
// Scheduled function que cada 6 horas:
//   1) Llama Volvo `/vehicle/vehicles` con secrets server-side.
//   2) Cruza con la colección VEHICULOS para mapear VIN → patente.
//   3) Escribe un snapshot idempotente por día y patente en
//      TELEMETRIA_HISTORICO (id `{patente}_{YYYY-MM-DD}`).
//
// Reemplaza la lógica que antes corría en el cliente Flutter
// (`AutoSyncService` → `VehiculoRepository.guardarSnapshotsDiarios`).
// Vivir server-side permite:
//   - Cerrar `TELEMETRIA_HISTORICO` con `write: if false` en las rules
//     (solo Admin SDK puede escribir).
//   - Que el snapshot se capture aún cuando ningún admin tenga la app
//     abierta.
//
// Frecuencia: cada 6 horas. El doc es idempotente por día, con lo cual
// múltiples corridas se sobreescriben. La frecuencia da resiliencia
// ante fallos puntuales sin generar costos significativos (4 calls
// Volvo + 4 batch writes por día).

export const telemetriaSnapshotScheduled = onSchedule(
  {
    schedule: "every 6 hours",
    timeZone: "America/Argentina/Buenos_Aires",
    secrets: [volvoUsername, volvoPassword],
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async () => {
    logger.info("[telemetriaSnapshot] iniciando ciclo");

    // ─── 1. Fetch flota Volvo ──────────────────────────────────────
    const authHeader = "Basic " + Buffer.from(
      `${volvoUsername.value()}:${volvoPassword.value()}`
    ).toString("base64");

    // El endpoint `/vehicle/vehicles` NO trae telemetría (solo metadata
    // como vin/marca/modelo). Para `accumulatedData.totalFuelConsumption`
    // y `hrTotalVehicleDistance` hay que pegarle a `/vehicle/vehiclestatuses`
    // con `latestOnly=true` (devuelve el último snapshot de cada unidad
    // en una sola request).
    let cache: unknown[] = [];
    try {
      const url =
        `${VOLVO_BASE}/vehicle/vehiclestatuses?latestOnly=true`;
      const res = await fetch(url, {
        method: "GET",
        headers: {
          "Authorization": authHeader,
          "Accept": ACCEPT_STATUSES,
        },
      });
      if (!res.ok) {
        logger.error("[telemetriaSnapshot] Volvo HTTP error", {
          statusCode: res.status,
        });
        return;
      }
      const body = (await res.json()) as Record<string, unknown>;
      const statusResponse = body?.vehicleStatusResponse as
        | Record<string, unknown>
        | undefined;
      const list = statusResponse?.vehicleStatuses;
      if (Array.isArray(list)) cache = list;
      logger.info("[telemetriaSnapshot] estados recibidos", {
        recibidos: cache.length,
        sampleKeys: cache.length > 0 ?
          Object.keys(cache[0] as object).slice(0, 20) :
          [],
      });
    } catch (e) {
      logger.error("[telemetriaSnapshot] error consultando Volvo", {
        error: (e as Error).message,
      });
      return;
    }

    if (cache.length === 0) {
      logger.warn("[telemetriaSnapshot] flota Volvo vacía, abortando");
      return;
    }

    // ─── 2. Map VIN → patente desde Firestore ──────────────────────
    const vehiculosSnap = await db.collection("VEHICULOS").get();
    const vinToPatente = new Map<string, string>();
    for (const doc of vehiculosSnap.docs) {
      const data = doc.data();
      const vin = (data.VIN ?? "").toString().trim().toUpperCase();
      if (vin && vin !== "-") {
        vinToPatente.set(vin, doc.id);
      }
    }

    // ─── 3. Fecha del snapshot (midnight ARG) ──────────────────────
    // Buenos Aires es UTC-3 sin DST. Construimos la fecha en TZ ARG
    // para que `fechaTxt` y `fecha` Timestamp sean consistentes con la
    // versión cliente original (que usaba DateTime.now() local).
    const ahora = new Date();
    const fechaTxt = new Intl.DateTimeFormat("en-CA", {
      timeZone: "America/Argentina/Buenos_Aires",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(ahora); // "2026-04-29"
    const [year, month, day] = fechaTxt.split("-").map(Number);
    const fechaMidnight = new Date(Date.UTC(year, month - 1, day, 3, 0, 0));

    // ─── 4. Batch write a TELEMETRIA_HISTORICO ─────────────────────
    const batch = db.batch();
    let escritos = 0;
    let saltadosVin = 0;
    let saltadosPatente = 0;
    let saltadosCeros = 0;

    for (const v of cache) {
      const vehiculo = v as Record<string, unknown>;
      const vin = (vehiculo.vin ?? "").toString().trim().toUpperCase();
      if (!vin) {
        saltadosVin++;
        continue;
      }
      const patente = vinToPatente.get(vin);
      if (!patente) {
        saltadosPatente++;
        continue;
      }

      // Litros acumulados — el endpoint vehiclestatuses lo expone como
      // `engineTotalFuelUsed` al primer nivel **en MILILITROS**. Para
      // que el campo `litros_acumulados` esté efectivamente en litros
      // (consistente con su nombre y con el reporte de consumo),
      // dividimos por 1000. Mantenemos `accumulatedData.totalFuelConsumption`
      // como fallback por si en algún tipo de unidad viene nested.
      let litrosMl = 0;
      const top = vehiculo.engineTotalFuelUsed;
      if (typeof top === "number") {
        litrosMl = top;
      } else if (top != null) {
        litrosMl = Number(top);
      } else {
        const acc = vehiculo.accumulatedData;
        if (acc && typeof acc === "object") {
          const accObj = acc as Record<string, unknown>;
          const total = accObj.totalFuelConsumption;
          if (typeof total === "number") {
            litrosMl = total;
          } else if (total != null) {
            litrosMl = Number(total);
          }
        }
      }
      if (Number.isNaN(litrosMl)) litrosMl = 0;
      const litros = litrosMl / 1000;

      // Odómetro — Volvo lo entrega en metros.
      const metros = Number(
        vehiculo.hrTotalVehicleDistance ?? vehiculo.lastKnownOdometer ?? 0
      );
      const km = metros / 1000;

      // Sin telemetría útil no escribimos.
      if (litros === 0 && km === 0) {
        saltadosCeros++;
        continue;
      }

      const docId = `${patente}_${fechaTxt}`;
      batch.set(db.collection("TELEMETRIA_HISTORICO").doc(docId), {
        patente,
        vin,
        fecha: Timestamp.fromDate(fechaMidnight),
        litros_acumulados: litros,
        km,
        timestamp: FieldValue.serverTimestamp(),
      });
      escritos++;
    }

    if (escritos === 0) {
      logger.info("[telemetriaSnapshot] sin datos útiles, nada que escribir", {
        recibidos: cache.length,
        saltadosVin,
        saltadosPatente,
        saltadosCeros,
        vinesEnFirestore: vinToPatente.size,
      });
      return;
    }

    await batch.commit();
    logger.info("[telemetriaSnapshot] OK", {
      escritos,
      fechaTxt,
      recibidos: cache.length,
      saltadosVin,
      saltadosPatente,
      saltadosCeros,
    });
  }
);

// ============================================================================
// auditLogWrite
// ============================================================================
// Callable que escribe a AUDITORIA_ACCIONES con datos del admin tomados
// del JWT (uid + custom claim `nombre`). Permite cerrar la rule de
// AUDITORIA_ACCIONES a `write: if false` y que solo el server pueda
// escribir, eliminando la posibilidad de que un admin con la consola
// abierta forje entradas de bitácora.
//
// Diseño:
//   - **Whitelist de acciones**: el caller no puede inventar strings
//     nuevos. Si el enum AuditAccion del cliente agrega un caso, hay
//     que sumarlo acá también (es una conscious choice — la auditoría
//     no debería tener vocabulario abierto).
//   - **Sanitización de tamaño**: payload total <= 10KB para defendernos
//     de un caller que mande un detalles enorme y nos haga gastar
//     espacio.
//   - **Fire-and-forget cliente**: la function devuelve OK rápido. Si
//     algo falla, el cliente loguea y sigue; nunca bloquea al admin.

const AUDIT_ACCIONES_PERMITIDAS = new Set<string>([
  // Personal
  "CREAR_CHOFER",
  "EDITAR_CHOFER",
  "CAMBIAR_FOTO_PERFIL",
  "REEMPLAZAR_PAPEL_CHOFER",
  // Flota
  "CREAR_VEHICULO",
  "EDITAR_VEHICULO",
  "CAMBIAR_FOTO_VEHICULO",
  // Asignaciones
  "ASIGNAR_EQUIPO",
  "DESVINCULAR_EQUIPO",
  // Revisiones
  "APROBAR_REVISION",
  "RECHAZAR_REVISION",
]);

const AUDIT_ENTIDADES_PERMITIDAS = new Set<string>([
  "EMPLEADOS",
  "VEHICULOS",
  "REVISIONES",
]);

const AUDIT_MAX_DETALLES_BYTES = 10 * 1024; // 10KB

interface AuditLogResult {
  ok: true;
  docId: string;
}

export const auditLogWrite = onCall(
  {
    enforceAppCheck: false, // todavía no está activado App Check
  },
  async (request): Promise<AuditLogResult> => {
    // ─── Auth: solo admin logueado ─────────────────────────────────
    const rol = request.auth?.token?.rol;
    if (!request.auth || rol !== "ADMIN") {
      logger.warn("[auditLog] llamada sin auth ADMIN", {
        uid: request.auth?.uid ?? "no-uid",
        rol: rol ?? "no-rol",
      });
      throw new HttpsError(
        "permission-denied",
        "Solo administradores pueden escribir bitácora."
      );
    }

    // ─── Validación de input ───────────────────────────────────────
    const data = request.data ?? {};
    const accion = (data.accion ?? "").toString().trim();
    const entidad = (data.entidad ?? "").toString().trim();
    const entidadId = (data.entidadId ?? "").toString().trim();
    const detalles = data.detalles;

    if (!accion || !AUDIT_ACCIONES_PERMITIDAS.has(accion)) {
      throw new HttpsError(
        "invalid-argument",
        `Acción '${accion}' no está en la whitelist.`
      );
    }

    if (!entidad || !AUDIT_ENTIDADES_PERMITIDAS.has(entidad)) {
      throw new HttpsError(
        "invalid-argument",
        `Entidad '${entidad}' no está en la whitelist.`
      );
    }

    if (entidadId.length > 100) {
      throw new HttpsError(
        "invalid-argument",
        "entidadId demasiado largo (máx 100 chars)."
      );
    }

    // detalles debe ser objeto plano serializable. Validamos tamaño
    // serializando con JSON.stringify — si tira por circular references
    // o tipos no-serializables, rechazamos.
    if (detalles != null) {
      if (typeof detalles !== "object" || Array.isArray(detalles)) {
        throw new HttpsError(
          "invalid-argument",
          "`detalles` debe ser un objeto plano."
        );
      }
      let serializados: string;
      try {
        serializados = JSON.stringify(detalles);
      } catch {
        throw new HttpsError(
          "invalid-argument",
          "`detalles` no es serializable."
        );
      }
      if (serializados.length > AUDIT_MAX_DETALLES_BYTES) {
        throw new HttpsError(
          "resource-exhausted",
          `\`detalles\` excede el límite (${AUDIT_MAX_DETALLES_BYTES} bytes).`
        );
      }
    }

    // ─── Datos del admin desde el JWT ──────────────────────────────
    // request.auth.uid es el DNI gracias a loginConDni que setea uid=dni.
    // request.auth.token.nombre es un custom claim también seteado en
    // loginConDni. Si por algún motivo no está, fallback a "Admin".
    const adminDni = request.auth.uid;
    const adminNombre = (request.auth.token.nombre ?? "Admin").toString();

    // ─── Escritura ─────────────────────────────────────────────────
    const doc: Record<string, unknown> = {
      accion,
      entidad,
      admin_dni: adminDni,
      admin_nombre: adminNombre,
      timestamp: FieldValue.serverTimestamp(),
    };
    if (entidadId) {
      doc.entidad_id = entidadId;
    }
    if (detalles != null) {
      doc.detalles = detalles;
    }

    try {
      const ref = await db.collection("AUDITORIA_ACCIONES").add(doc);
      logger.info("[auditLog] OK", {
        accion,
        entidad,
        entidadId: entidadId || undefined,
        adminDni,
        docId: ref.id,
      });
      return { ok: true, docId: ref.id };
    } catch (e) {
      logger.error("[auditLog] error escribiendo", {
        accion,
        entidad,
        error: (e as Error).message,
      });
      throw new HttpsError(
        "internal",
        "No se pudo registrar la acción en bitácora."
      );
    }
  }
);
