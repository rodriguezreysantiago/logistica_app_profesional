// =============================================================================
// recomputeIcmSemanalScheduled — agregados ICM semanales en `ICM_SEMANAL`
// =============================================================================
// Extraído de index.ts el 2026-05-18 (split del archivo de 6884 LOC).
//
// Cada lunes 6 AM ART calcula los agregados de la SEMANA ANTERIOR
// (lun-dom que acaba de cerrar) y los persiste en `ICM_SEMANAL/{YYYY-WW}`.
//
// El cliente Flutter (módulo ICM) lee primero de esta colección (rápido,
// ~50 docs históricos máximo) y solo cae al cálculo on-the-fly desde
// SITRACK_EVENTOS para la semana actual que aún no cerró. Eso evita
// recomputar 12 semanas de eventos cada vez que se abre el reporte.
//
// Schema del doc `ICM_SEMANAL/{YYYY-WW}`:
//   {
//     semana_id: string ("2026-W20" — ISO week format),
//     semana_inicio_ts: Timestamp (lunes 00:00 ART),
//     semana_fin_ts: Timestamp (siguiente lunes 00:00 ART),
//     semana_label: string ("12-18 May"),
//     icm_promedio: number (0-100),
//     total_eventos: number,
//     choferes_activos: number,
//     choferes_verdes: number,    // ICM >= 80
//     choferes_amarillos: number, // 60 <= ICM < 80
//     choferes_rojos: number,     // ICM < 60
//     choferes: [{ dni, nombre, icm, total_eventos, ratio_100km, categoria }],
//     top_5_mejores: [{ dni, nombre, icm }],
//     top_5_peores: [{ dni, nombre, icm }],
//     calculado_en: Timestamp (server),
//   }

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { db } from "./setup";
// hashId y TIPOS_PELIGROSOS_SITRACK siguen viviendo en index.ts (se
// re-exportan ahí para que múltiples módulos extraidos puedan
// importarlos sin acoplarse entre sí).
import { hashId, TIPOS_PELIGROSOS_SITRACK } from "./index";

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
    // "Hoy" es el lunes 6 AM ART. La semana cerrada va del lunes
    // anterior 00:00 al lunes actual 00:00.
    const ahora = new Date();
    const fechaArtHoy = new Intl.DateTimeFormat("en-CA", {
      timeZone: "America/Argentina/Buenos_Aires",
      year: "numeric", month: "2-digit", day: "2-digit",
    }).format(ahora);
    // Lunes actual 00:00 ART en epoch ms.
    const lunesActualMs = Date.parse(`${fechaArtHoy}T00:00:00-03:00`);
    const lunesAnteriorMs = lunesActualMs - 7 * 24 * 60 * 60 * 1000;

    const semanaInicio = new Date(lunesAnteriorMs);
    const semanaFin = new Date(lunesActualMs);

    // ID ISO Week (ej. "2026-W20")
    const semanaId = _isoWeekId(semanaInicio);
    const semanaLabel = _semanaLabel(semanaInicio, semanaFin);

    logger.info("[recomputeIcmSemanalScheduled] rango", {
      semanaId,
      semanaLabel,
      desde: semanaInicio.toISOString(),
      hasta: semanaFin.toISOString(),
    });

    // ─── 2. Lookup nombres de empleados ───────────────────────────
    // Limit defensivo 5000 (mismo cap que otros queries de EMPLEADOS
    // en este archivo). Si lo cruzamos algun dia, ojo: la app no esta
    // hecha para mas de unos cientos de empleados.
    const empSnap = await db.collection("EMPLEADOS").limit(5000).get();
    const nombrePorDni = new Map<string, string>();
    for (const d of empSnap.docs) {
      const data = d.data();
      const dni = (data.DNI ?? d.id).toString();
      const nombre = (data.NOMBRE ?? "").toString().trim();
      if (nombre) nombrePorDni.set(dni, nombre);
    }

    // ─── 3. Cargar eventos peligrosos del rango ───────────────────
    // Limit defensivo 200000: lectura semanal de SITRACK_EVENTOS (~7×
    // limit diario). Si crece, ICM semanal puede quedar parcial pero
    // no rompe — el warn alerta a investigar volumen.
    const LIMIT_SITRACK_SEMANA = 200000;
    const evSnap = await db
      .collection("SITRACK_EVENTOS")
      .where("report_date", ">=", Timestamp.fromMillis(lunesAnteriorMs))
      .where("report_date", "<", Timestamp.fromMillis(lunesActualMs))
      .limit(LIMIT_SITRACK_SEMANA)
      .get();
    if (evSnap.size >= LIMIT_SITRACK_SEMANA) {
      logger.warn(
        "[recomputeIcmSemanalScheduled] SITRACK_EVENTOS query " +
        `alcanzó el limit (${LIMIT_SITRACK_SEMANA}). ICM semanal ` +
        "puede estar incompleto. Investigar volumen.",
      );
    }

    // Tracking del odómetro Sitrack por patente para cada chofer.
    // km en rango = max - min para cada patente, sumado.
    interface OdometroTracking {
      min: number;
      max: number;
    }
    interface AggChofer {
      dni: string;
      nombre: string;
      totalEventos: number;
      eventosPorTipo: Record<string, number>;
      odometroPorPatente: Map<string, OdometroTracking>;
    }
    const porChofer = new Map<string, AggChofer>();
    for (const d of evSnap.docs) {
      const data = d.data();
      const eventId = data.event_id;
      const dni = (data.driver_dni ?? "").toString().trim();
      if (!dni) continue;
      const patente = (data.asset_id ?? "").toString().trim().toUpperCase();
      const odometer = typeof data.odometer === "number" ? data.odometer : null;

      let agg = porChofer.get(dni);
      if (!agg) {
        agg = {
          dni,
          nombre: nombrePorDni.get(dni) ?? `DNI ${dni}`,
          totalEventos: 0,
          eventosPorTipo: {} as Record<string, number>,
          odometroPorPatente: new Map<string, OdometroTracking>(),
        };
        porChofer.set(dni, agg);
      }

      // Acumular odómetros — incluye TODOS los eventos (no solo
      // infracciones) para maximizar la ventana de km medible.
      if (patente && odometer !== null && odometer > 0) {
        let t = agg.odometroPorPatente.get(patente);
        if (!t) {
          t = { min: odometer, max: odometer };
          agg.odometroPorPatente.set(patente, t);
        } else {
          if (odometer < t.min) t.min = odometer;
          if (odometer > t.max) t.max = odometer;
        }
      }

      // Infracciones solo cuentan si el evento está en la lista YPF.
      if (typeof eventId !== "number" ||
          !TIPOS_PELIGROSOS_SITRACK.has(eventId)) continue;
      const nombreEv = (data.event_name ?? `Evento ${eventId}`).toString();
      agg.totalEventos++;
      agg.eventosPorTipo[nombreEv] =
        (agg.eventosPorTipo[nombreEv] ?? 0) + 1;
    }

    // ─── 4. Calcular ICM por chofer (misma fórmula que cliente) ───
    // Km reales del chofer en la semana = suma(max - min) del odómetro
    // Sitrack en eventos del chofer por cada patente que manejó.
    // Refactor 2026-05-16: antes era `totalEventos × 100` que daba
    // ratio = 1 → ICM = 95 para CUALQUIER chofer con eventos. Auditoria
    // detecto que el reporte semanal a Molina tenia todos los choferes
    // empatados en 95, sin valor de ranking.
    // FACTOR=5 → 4 ev/100km = ICM 80, 8 ev/100km = ICM 60.
    interface ChoferAgg {
      dni: string;
      nombre: string;
      icm: number;
      total_eventos: number;
      ratio_100km: number;
      categoria: string;
      eventos_por_tipo: Record<string, number>;
    }
    const FACTOR = 5;
    const KM_MIN = 50; // mismo umbral que cliente para evitar ICM ruidoso
    const choferes: ChoferAgg[] = [];
    for (const a of porChofer.values()) {
      // Sumar km reales por patente. Cap 10000 km/patente/semana
      // defensivo contra reset de odometro Sitrack. Cap subido de 5000
      // a 10000 en auditoria 2026-05-18 — choferes de larga distancia
      // (BB→Mendoza, BB→Misiones) hacen 5500-7000 km/semana legitimo
      // y quedaban como SIN_DATOS. 10000 sigue siendo > 2x la semana
      // mas grande realista.
      let kmReales = 0;
      let capsAplicados = 0;
      for (const [patente, t] of a.odometroPorPatente.entries()) {
        if (t.max > t.min) {
          const delta = t.max - t.min;
          if (delta <= 10000) {
            kmReales += delta;
          } else {
            capsAplicados++;
            // Log diagnostico (auditoria 2026-05-18): sin esto, un chofer
            // SIN_DATOS por cap silencioso es indistinguible de "no manejo
            // esa semana" en el ranking ICM.
            logger.warn(
              "[recomputeIcmSemanal] cap aplicado por probable reset",
              {
                dniHash: hashId(a.dni),
                patente,
                deltaKm: Math.round(delta),
                minKm: Math.round(t.min),
                maxKm: Math.round(t.max),
              },
            );
          }
        }
      }
      if (capsAplicados > 0 && kmReales === 0) {
        logger.warn(
          "[recomputeIcmSemanal] chofer queda SIN_DATOS por todos los caps",
          { dniHash: hashId(a.dni), capsAplicados },
        );
      }
      const km = kmReales >= KM_MIN ? kmReales : 0;
      const ratio = km > 0 ? a.totalEventos / (km / 100) : 0;
      const icmRaw = km > 0 ? 100 - ratio * FACTOR : 0;
      const icm = Math.max(0, Math.min(100, icmRaw));
      const categoria = km <= 0 ?
        "SIN_DATOS" :
        (icm >= 80 ? "BAJO" : (icm >= 60 ? "MEDIO" : "ALTO"));
      choferes.push({
        dni: a.dni,
        nombre: a.nombre,
        icm: Number(icm.toFixed(2)),
        total_eventos: a.totalEventos,
        ratio_100km: Number(ratio.toFixed(2)),
        categoria,
        eventos_por_tipo: a.eventosPorTipo,
      });
    }

    // ─── 5. Agregados flota ───────────────────────────────────────
    // CRITICO (auditoria 2026-05-17): excluir choferes SIN_DATOS de
    // promedio y top5. Antes los SIN_DATOS (icm=0 por km insuficientes)
    // pisaban el promedio (KPI Vista Ejecutiva mostraba 60 cuando real
    // era 90) y aparecian en top5 peores (ranking sin valor para Molina).
    const choferesConDatos = choferes.filter((c) => c.categoria !== "SIN_DATOS");
    const totalEventos = choferes.reduce((acc, c) => acc + c.total_eventos, 0);
    const sumIcm = choferesConDatos.reduce((acc, c) => acc + c.icm, 0);
    const icmPromedio = choferesConDatos.length > 0 ?
      Number((sumIcm / choferesConDatos.length).toFixed(2)) :
      0;
    const verdes = choferesConDatos.filter((c) => c.categoria === "BAJO").length;
    const amarillos = choferesConDatos.filter((c) => c.categoria === "MEDIO").length;
    const rojos = choferesConDatos.filter((c) => c.categoria === "ALTO").length;
    const sinDatos = choferes.filter((c) => c.categoria === "SIN_DATOS").length;

    // Sort para top mejores/peores — solo entre los que tienen datos.
    const sortedAsc = [...choferesConDatos].sort((a, b) => a.icm - b.icm);
    const top5Peores = sortedAsc.slice(0, 5).map((c) => ({
      dni: c.dni, nombre: c.nombre, icm: c.icm,
    }));
    const top5Mejores = sortedAsc.slice(-5).reverse().map((c) => ({
      dni: c.dni, nombre: c.nombre, icm: c.icm,
    }));

    // ─── 6. Persistir en ICM_SEMANAL/{YYYY-WW} ────────────────────
    await db.collection("ICM_SEMANAL").doc(semanaId).set({
      semana_id: semanaId,
      semana_inicio_ts: Timestamp.fromMillis(lunesAnteriorMs),
      semana_fin_ts: Timestamp.fromMillis(lunesActualMs),
      semana_label: semanaLabel,
      icm_promedio: icmPromedio,
      total_eventos: totalEventos,
      // `choferes_activos` = solo con datos, para que coincida con el
      // denominador del promedio. `choferes_sin_datos` separado para
      // que la UI lo muestre distinto (ej. "8 con poca actividad").
      choferes_activos: choferesConDatos.length,
      choferes_sin_datos: sinDatos,
      choferes_verdes: verdes,
      choferes_amarillos: amarillos,
      choferes_rojos: rojos,
      choferes,
      top_5_mejores: top5Mejores,
      top_5_peores: top5Peores,
      calculado_en: FieldValue.serverTimestamp(),
    });

    logger.info("[recomputeIcmSemanalScheduled] OK", {
      semanaId,
      icmPromedio,
      totalEventos,
      choferesConDatos: choferesConDatos.length,
      sinDatos,
      verdes, amarillos, rojos,
    });
  }
);

// Helper: ID semana ISO 8601 ("YYYY-WNN") de un Date.
// Fix auditoria 2026-05-16: antes mezclaba UTC y local (`d.getFullYear()`
// es local, `getUTCDay()`/`setUTCDate()` son UTC). En el borde de año
// (semana 1 de enero o 52/53 en diciembre) el calculo podia dar
// "2025-W01" cuando deberia ser "2026-W01" — los lectores client buscaban
// el docId esperado y no encontraban (off-by-one silencioso).
// Ahora usamos UTC consistente desde el primer paso.
function _isoWeekId(d: Date): string {
  // ISO 8601: la semana 1 es la que contiene el primer jueves del año.
  // UTC consistente: getUTCFullYear / Month / Date desde el input.
  const target = new Date(Date.UTC(
    d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()
  ));
  const dayNum = (target.getUTCDay() + 6) % 7; // lunes=0 ... domingo=6
  target.setUTCDate(target.getUTCDate() - dayNum + 3); // jueves de la semana
  const firstThursday = new Date(Date.UTC(target.getUTCFullYear(), 0, 4));
  const week = 1 + Math.round(
    ((target.getTime() - firstThursday.getTime()) / 86400000 -
      3 + ((firstThursday.getUTCDay() + 6) % 7)) / 7
  );
  const year = target.getUTCFullYear();
  return `${year}-W${week.toString().padStart(2, "0")}`;
}

// Helper: label legible de una semana ("12-18 May" o cross-mes "30 Abr - 6 May").
function _semanaLabel(inicio: Date, fin: Date): string {
  const meses = [
    "Ene", "Feb", "Mar", "Abr", "May", "Jun",
    "Jul", "Ago", "Sep", "Oct", "Nov", "Dic",
  ];
  const finDom = new Date(fin.getTime() - 24 * 60 * 60 * 1000);
  // Convertir a ART para extraer día/mes locales
  const inicioArt = new Date(inicio.getTime() - 3 * 60 * 60 * 1000);
  const finArt = new Date(finDom.getTime() - 3 * 60 * 60 * 1000);
  if (inicioArt.getUTCMonth() === finArt.getUTCMonth()) {
    return `${inicioArt.getUTCDate()}-${finArt.getUTCDate()} ` +
      meses[inicioArt.getUTCMonth()];
  }
  return `${inicioArt.getUTCDate()} ${meses[inicioArt.getUTCMonth()]} - ` +
    `${finArt.getUTCDate()} ${meses[finArt.getUTCMonth()]}`;
}
