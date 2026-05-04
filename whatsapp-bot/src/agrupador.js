// Agrupador consumer-side de mensajes en COLA_WHATSAPP.
//
// Antes de mandar un doc PENDIENTE de tipo `volvo_alert_high` o
// `volvo_alert_mantenimiento`, busca otros pendientes para el MISMO
// destinatario con el MISMO origen y los combina en UN solo mensaje.
//
// Justificación (incidente 2026-05-03):
// - Cada alerta Volvo HIGH dispara `onAlertaVolvoCreated` que encola UN
//   doc por evento. Un chofer con un testigo del tablero parpadeando
//   genera 10-15 eventos en un día → 10-15 WhatsApps al chofer = spam +
//   riesgo de baneo del número.
// - Las alertas de mantenimiento (a Santiago) generaban hasta 7-8
//   mensajes en un día (uno por patente afectada). Ruido innecesario.
//
// El cron interno del bot ya tiene agrupación al ENCOLAR (ver cron.js
// → cron_aviso_agrupado). Este módulo es el equivalente al ENVIAR para
// los flujos que vienen de Cloud Functions y NO pasan por el cron.

const { aDdMmYyyyLocal, aLocalTime } = require('./fechas');

// Banner que se muestra al final del mensaje mientras la app esté en
// etapa de prueba. Quitar cuando se pase a producción real.
const BANNER_TESTING =
  '⚠️ *Etapa de prueba* — si ves un error o algo no encaja, avisanos. ' +
  'No tomes el contenido al 100%.\n\n';

/** Origenes que disparan agrupación al envío. */
const ORIGENES_AGRUPABLES = new Set([
  'volvo_alert_high',
  'volvo_alert_mantenimiento',
]);

/**
 * Etiquetas legibles de tipos de alerta Volvo. Espejo de `ETIQUETAS_TIPO`
 * en `aviso_alertas_volvo_builder.js` y `_etiquetaTipo` del cliente
 * Flutter. Si aparece un tipo nuevo, cae al código crudo.
 */
const ETIQUETAS_TIPO = {
  DISTANCE_ALERT: 'Cerca del vehículo de adelante',
  IDLING: 'Motor en ralentí',
  OVERSPEED: 'Exceso de velocidad',
  PTO: 'Toma de fuerza activada',
  HARSH: 'Aceleración / frenada brusca',
  GENERIC: 'Evento genérico',
  TELL_TALE: 'Luz de tablero encendida',
  FUEL: 'Cambio anormal de combustible',
  CATALYST: 'Cambio de nivel AdBlue',
  ALARM: 'Alarma anti-robo',
  ADBLUELEVEL_LOW: 'AdBlue bajo',
  WITHOUT_ADBLUE: 'Sin AdBlue',
};

/**
 * Toma un doc PENDIENTE recién leído por el polling y devuelve el plan
 * de envío:
 *   - Si el doc NO es de un origen agrupable → null (envío normal).
 *   - Si lo es: busca otros PENDIENTES del mismo destinatario+origen
 *     en últimas 48hs, los combina en un solo mensaje, y devuelve
 *     `{ mensajeCombinado, otrosDocsAgrupados }`.
 *
 * El caller envía `mensajeCombinado` y marca los `otrosDocsAgrupados`
 * como ENVIADO con `agrupado_en: <docIdActual>` (sin reenviar).
 *
 * El timestamp del evento real para cada item viene del campo
 * `alert_creado_en` que pone `onAlertaVolvoCreated` /
 * `onAlertaVolvoMantenimientoCreated`. Si por algún motivo no está
 * (docs viejos pre-fix), cae al `encolado_en`.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {FirebaseFirestore.QueryDocumentSnapshot} docActual
 * @returns {Promise<{ mensajeCombinado: string, otrosDocsAgrupados: FirebaseFirestore.QueryDocumentSnapshot[] } | null>}
 */
async function planificarEnvioAgrupado(db, docActual) {
  const data = docActual.data() ?? {};
  const origen = data.origen;
  if (!ORIGENES_AGRUPABLES.has(origen)) return null;

  const destinatarioId = data.destinatario_id;
  if (!destinatarioId) return null;

  // Ventana: últimas 48hs. Cubre el caso típico (eventos del finde que
  // se mandan el lunes) sin meter docs viejos olvidados.
  const ventanaMs = 48 * 60 * 60 * 1000;
  const cutoff = new admin.firestore.Timestamp(
    Math.floor((Date.now() - ventanaMs) / 1000),
    0
  );

  // Buscar otros PENDIENTE del mismo destinatario + origen.
  const snap = await db
    .collection('COLA_WHATSAPP')
    .where('destinatario_id', '==', destinatarioId)
    .where('origen', '==', origen)
    .where('estado', '==', 'PENDIENTE')
    .where('encolado_en', '>=', cutoff)
    .get();

  // Filtrar el actual (no agruparse a sí mismo) y los > 50 docs (cap
  // defensivo — si algún día hay un bug y se acumulan miles, no
  // pretendemos armar un mensaje de WhatsApp de 50000 chars).
  const otros = snap.docs
    .filter((d) => d.id !== docActual.id)
    .slice(0, 49);

  if (otros.length === 0) return null;

  // Todos los items (actual + otros) que vamos a combinar.
  const todos = [docActual, ...otros];

  // Armar el mensaje según el origen.
  const mensajeCombinado =
    origen === 'volvo_alert_high' ?
      _armarMensajeAlertHighAgrupado(todos) :
      _armarMensajeMantenimientoAgrupado(todos);

  return {
    mensajeCombinado,
    otrosDocsAgrupados: otros,
  };
}

/** "Hola X, se detectaron N eventos en tu(s) tractor(es): ...". */
function _armarMensajeAlertHighAgrupado(docs) {
  // Saludo: tomamos el del primer doc (todos van al mismo destinatario,
  // tienen el mismo saludo). Lo extraemos parseando el mensaje viejo —
  // no tenemos un campo `nombre_chofer` separado en el doc.
  const primerMensaje = docs[0].data().mensaje || '';
  const matchSaludo = primerMensaje.match(/^(Hola[^,]*),/);
  const saludo = matchSaludo ? matchSaludo[1] : 'Hola';

  // Items: agrupar por patente, mostrar lista cronológica de eventos.
  const porPatente = new Map();
  for (const doc of docs) {
    const d = doc.data();
    const patente = (d.alert_patente || '?').toString();
    const tipo = (d.alert_tipo || '').toString();
    const fecha = _fechaEventoDe(d);
    if (!porPatente.has(patente)) porPatente.set(patente, []);
    porPatente.get(patente).push({ tipo, fecha });
  }

  const bloques = [...porPatente.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([patente, eventos]) => {
      // Ordenar cronológicamente.
      eventos.sort((a, b) => a.fecha.getTime() - b.fecha.getTime());
      // Agrupar por tipo dentro de la patente: "2x Exceso (14:23 / 17:08)"
      const porTipo = new Map();
      for (const ev of eventos) {
        if (!porTipo.has(ev.tipo)) porTipo.set(ev.tipo, []);
        porTipo.get(ev.tipo).push(ev.fecha);
      }
      const lineas = [...porTipo.entries()].map(([tipo, fechas]) => {
        const etiqueta = ETIQUETAS_TIPO[tipo] || tipo;
        const horas = fechas.map((d) => aLocalTime(d)).join(' / ');
        const prefijo = fechas.length > 1 ? `${fechas.length}x ` : '';
        return `   • ${prefijo}${etiqueta} (${horas})`;
      });
      return `🚛 *${patente}*\n${lineas.join('\n')}`;
    });

  // Encabezado con cantidad + fecha del evento más viejo.
  const cantidad = docs.length;
  const fechaMin = _fechaEventoDe(
    docs.reduce((min, d) => {
      const f = _fechaEventoDe(d.data());
      return f < _fechaEventoDe(min.data()) ? d : min;
    }).data()
  );

  return (
    `${saludo},\n\n` +
    `Se detectaron ${cantidad} eventos de manejo desde el ${aDdMmYyyyLocal(fechaMin)}:\n\n` +
    `${bloques.join('\n\n')}\n\n` +
    'Te pedimos prestar atención a estos avisos. Si hubo una situación ' +
    'particular, avisanos a la oficina.\n\n' +
    BANNER_TESTING +
    '_Coopertrans Móvil — Mensaje automático._'
  );
}

/** "Hay alertas de mantenimiento en N tractores: ..." (al jefe de mant). */
function _armarMensajeMantenimientoAgrupado(docs) {
  // Para cada doc agrupar por patente.
  const porPatente = new Map();
  for (const doc of docs) {
    const d = doc.data();
    const patente = (d.alert_patente || '?').toString();
    const tipo = (d.alert_tipo || '').toString();
    const fecha = _fechaEventoDe(d);
    if (!porPatente.has(patente)) porPatente.set(patente, []);
    porPatente.get(patente).push({ tipo, fecha });
  }

  const bloques = [...porPatente.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([patente, eventos]) => {
      eventos.sort((a, b) => a.fecha.getTime() - b.fecha.getTime());
      const porTipo = new Map();
      for (const ev of eventos) {
        if (!porTipo.has(ev.tipo)) porTipo.set(ev.tipo, []);
        porTipo.get(ev.tipo).push(ev.fecha);
      }
      const lineas = [...porTipo.entries()].map(([tipo, fechas]) => {
        const etiqueta = ETIQUETAS_TIPO[tipo] || tipo;
        const horas = fechas.map((d) => aLocalTime(d)).join(' / ');
        const prefijo = fechas.length > 1 ? `${fechas.length}x ` : '';
        return `   • ${prefijo}${etiqueta} (${horas})`;
      });
      return `*${patente}*\n${lineas.join('\n')}`;
    });

  const cantidad = docs.length;
  const patentesUnicas = porPatente.size;

  return (
    '🔧 *Alertas de mantenimiento agrupadas*\n\n' +
    `${cantidad} alerta${cantidad !== 1 ? 's' : ''} ` +
    `en ${patentesUnicas} tractor${patentesUnicas !== 1 ? 'es' : ''}:\n\n` +
    `${bloques.join('\n\n')}\n\n` +
    '_Coopertrans Móvil — Aviso automático._'
  );
}

/** Devuelve un Date desde el campo `alert_creado_en` o cae al `encolado_en`. */
function _fechaEventoDe(data) {
  const ts = data.alert_creado_en || data.encolado_en;
  if (ts && typeof ts.toDate === 'function') return ts.toDate();
  if (ts instanceof Date) return ts;
  return new Date();
}

const admin = require('firebase-admin');

module.exports = {
  planificarEnvioAgrupado,
  // Exportados para tests
  ORIGENES_AGRUPABLES,
  ETIQUETAS_TIPO,
};
