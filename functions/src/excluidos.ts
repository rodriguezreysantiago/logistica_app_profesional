// =============================================================================
// EXCLUIDOS — choferes/vehículos que NO controla Coopertrans Móvil
// =============================================================================
//
// Caso de negocio (Santiago 2026-05-19): hay 3 choferes asignados a 3
// **enganches TANQUE** (combustibles líquidos). Están en la cuenta
// Sitrack `ws41629VecchiSRL` compartida porque pertenecen a la misma
// razón social, pero operativamente son de OTRA unidad de negocio que
// Vecchi NO controla — los maneja otra área de la empresa.
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

    if (patentesTanque.size === 0) {
      // Sin tanques cargados → set vacío. Cacheamos igual para no
      // martillar Firestore con queries vacías.
      _cacheData = EXCLUIDOS_VACIO;
      _cacheExpiraEn = Date.now() + TTL_MS;
      return _cacheData;
    }

    // ─── 2. Choferes asignados a esos enganches ──────────────────
    // Leemos TODOS los EMPLEADOS (filtrados por rol CHOFER para
    // reducir reads) y filtramos client-side por ENGANCHE in tanques.
    // Alternativa: `where('ENGANCHE', 'in', [...])` Firestore limita
    // a 30 valores — con 3 nos sobra, pero client-side es más
    // robusto contra crecimiento futuro.
    const empSnap = await database
      .collection("EMPLEADOS")
      .where("ROL", "==", "CHOFER")
      .limit(1000)
      .get();
    const dnis = new Set<string>();
    const tractoresExcluidos = new Set<string>();
    for (const d of empSnap.docs) {
      const data = d.data();
      if (data.ACTIVO === false) continue;
      const enganche = (data.ENGANCHE ?? "").toString().trim().toUpperCase();
      if (!enganche || !patentesTanque.has(enganche)) continue;
      dnis.add(d.id);
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
      choferesAsignados: dnis.size,
      tractoresExcluidos: tractoresExcluidos.size,
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
