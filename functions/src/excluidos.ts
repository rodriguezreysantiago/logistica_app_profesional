// =============================================================================
// EXCLUIDOS — choferes/vehículos/usuarios que NO controla Coopertrans Móvil
// =============================================================================
//
// Hay DOS familias de exclusión con razones distintas:
//
// ─── (A) Choferes TANQUE (combustibles líquidos) ──────────────────────
// Caso de negocio (Santiago 2026-05-19): 3 choferes asignados a 3
// **enganches TANQUE**. Están en la cuenta Sitrack `ws41629VecchiSRL`
// compartida porque pertenecen a la misma razón social, pero
// operativamente son de OTRA unidad de negocio que Vecchi NO controla
// — los maneja otra área de la empresa.
//
// Sin filtrar, esos 3 choferes y sus camiones aparecen en:
//   - Ranking ICM semanal a Molina (con eventos que no son nuestros)
//   - Resumen conducta diario (mezclan con la operativa de Vecchi)
//   - Resumen drifts (sus iButton confunden el cross-check)
//   - Resumen excesos jornada (no controlamos su jornada)
//   - KPI dashboard `choferes_activos` (inflan el conteo)
//   - Reportes Excel de personal / flota / consumo
//   - Bot WhatsApp avisos (vencimientos, "pasá iButton", jornada)
//
// Decisión: "como si no existieran" — NO borrar (son empleados reales
// de la razón social Vecchi y los enganches están patentados a su
// nombre), pero EXCLUIR de todos los crons / queries / reportes.
//
// **Identificación dinámica** (sin hardcoded DNIs ni patentes):
//   1. Set base = `VEHICULOS where TIPO='TANQUE'` → 3 patentes
//   2. DNIs excluidos = `EMPLEADOS where ENGANCHE in patentesTanque`
//   3. Patentes de TRACTOR excluidos = `EMPLEADOS.VEHICULO` de esos DNIs
//   4. Patentes totales excluidas = enganches TANQUE + tractores asociados
//
// Si en el futuro se suma un 4to tanque o el chofer rota a otro
// vehículo, el sistema lo detecta automáticamente (solo hay que cargar
// el doc en VEHICULOS con TIPO=TANQUE o asignar el ENGANCHE al chofer).
// NO requiere deploy ni hardcoded list que mantener.
//
// ─── (B) Usuarios tester (Apple Reviewer + Android tester) ────────────
// Santiago 2026-05-18 (post go-live Play Store + TestFlight Externo):
// "tendríamos que hacer la exclusión también de los testers, aparecen
// para adelantos y demás, además de que ya estamos operativos, y los
// empleados me preguntaron por los 2 usuarios testers".
//
// Apple Reviewer (DNI 00000001) y el Android tester son cuentas DEMO
// creadas para que Apple/Google revisen la app. Tienen rol ADMIN para
// que el reviewer pueda navegar todo. NO son empleados reales, no
// tienen vehículo asignado, pero aparecen en:
//   - Dropdown de adelantos (logística) → empleados reales preguntan
//   - Listados admin de personal
//   - Reportes Excel de personal
//
// **Identificación dinámica** (sin hardcoded DNIs):
//   Regex sobre EMPLEADOS.NOMBRE: `/\b(reviewer|tester|demo)\b/i`
//   Word boundary evita falsos positivos ("Demolición" NO matchea).
//   Case-insensitive — funciona con "REVIEWER" o "Reviewer".
//
// Si se crean más cuentas demo en el futuro (ej: "Demo Cliente",
// "Tester Android v2"), quedan excluidas automáticamente sin deploy.

import { Firestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import { db } from "./setup";

export interface SetExcluidos {
  /** DNIs de los 3 choferes asignados a enganches TANQUE. */
  dnis: Set<string>;
  /** Patentes excluidas (enganches TANQUE + tractores que esos choferes
   * tienen asignados). UPPERCASE normalizada. */
  patentes: Set<string>;
}

const EXCLUIDOS_VACIO: SetExcluidos = {
  dnis: new Set<string>(),
  patentes: new Set<string>(),
};

// Cache in-memory por instancia de Cloud Function. TTL 10 min — los
// datos cambian raramente (alta/baja de chofer o tanque es manual,
// y un delay de hasta 10 min en propagar la exclusión es tolerable).
//
// Cuando GCP enfría la instancia, la próxima fría re-lee. Cuando varias
// instancias corren en paralelo, cada una tiene su cache — no es
// problema porque la fuente de verdad (Firestore) es consistente.
let _cacheData: SetExcluidos | null = null;
let _cacheExpiraEn = 0;
const TTL_MS = 10 * 60 * 1000;

/**
 * Regex para detectar usuarios tester por NOMBRE. Apple Reviewer y los
 * Android testers tienen estos términos en el nombre. Word boundary
 * evita falsos positivos ("Demolición", "Restful" no matchean).
 * Case-insensitive: matchea "REVIEWER", "Reviewer", "reviewer", etc.
 */
const PATTERN_TESTER = /\b(reviewer|tester|demo)\b/i;

/**
 * Devuelve los DNIs y patentes que deben EXCLUIRSE de todo proceso
 * operativo. Cacheado 10 min in-memory.
 *
 * Si Firestore falla, devuelve el set vacío (fail-safe: mejor incluir
 * a alguien indebido por 1 ciclo que romper todos los crons por una
 * query caída). Loguea WARN para diagnóstico.
 *
 * **Llamar UNA vez al inicio de cada cron** y reutilizar el resultado
 * — NO llamar dentro del loop de eventos (innecesario, los reads de
 * EMPLEADOS+VEHICULOS no son baratos).
 */
export async function cargarExcluidos(
  database: Firestore = db,
): Promise<SetExcluidos> {
  if (_cacheData && Date.now() < _cacheExpiraEn) {
    return _cacheData;
  }

  try {
    // ─── 1. Patentes de enganches TANQUE ──────────────────────────
    const tanquesSnap = await database
      .collection("VEHICULOS")
      .where("TIPO", "==", "TANQUE")
      .limit(100) // defensivo — esperamos ~3
      .get();
    const patentesTanque = new Set<string>();
    for (const d of tanquesSnap.docs) {
      patentesTanque.add(d.id.toUpperCase());
    }

    // ─── 2. Iterar EMPLEADOS — detectar testers + choferes tanque ──
    // Leemos TODOS los EMPLEADOS (sin filtro de rol — Apple Reviewer es
    // ADMIN, no CHOFER, así que un filtro `where ROL == CHOFER` los
    // omitiría). Costo trivial: la colección tiene <100 docs reales.
    const empSnap = await database
      .collection("EMPLEADOS")
      .limit(1000)
      .get();
    const dnis = new Set<string>();
    const tractoresExcluidos = new Set<string>();
    let testersDetectados = 0;
    let tanquerosDetectados = 0;
    for (const d of empSnap.docs) {
      const data = d.data();
      if (data.ACTIVO === false) continue;

      // (a) Testers por NOMBRE — independiente de rol/vehículo
      const nombre = (data.NOMBRE ?? "").toString();
      if (PATTERN_TESTER.test(nombre)) {
        dnis.add(d.id);
        testersDetectados++;
        // No seguimos con la detección tanque: un tester demo no tiene
        // tractor real cuyo patente sumar al set.
        continue;
      }

      // (b) Choferes asignados a enganche TANQUE (solo si hay tanques)
      if (patentesTanque.size === 0) continue;
      const enganche = (data.ENGANCHE ?? "").toString().trim().toUpperCase();
      if (!enganche || !patentesTanque.has(enganche)) continue;
      dnis.add(d.id);
      tanquerosDetectados++;
      // El tractor asignado a este chofer también queda excluido
      // (sus eventos Sitrack/Volvo vienen con esa patente).
      const tractor = (data.VEHICULO ?? "").toString().trim().toUpperCase();
      if (tractor && tractor !== "-") {
        tractoresExcluidos.add(tractor);
      }
    }

    // ─── 3. Combinar set total de patentes (tanques + tractores) ──
    const patentes = new Set<string>([
      ...patentesTanque,
      ...tractoresExcluidos,
    ]);

    _cacheData = { dnis, patentes };
    _cacheExpiraEn = Date.now() + TTL_MS;

    logger.info("[cargarExcluidos] cache actualizado", {
      tanques: patentesTanque.size,
      tanqueros: tanquerosDetectados,
      testers: testersDetectados,
      tractoresExcluidos: tractoresExcluidos.size,
      totalDnis: dnis.size,
      totalPatentes: patentes.size,
    });

    return _cacheData;
  } catch (e) {
    // Fail-safe: si Firestore está caído, no romper los crons.
    // Devolvemos el set vacío (NO excluye nada) y loggeamos WARN.
    // El próximo ciclo reintenta.
    logger.warn("[cargarExcluidos] query fallo, devuelve vacio", {
      error: (e as Error).message,
    });
    return EXCLUIDOS_VACIO;
  }
}

/**
 * Helper de conveniencia para chequear si un DNI o patente está
 * excluido. Acepta valores en cualquier case — internamente normaliza
 * a upper para patentes (DNIs no se normalizan porque son numéricos).
 */
export function esExcluido(
  excluidos: SetExcluidos,
  opts: { dni?: string; patente?: string },
): boolean {
  if (opts.dni && excluidos.dnis.has(opts.dni)) return true;
  if (opts.patente) {
    const norm = opts.patente.toString().trim().toUpperCase();
    if (norm && excluidos.patentes.has(norm)) return true;
  }
  return false;
}

/**
 * Solo para tests: invalida el cache forzando re-lectura en la
 * próxima llamada. NO usar en producción.
 */
export function _resetCacheExcluidosParaTests(): void {
  _cacheData = null;
  _cacheExpiraEn = 0;
}
