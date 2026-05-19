// Helpers compartidos entre `index.ts` y `jornadas_v2.ts`.
//
// Antes vivían DUPLICADOS con leves diferencias en los 2 archivos
// (drift inevitable). Auditoría 2026-05-18 detectó:
//   - `_expiraEnMin` (jornadas_v2) vs `_expiraEnMinutos` (index)
//     → fórmula idéntica, solo cambia el nombre.
//   - `primerNombre` (jornadas_v2) vs `_primerNombre` (index)
//     → DRIFT SEMÁNTICO: jornadas devolvía "JUAN" sin capitalizar,
//       index devolvía "Juan" capitalizado. Unificamos a la versión
//       CAPITALIZADA (mejor UX en mensajes "Hola Juan, ...").
//   - `rrPick` (jornadas_v2) vs `_rrPick` (index)
//     → DRIFT ALGORÍTMICO: jornadas usaba `Math.random()` puro (podía
//       repetir índices consecutivos), index usaba round-robin con
//       counter (garantiza rotación). Unificamos al ROUND-ROBIN
//       (mejor anti-baneo de WhatsApp — diversidad asegurada).
//
// Naming sin prefijo `_`: estos helpers ahora son la API pública del
// módulo `helpers.ts` — el prefijo solo tiene sentido para "private al
// archivo" pero acá son explícitamente compartidos.

import * as admin from "firebase-admin";

// ─── Tipos ──────────────────────────────────────────────────────────
type Timestamp = admin.firestore.Timestamp;

// ────────────────────────────────────────────────────────────────────
// TIME — formato y TTL en TZ Argentina
// ────────────────────────────────────────────────────────────────────

const TZ_ARG = "America/Argentina/Buenos_Aires";
const OFFSET_ARG = "-03:00";

/**
 * Devuelve un Timestamp que expira N minutos en el futuro. Usado para
 * setear `expira_en` en docs de `COLA_WHATSAPP` time-sensitive (si el
 * bot está caído y el aviso se entrega después del TTL, el consumer
 * lo descarta sin enviar — mejor silencio que mensaje desactualizado).
 */
export function expiraEnMin(minutos: number): Timestamp {
  return admin.firestore.Timestamp.fromMillis(
    Date.now() + minutos * 60 * 1000,
  );
}

/**
 * Formatea HH:MM en TZ Argentina a partir de millis UTC. Independiente
 * de la TZ del runtime (Cloud Functions corre en UTC). Ejemplo de uso:
 * "Hola Juan, te quedan 15 min hasta las 12:30hs".
 */
export function formatHoraArg(millis: number): string {
  return new Intl.DateTimeFormat("es-AR", {
    timeZone: TZ_ARG,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(millis));
}

/**
 * Formatea DD/MM en TZ Argentina a partir de millis UTC. Usado en
 * mensajes al chofer para que la fecha del evento sea explícita
 * (no "hoy" — el bot puede demorar el envío al lunes si el evento
 * ocurrió el fin de semana, "hoy" sería ambiguo).
 */
export function formatFechaArg(millis: number): string {
  return new Intl.DateTimeFormat("es-AR", {
    timeZone: TZ_ARG,
    day: "2-digit",
    month: "2-digit",
  }).format(new Date(millis));
}

/**
 * Devuelve la fecha "ayer" en TZ Argentina como YYYY-MM-DD. Útil para
 * crons que arrancan a las 04:00 ART y queryean datos del día anterior.
 * Independiente del runtime (Cloud Functions corre en UTC).
 */
export function ayerYmdArg(): string {
  const ahora = new Date();
  const ymdHoy = new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ_ARG,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(ahora);
  const hoyArg = new Date(`${ymdHoy}T00:00:00${OFFSET_ARG}`);
  const ayer = new Date(hoyArg.getTime() - 24 * 60 * 60 * 1000);
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ_ARG,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(ayer);
}

/**
 * Devuelve un Date apuntando al inicio del día YMD en TZ Argentina
 * (00:00:00 -03:00). Útil para construir rangos de query por día.
 */
export function inicioDelDiaArg(ymd: string): Date {
  return new Date(`${ymd}T00:00:00${OFFSET_ARG}`);
}

// ────────────────────────────────────────────────────────────────────
// NOMBRE — extracción y formato para mensajes al chofer
// ────────────────────────────────────────────────────────────────────

/**
 * Devuelve el primer nombre capitalizado de un nombre completo estilo
 * Vecchi "APELLIDO NOMBRE [SEGUNDO_NOMBRE]". Ejemplos:
 *   "RODRIGUEZ JUAN"         → "Juan"
 *   "GARCIA PEREZ MARIA SOL" → "Maria"
 *   "MADONNA"                → "" (un solo token, no se puede inferir)
 *   ""                       → ""
 *
 * Si la inferencia falla devolvé "" para que el caller use el `APODO`
 * (campo manual en EMPLEADOS) como fallback explícito en lugar de
 * mandar un saludo raro.
 */
export function primerNombre(full: string): string {
  const partes = full.trim().split(/\s+/);
  if (partes.length < 2) return "";
  const n = partes[1];
  if (!n) return "";
  return n[0].toUpperCase() + n.slice(1).toLowerCase();
}

// ────────────────────────────────────────────────────────────────────
// RANDOMIZACIÓN — variantes anti-baneo de WhatsApp
// ────────────────────────────────────────────────────────────────────

/**
 * Round-robin de índice para elegir entre N variantes de un mensaje.
 * Cada llamada avanza el counter y devuelve `counter % N`. Garantiza
 * que mensajes consecutivos toman variantes DISTINTAS (vs `Math.random()`
 * puro que puede repetir el mismo índice 3 veces seguidas y dispararle
 * el detector de duplicados a WhatsApp).
 *
 * Estado: el counter es module-level (vive mientras la instancia esté
 * caliente). Si la instancia se enfría y otra arranca fría, vuelve a
 * 0 — eso es OK, lo importante es la diversidad dentro de una ráfaga.
 *
 * Detalle de implementación: usamos `>>> 0` (unsigned right shift de
 * 0 bits) para wrappear el counter como uint32. Sin esto, al cruzar
 * 2^31 saltaba a -2^31 (int32 signed) y `idx = counter % len` daba
 * negativo (en JS `(-3) % 8 = -3`, NO 5 como en otras lenguas) →
 * `variantes[-3] = undefined` y mensaje vacío. Edge case raro pero
 * documentado por si lo vuelven a tocar.
 */
let _rrCounter = 0;
export function rrPick(len: number): number {
  if (len <= 0) return 0;
  const idx = _rrCounter % len;
  _rrCounter = (_rrCounter + 1) >>> 0;
  return idx;
}
