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
 * Cada nivel se manda UNA SOLA VEZ por (item, fecha de vencimiento).
 * Si la fecha de vencimiento cambia (papel renovado), el id es
 * distinto y los avisos se reanudan en el próximo período.
 */
const URGENCIAS = {
  preventivo: { codigo: 'preventivo', umbral: 30, minDias: 16, maxDias: 30 },
  recordatorio: { codigo: 'recordatorio', umbral: 15, minDias: 8, maxDias: 15 },
  urgente: { codigo: 'urgente', umbral: 7, minDias: 1, maxDias: 7 },
  hoy: { codigo: 'hoy', umbral: 0, minDias: 0, maxDias: 0 },
};

/**
 * Devuelve la urgencia que corresponde a una cantidad de días, o
 * `null` si está fuera de los rangos que avisamos automáticamente
 * (>30 días o ya vencido — para vencidos avisa el admin manualmente
 * o queda como Fase 3).
 */
function urgenciaPara(dias) {
  if (dias < 0) return null; // Vencido — fuera de scope de Fase 2.
  if (dias > 30) return null; // Demasiado lejano.
  if (dias === 0) return URGENCIAS.hoy;
  if (dias <= 7) return URGENCIAS.urgente;
  if (dias <= 15) return URGENCIAS.recordatorio;
  if (dias <= 30) return URGENCIAS.preventivo;
  return null;
}

/**
 * Construye el id determinístico para un aviso.
 *
 * Sanitiza caracteres no aptos para document IDs de Firestore (`/`).
 */
function buildId({ coleccion, docId, campoBase, urgencia, fechaVenc }) {
  return `${coleccion}_${docId}_${campoBase}_${urgencia}_${fechaVenc}`
    .replace(/\//g, '-')
    .replace(/\s+/g, '');
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
  urgenciaPara,
  buildId,
  yaSeEnvio,
  registrar,
  limpiarObsoletos,
};
