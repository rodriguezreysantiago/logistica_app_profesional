// Idempotencia de los avisos automáticos.
//
// Antes de encolar un aviso, el cron consulta esta colección para no
// reenviar el mismo aviso en cada ciclo (cada hora). Cuando un papel
// se renueva (cambia la fecha de vencimiento), el id histórico cambia
// y los avisos del nuevo período se generan limpios.
//
// Estructura del id determinístico:
//   {coleccion}_{docId}_{campoBase}_{urgencia}_{fechaVenc}
// Ejemplo:
//   EMPLEADOS_12345678_LICENCIA_DE_CONDUCIR_7_2026-12-31

const admin = require('firebase-admin');
const log = require('./logger');

const COLECCION = 'AVISOS_AUTOMATICOS_HISTORICO';

/**
 * Niveles de urgencia que el cron puede generar. El número es el
 * umbral de días restantes — el aviso `urgente_7` se manda cuando
 * `dias <= 7 && dias > 1`, etc.
 *
 * Cada nivel `preventivo`, `recordatorio`, `urgente`, `hoy` se manda
 * UNA SOLA VEZ por (item, fecha de vencimiento). El nivel `vencido`
 * se manda **una vez por día** hasta que el papel se regularice (la
 * idempotencia del id incluye la fecha de hoy — ver `buildId`).
 *
 * Si la fecha de vencimiento cambia (papel renovado), el id es
 * distinto y los avisos se reanudan en el próximo período.
 */
const URGENCIAS = {
  preventivo: { codigo: 'preventivo', umbral: 30, minDias: 16, maxDias: 30 },
  recordatorio: { codigo: 'recordatorio', umbral: 15, minDias: 8, maxDias: 15 },
  urgente: { codigo: 'urgente', umbral: 7, minDias: 1, maxDias: 7 },
  hoy: { codigo: 'hoy', umbral: 0, minDias: 0, maxDias: 0 },
  // Vencido: el papel ya pasó el momento de renovarse. Mandamos un
  // recordatorio por día hasta que se regularice (cargue una nueva
  // fecha de vencimiento). El nivel se aplica para `dias < 0`.
  vencido: {
    codigo: 'vencido',
    umbral: -Infinity,
    minDias: -Infinity,
    maxDias: -1,
  },
};

/**
 * Devuelve la urgencia que corresponde a una cantidad de días, o
 * `null` si está demasiado lejano (>30 días).
 *
 * Si está vencido (`dias < 0`) devuelve el nivel `vencido`. Para que
 * el reminder no se mande mil veces por día, la idempotencia diaria
 * la maneja `buildId` agregando la fecha de hoy al id.
 */
function urgenciaPara(dias) {
  if (dias == null) return null;
  if (dias < 0) return URGENCIAS.vencido; // recordatorio diario
  if (dias > 30) return null; // demasiado lejano
  if (dias === 0) return URGENCIAS.hoy;
  if (dias <= 7) return URGENCIAS.urgente;
  if (dias <= 15) return URGENCIAS.recordatorio;
  if (dias <= 30) return URGENCIAS.preventivo;
  return null;
}

/**
 * Niveles de urgencia para el SERVICE preventivo de tractores. Métrica
 * en KILÓMETROS (no días) — espejo de `MantenimientoEstado` del cliente.
 *
 *   serviceDistance > 5000      → null (todavía lejos, no avisamos)
 *   serviceDistance ≤ 5000      → service_atencion
 *   serviceDistance ≤ 2500      → service_programar
 *   serviceDistance ≤ 1000      → service_urgente
 *   serviceDistance ≤ 0         → service_vencido
 */
const URGENCIAS_SERVICE = {
  service_atencion: { codigo: 'service_atencion', umbralKm: 5000 },
  service_programar: { codigo: 'service_programar', umbralKm: 2500 },
  service_urgente: { codigo: 'service_urgente', umbralKm: 1000 },
  service_vencido: { codigo: 'service_vencido', umbralKm: 0 },
};

/**
 * Devuelve la urgencia de service que corresponde a una distancia
 * restante en KM, o `null` si todavía falta mucho (>5000 km).
 */
function urgenciaServicePara(km) {
  if (km == null || isNaN(km)) return null;
  if (km <= 0) return URGENCIAS_SERVICE.service_vencido;
  if (km <= URGENCIAS_SERVICE.service_urgente.umbralKm) {
    return URGENCIAS_SERVICE.service_urgente;
  }
  if (km <= URGENCIAS_SERVICE.service_programar.umbralKm) {
    return URGENCIAS_SERVICE.service_programar;
  }
  if (km <= URGENCIAS_SERVICE.service_atencion.umbralKm) {
    return URGENCIAS_SERVICE.service_atencion;
  }
  return null;
}

/**
 * Construye el id determinístico para un aviso.
 *
 * Para los niveles "vencido" y "service_vencido" agregamos la fecha
 * de HOY al id, así el cron envía un recordatorio por día (el id es
 * distinto en cada corrida diaria). Cuando el admin actualiza la
 * fecha de vencimiento o el `ULTIMO_SERVICE_KM`, la parte base del
 * id cambia y el ciclo se reinicia limpio.
 *
 * Sanitiza caracteres no aptos para document IDs de Firestore (`/`).
 */
function buildId({ coleccion, docId, campoBase, urgencia, fechaVenc }) {
  let id = `${coleccion}_${docId}_${campoBase}_${urgencia}_${fechaVenc}`;
  if (urgencia === 'vencido' || urgencia === 'service_vencido') {
    id += `_${_fechaHoyIso()}`;
  }
  return id.replace(/\//g, '-').replace(/\s+/g, '');
}

/** YYYY-MM-DD de hoy, en hora local del bot. */
function _fechaHoyIso() {
  const d = new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

/**
 * `true` si el aviso ya se envió alguna vez (cualquier estado, incluso
 * ERROR — si quedó en error que el admin lo reintente desde la pantalla
 * "Cola de WhatsApp" en vez del cron).
 */
async function yaSeEnvio(db, params) {
  const id = buildId(params);
  const doc = await db.collection(COLECCION).doc(id).get();
  return doc.exists;
}

/**
 * Marca el aviso como ya enviado por el cron. Se guarda metadata para
 * auditoría: cuándo se generó, qué doc de COLA_WHATSAPP creó, etc.
 */
async function registrar(db, params, colaDocId) {
  const id = buildId(params);
  await db.collection(COLECCION).doc(id).set({
    coleccion: params.coleccion,
    doc_id: params.docId,
    campo_base: params.campoBase,
    urgencia: params.urgencia,
    fecha_vencimiento: params.fechaVenc,
    cola_doc_id: colaDocId,
    creado_en: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Helper para limpiar históricos de avisos cuyo papel ya se renovó.
 * No se llama hoy — pensado para una tarea de mantenimiento futura.
 * Se deja documentado para no perder la idea.
 */
async function limpiarObsoletos(db, dryRun = true) {
  // TODO: querer all docs, comparar fecha_vencimiento con la fecha
  // actual del papel en EMPLEADOS/VEHICULOS, borrar los que ya
  // pasaron al próximo período.
  log.info(`limpiarObsoletos no implementado todavía (dryRun=${dryRun})`);
}

module.exports = {
  COLECCION,
  URGENCIAS,
  URGENCIAS_SERVICE,
  urgenciaPara,
  urgenciaServicePara,
  buildId,
  yaSeEnvio,
  registrar,
  limpiarObsoletos,
};
