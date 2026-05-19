// =============================================================================
// recomputeIcmSemanalScheduled — agregados ICM semanales en `ICM_SEMANAL`
// =============================================================================
// Refactor mayor 2026-05-19: implementación EXACTA CESVI homologada
// (presentación Carsync). Ver `icm_cesvi.ts` para las funciones puras
// y los pesos por tipo. Decisión Santiago: usar las JORNADAS del
// vigilador v2 como unidad del cálculo (no "viaje" CESVI estricto
// motor ON/OFF), promediado por km.
//
// Cada lunes 6 AM ART calcula los agregados de la SEMANA ANTERIOR
// (lun-dom que acaba de cerrar) y los persiste en `ICM_SEMANAL/{YYYY-WW}`.
//
// El cliente Flutter (módulo ICM) lee primero de esta colección (rápido,
// ~50 docs históricos máximo) y solo cae al cálculo on-the-fly desde
// SITRACK_EVENTOS para la semana actual que aún no cerró. Eso evita
// recomputar 12 semanas de eventos cada vez que se abre el reporte.
//
// Schema del doc `ICM_SEMANAL/{YYYY-WW}` (compat hacia atrás mantenido):
//   {
//     semana_id: string ("2026-W20" — ISO week format),
//     semana_inicio_ts: Timestamp (lunes 00:00 ART),
//     semana_fin_ts: Timestamp (siguiente lunes 00:00 ART),
//     semana_label: string ("12-18 May"),
//     icm_promedio: number (0-100, ponderado por km flota),
//     total_eventos: number (count de eventos CESVI puros),
//     choferes_activos: number,
//     choferes_verdes: number,    // ICM >= 80
//     choferes_amarillos: number, // 60 <= ICM < 80
//     choferes_rojos: number,     // ICM < 60
//     choferes: [{ dni, nombre, icm, total_eventos, ratio_100km,
//                  categoria, eventos_por_tipo, km_recorridos,
//                  jornadas_contadas }],
//     top_5_mejores: [{ dni, nombre, icm }],
//     top_5_peores: [{ dni, nombre, icm }],
//     calculado_en: Timestamp (server),
//   }

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { db } from "./setup";
import { hashId, TIPOS_CESVI_PUROS } from "./index";
import { cargarExcluidos } from "./excluidos";
import {
  EventoSitrackICM,
  calcularIcmJornada,
  combinarJornadas,
  categorizar,
} from "./icm_cesvi";

/** Mínimo de km en una jornada para considerarla "con datos". Debajo de
 * esto el ICM no es estadísticamente útil. */
const KM_MIN_JORNADA = 10;

/** Cap defensivo: una jornada no puede recorrer más de 2000 km
 * (auditoria operativa Vecchi). Si max-min de odómetro supera esto, es
 * casi seguro un reset de odómetro Sitrack y descartamos la jornada. */
const KM_MAX_JORNADA = 2000;

export const recomputeIcmSemanalScheduled = onSchedule(
  {
    // Lunes 6 AM ART — la semana que termina justo el domingo 23:59
    // ya está cerrada y completa.
    schedule: "0 6 * * 1",
    timeZone: "America/Argentina/Buenos_Aires",
    timeoutSeconds: 240,
    memory: "512MiB",
  },
  async () => {
    logger.info("[recomputeIcmSemanalScheduled] iniciando");

    // ─── 1. Calcular rango de la SEMANA ANTERIOR en ART ────────────
    const ahora = new Date();
    const fechaArtHoy = new Intl.DateTimeFormat("en-CA", {
      timeZone: "America/Argentina/Buenos_Aires",
      year: "numeric", month: "2-digit", day: "2-digit",
    }).format(ahora);
    const lunesActualMs = Date.parse(`${fechaArtHoy}T00:00:00-03:00`);
    const lunesAnteriorMs = lunesActualMs - 7 * 24 * 60 * 60 * 1000;

    const semanaInicio = new Date(lunesAnteriorMs);
    const semanaFin = new Date(lunesActualMs);
    const semanaId = _isoWeekId(semanaInicio);
    const semanaLabel = _semanaLabel(semanaInicio, semanaFin);

    logger.info("[recomputeIcmSemanalScheduled] rango", {
      semanaId, semanaLabel,
      desde: semanaInicio.toISOString(),
      hasta: semanaFin.toISOString(),
    });

    // ─── 2. Lookup nombres de empleados ───────────────────────────
    const empSnap = await db.collection("EMPLEADOS").limit(5000).get();
    const nombrePorDni = new Map<string, string>();
    for (const d of empSnap.docs) {
      const data = d.data();
      const dni = (data.DNI ?? d.id).toString();
      const nombre = (data.NOMBRE ?? "").toString().trim();
      if (nombre) nombrePorDni.set(dni, nombre);
    }

    // ─── 3. Cargar excluidos (3 choferes tanqueros + testers) ────
    const excluidos = await cargarExcluidos(db);

    // ─── 4. Cargar JORNADAS cerradas en el rango ──────────────────
    // Filtramos por `jornada_fin_ts` (jornadas cerradas) en la semana.
    // Una jornada cuya cierre cayó dentro de la semana se cuenta acá,
    // aunque su inicio haya sido el lunes a las 23:50 (caso borde).
    const jornSnap = await db
      .collection("JORNADAS")
      .where("jornada_fin_ts", ">=", Timestamp.fromMillis(lunesAnteriorMs))
      .where("jornada_fin_ts", "<", Timestamp.fromMillis(lunesActualMs))
      .limit(5000)
      .get();
    logger.info("[recomputeIcmSemanalScheduled] jornadas cargadas",
      { count: jornSnap.size });

    // ─── 5. Cargar eventos Sitrack del rango (CESVI puros + otros
    // para tracking de odómetro/km) ────────────────────────────────
    const LIMIT_SITRACK = 200000;
    const evSnap = await db
      .collection("SITRACK_EVENTOS")
      .where("report_date", ">=", Timestamp.fromMillis(lunesAnteriorMs))
      .where("report_date", "<", Timestamp.fromMillis(lunesActualMs))
      .limit(LIMIT_SITRACK)
      .get();
    if (evSnap.size >= LIMIT_SITRACK) {
      logger.warn(
        "[recomputeIcmSemanalScheduled] SITRACK_EVENTOS alcanzó limit " +
        `(${LIMIT_SITRACK}). ICM puede estar incompleto.`,
      );
    }

    // Indexar eventos por (dni, tsMs) para asignarlos a jornadas.
    // Estructura: dni → array ordenado por timestamp.
    interface EventoRaw {
      eventId: number;
      reportDateMs: number;
      assetId: string;
      driverDni: string;
      eventName: string;
      speed: number | null;
      cartographyLimitSpeed: number | null;
      areaType: string;
      odometer: number | null;
    }
    const eventosPorDni = new Map<string, EventoRaw[]>();
    for (const d of evSnap.docs) {
      const data = d.data();
      const dni = (data.driver_dni ?? "").toString().trim();
      if (!dni) continue;
      if (excluidos.dnis.has(dni)) continue;
      const patente = (data.asset_id ?? "").toString().trim().toUpperCase();
      if (patente && excluidos.patentes.has(patente)) continue;
      const tsMs = (data.report_date as Timestamp | undefined)?.toMillis?.();
      if (!tsMs) continue;
      const e: EventoRaw = {
        eventId: typeof data.event_id === "number" ? data.event_id : -1,
        reportDateMs: tsMs,
        assetId: patente,
        driverDni: dni,
        eventName: (data.event_name ?? "").toString(),
        speed: typeof data.speed === "number" ? data.speed :
          (typeof data.gps_speed === "number" ? data.gps_speed : null),
        cartographyLimitSpeed:
          typeof data.cartography_limit_speed === "number" ?
            data.cartography_limit_speed : null,
        areaType: (data.area_type ?? "unknown").toString(),
        odometer: typeof data.odometer === "number" ? data.odometer :
          (typeof data.gps_odometer === "number" ? data.gps_odometer : null),
      };
      const arr = eventosPorDni.get(dni) ?? [];
      arr.push(e);
      eventosPorDni.set(dni, arr);
    }
    // Ordenar cada array por timestamp ascendente (binary search ready)
    for (const arr of eventosPorDni.values()) {
      arr.sort((a, b) => a.reportDateMs - b.reportDateMs);
    }

    // ─── 6. Por cada jornada, calcular ICM CESVI ──────────────────
    interface JornadaCalculada {
      dni: string;
      icm: number;
      km: number;
      desglose: ReturnType<typeof calcularIcmJornada>["desglose"];
    }
    const porChofer = new Map<string, JornadaCalculada[]>();
    let jornadasDescartadasPorKm = 0;
    let jornadasDescartadasPorCap = 0;
    for (const jDoc of jornSnap.docs) {
      const j = jDoc.data();
      const dni = (j.chofer_dni ?? "").toString().trim();
      if (!dni) continue;
      if (excluidos.dnis.has(dni)) continue;
      const iniMs = (j.jornada_inicio_ts as Timestamp | undefined)?.toMillis?.();
      const finMs = (j.jornada_fin_ts as Timestamp | undefined)?.toMillis?.();
      if (!iniMs || !finMs || finMs <= iniMs) continue;
      // Eventos del chofer en la ventana de la jornada
      const todosDelDni = eventosPorDni.get(dni) ?? [];
      const eventosEnVentana: EventoSitrackICM[] = [];
      let odMin = Infinity;
      let odMax = -Infinity;
      for (const e of todosDelDni) {
        if (e.reportDateMs < iniMs) continue;
        if (e.reportDateMs > finMs) break; // ordenado, podemos cortar
        if (e.assetId && excluidos.patentes.has(e.assetId)) continue;
        // Solo aporta al cálculo CESVI si el evento es de tipo CESVI puro.
        if (TIPOS_CESVI_PUROS.has(e.eventId)) {
          eventosEnVentana.push({
            eventId: e.eventId,
            reportDateMs: e.reportDateMs,
            assetId: e.assetId,
            driverDni: e.driverDni,
            speed: e.speed,
            cartographyLimitSpeed: e.cartographyLimitSpeed,
            areaType: e.areaType,
            odometer: e.odometer,
          });
        }
        // Pero TODOS los eventos con odómetro válido aportan al cálculo
        // de km de la jornada (no solo los CESVI).
        if (e.odometer !== null && e.odometer > 0) {
          if (e.odometer < odMin) odMin = e.odometer;
          if (e.odometer > odMax) odMax = e.odometer;
        }
      }
      // Km de la jornada
      let km = 0;
      if (odMax > odMin && odMin !== Infinity) {
        const delta = odMax - odMin;
        if (delta > KM_MAX_JORNADA) {
          jornadasDescartadasPorCap++;
          logger.warn(
            "[recomputeIcmSemanal] jornada descartada por reset odómetro",
            { dniHash: hashId(dni), deltaKm: Math.round(delta) },
          );
          continue;
        }
        km = delta;
      }
      if (km < KM_MIN_JORNADA) {
        jornadasDescartadasPorKm++;
        continue;
      }
      // Bloques de manejo del vigilador para fatiga
      const bloquesCompletos = typeof j.bloques_completos === "number" ?
        j.bloques_completos : 0;
      const bloqueActualSeg = typeof j.bloque_actual_manejo_seg === "number" ?
        j.bloque_actual_manejo_seg : 0;
      const totalManejoSeg = typeof j.total_manejo_seg === "number" ?
        j.total_manejo_seg : (bloquesCompletos * 4 * 3600 + bloqueActualSeg);
      // Asumimos bloques cerrados de ~4h cada uno + el bloque actual con
      // su tiempo parcial. Si tenemos más detalle en el futuro, refinar.
      const manejoSegPorBloque: number[] = [];
      for (let i = 0; i < bloquesCompletos; i++) {
        manejoSegPorBloque.push(4 * 3600);
      }
      if (bloqueActualSeg > 0) manejoSegPorBloque.push(bloqueActualSeg);
      // Defensivo: si no hay bloques pero hay manejo total, lo asignamos
      // a un único bloque (puede pasar con jornadas viejas pre-vigilador).
      if (manejoSegPorBloque.length === 0 && totalManejoSeg > 0) {
        manejoSegPorBloque.push(totalManejoSeg);
      }
      const resultado = calcularIcmJornada(eventosEnVentana, manejoSegPorBloque);
      const lista = porChofer.get(dni) ?? [];
      lista.push({
        dni,
        icm: resultado.icm,
        km,
        desglose: resultado.desglose,
      });
      porChofer.set(dni, lista);
    }
    logger.info("[recomputeIcmSemanalScheduled] jornadas procesadas", {
      total: jornSnap.size,
      descartadasPorKm: jornadasDescartadasPorKm,
      descartadasPorCap: jornadasDescartadasPorCap,
      choferesConJornadas: porChofer.size,
    });

    // ─── 7. Combinar jornadas en ICM agregado por chofer ──────────
    interface ChoferAgg {
      dni: string;
      nombre: string;
      icm: number;
      total_eventos: number;
      ratio_100km: number;
      categoria: string;
      eventos_por_tipo: Record<string, number>;
      km_recorridos: number;
      jornadas_contadas: number;
    }
    const choferes: ChoferAgg[] = [];
    for (const [dni, jornadas] of porChofer.entries()) {
      const agregado = combinarJornadas(jornadas);
      const totalEventosCesvi =
        agregado.desgloseSumado.aceleracionesBruscas +
        agregado.desgloseSumado.frenadasBruscas +
        agregado.desgloseSumado.girosBruscos +
        agregado.desgloseSumado.sobrevelocidades;
      const ratio = agregado.kmTotales > 0 ?
        totalEventosCesvi / (agregado.kmTotales / 100) : 0;
      choferes.push({
        dni,
        nombre: nombrePorDni.get(dni) ?? `DNI ${dni}`,
        icm: Number(agregado.icm.toFixed(2)),
        total_eventos: totalEventosCesvi,
        ratio_100km: Number(ratio.toFixed(2)),
        categoria: agregado.categoria,
        eventos_por_tipo: {
          "Aceleración brusca": agregado.desgloseSumado.aceleracionesBruscas,
          "Frenada brusca": agregado.desgloseSumado.frenadasBruscas,
          "Giro brusco": agregado.desgloseSumado.girosBruscos,
          "Sobrevelocidad": agregado.desgloseSumado.sobrevelocidades,
        },
        km_recorridos: Number(agregado.kmTotales.toFixed(1)),
        jornadas_contadas: agregado.jornadas,
      });
    }

    // ─── 8. Agregados flota ───────────────────────────────────────
    const choferesConDatos = choferes.filter((c) => c.categoria !== "SIN_DATOS");
    const totalEventos = choferes.reduce((acc, c) => acc + c.total_eventos, 0);
    // ICM promedio ponderado por km (no aritmético) — consistente con
    // cómo CESVI presenta el ICM del contratista.
    const sumKm = choferesConDatos.reduce((acc, c) => acc + c.km_recorridos, 0);
    const sumIcmKm = choferesConDatos.reduce(
      (acc, c) => acc + c.icm * c.km_recorridos, 0);
    const icmPromedio = sumKm > 0 ?
      Number((sumIcmKm / sumKm).toFixed(2)) : 0;
    const verdes = choferesConDatos.filter((c) => c.categoria === "BAJO").length;
    const amarillos = choferesConDatos.filter((c) => c.categoria === "MEDIO").length;
    const rojos = choferesConDatos.filter((c) => c.categoria === "ALTO").length;
    const sinDatos = choferes.filter((c) => c.categoria === "SIN_DATOS").length;
    const sortedAsc = [...choferesConDatos].sort((a, b) => a.icm - b.icm);
    const top5Peores = sortedAsc.slice(0, 5).map((c) => ({
      dni: c.dni, nombre: c.nombre, icm: c.icm,
    }));
    const top5Mejores = sortedAsc.slice(-5).reverse().map((c) => ({
      dni: c.dni, nombre: c.nombre, icm: c.icm,
    }));

    // ─── 9. Persistir en ICM_SEMANAL/{YYYY-WW} ─────────────────────
    await db.collection("ICM_SEMANAL").doc(semanaId).set({
      semana_id: semanaId,
      semana_inicio_ts: Timestamp.fromMillis(lunesAnteriorMs),
      semana_fin_ts: Timestamp.fromMillis(lunesActualMs),
      semana_label: semanaLabel,
      icm_promedio: icmPromedio,
      total_eventos: totalEventos,
      choferes_activos: choferesConDatos.length,
      choferes_sin_datos: sinDatos,
      choferes_verdes: verdes,
      choferes_amarillos: amarillos,
      choferes_rojos: rojos,
      choferes,
      top_5_mejores: top5Mejores,
      top_5_peores: top5Peores,
      formula_version: "cesvi-1.0", // marcador para migración futura
      calculado_en: FieldValue.serverTimestamp(),
    });

    logger.info("[recomputeIcmSemanalScheduled] OK", {
      semanaId, icmPromedio, totalEventos,
      choferesConDatos: choferesConDatos.length,
      sinDatos, verdes, amarillos, rojos,
    });
  }
);

// Re-exports para que el helper de categorización quede accesible desde
// el cliente y para tests (compat con consumidores externos del módulo).
export { categorizar as categorizarIcm };

// Helper: ID semana ISO 8601 ("YYYY-WNN") de un Date.
// Fix auditoria 2026-05-16: antes mezclaba UTC y local. Ahora UTC
// consistente desde el primer paso.
function _isoWeekId(d: Date): string {
  const target = new Date(Date.UTC(
    d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()
  ));
  const dayNum = (target.getUTCDay() + 6) % 7;
  target.setUTCDate(target.getUTCDate() - dayNum + 3);
  const firstThursday = new Date(Date.UTC(target.getUTCFullYear(), 0, 4));
  const week = 1 + Math.round(
    ((target.getTime() - firstThursday.getTime()) / 86400000 -
      3 + ((firstThursday.getUTCDay() + 6) % 7)) / 7
  );
  const year = target.getUTCFullYear();
  return `${year}-W${week.toString().padStart(2, "0")}`;
}

// Helper: label legible de una semana ("12-18 May" o "30 Abr - 6 May").
function _semanaLabel(inicio: Date, fin: Date): string {
  const meses = [
    "Ene", "Feb", "Mar", "Abr", "May", "Jun",
    "Jul", "Ago", "Sep", "Oct", "Nov", "Dic",
  ];
  const finDom = new Date(fin.getTime() - 24 * 60 * 60 * 1000);
  const inicioArt = new Date(inicio.getTime() - 3 * 60 * 60 * 1000);
  const finArt = new Date(finDom.getTime() - 3 * 60 * 60 * 1000);
  if (inicioArt.getUTCMonth() === finArt.getUTCMonth()) {
    return `${inicioArt.getUTCDate()}-${finArt.getUTCDate()} ` +
      meses[inicioArt.getUTCMonth()];
  }
  return `${inicioArt.getUTCDate()} ${meses[inicioArt.getUTCMonth()]} - ` +
    `${finArt.getUTCDate()} ${meses[finArt.getUTCMonth()]}`;
}
