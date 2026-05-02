// Builder del resumen DIARIO de Alertas del Vehicle Alerts API de Volvo.
//
// Espejo conceptual de `aviso_service_builder.js → buildResumenDiario`,
// pero con la metrica "eventos HIGH severity de las ultimas 24h" en
// vez de "tractores con urgencia de service".
//
// Una sola persona (definida por ALERTAS_RESUMEN_DESTINATARIO_DNI en
// .env, normalmente el admin) recibe UN mensaje por dia con el listado
// completo de eventos criticos detectados. Si no hubo eventos en las
// 24h, NO se manda nada (a diferencia del resumen de service que avisa
// "todo OK" — para alertas de manejo el silencio significa "nada que
// reportar" y mandar un mensaje vacio seria ruido).

const FIRMA =
  '_Mensaje automático del sistema de gestión Coopertrans Móvil._\n' +
  '_Detalle completo en la app → Alertas._';

// Mapa de alertType (Vehicle Alerts API) a etiqueta legible en
// castellano. Espejo del que vive en el cliente Flutter
// (`admin_volvo_alertas_screen.dart → _etiquetaTipo`). Si aparece un
// tipo nuevo de Volvo, cae al codigo crudo.
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
  GEOFENCE: 'Entrada/salida de geocerca',
  SAFETY_ZONE: 'Zona de velocidad reducida',
  TPM: 'Presión de neumático',
  TTM: 'Temperatura de neumático',
  AEBS: 'Frenado automático de emergencia',
  ESP: 'Control de estabilidad',
  DAS: 'Alerta de cansancio',
  LKS: 'Asistente de carril',
  LCS: 'Asistente de cambio de carril',
  UNSAFE_LANE_CHANGE: 'Cambio de carril inseguro',
  TACHO_OUT_OF_SCOPE_MODE_CHANGE: 'Tacógrafo fuera de servicio',
  CARGO: 'Cambio en carga (puerta / temp)',
  ADBLUELEVEL_LOW: 'AdBlue bajo',
  WITHOUT_ADBLUE: 'Sin AdBlue',
  DRIVING_WITHOUT_BEING_LOGGED_IN: 'Conducción sin chofer identificado',
};

/**
 * Construye el mensaje resumen diario de alertas HIGH de Volvo.
 *
 * @param {object} args
 * @param {string|null} args.destinatarioNombre - Apodo o primer nombre.
 * @param {Array<{
 *   patente: string,
 *   tipo: string,
 *   choferNombre: string|null,
 *   fechaHora: Date,
 * }>} args.eventos - Eventos HIGH de las ultimas 24h.
 * @returns {string|null} Mensaje listo para encolar, o null si no hay
 *   eventos (caller decide no encolar).
 */
function buildResumenDiario({ destinatarioNombre, eventos }) {
  if (!Array.isArray(eventos) || eventos.length === 0) {
    return null;
  }

  const nombre = destinatarioNombre
    ? String(destinatarioNombre).replace(/\s+/g, ' ').trim().slice(0, 40)
    : null;
  const saludo = nombre ? `Hola ${nombre}` : 'Hola';

  // Agrupamos por patente para que cada unidad ocupe un bloque visual
  // y dentro listamos los eventos cronologicamente. Ordenamos las
  // patentes alfabeticamente para consistencia entre dias.
  const porPatente = new Map();
  for (const ev of eventos) {
    const key = String(ev.patente || '—').trim().toUpperCase();
    if (!porPatente.has(key)) porPatente.set(key, []);
    porPatente.get(key).push(ev);
  }
  const patentesOrd = [...porPatente.keys()].sort();

  const bloques = patentesOrd.map((patente) => {
    const eventosUnidad = porPatente.get(patente);
    const choferNombre = eventosUnidad
      .map((e) => e.choferNombre)
      .find((n) => n && String(n).trim().length > 0);
    const titulo = choferNombre
      ? `🚛 *${patente}* (${choferNombre})`
      : `🚛 *${patente}*`;

    // Eventos ordenados cronologicamente.
    const ordenados = [...eventosUnidad].sort(
      (a, b) => a.fechaHora.getTime() - b.fechaHora.getTime()
    );

    // Si hay varios eventos del mismo tipo, los condensamos:
    //   "2x Exceso de velocidad (14:23 / 17:08)"
    // Sino:
    //   "Exceso de velocidad (14:23)"
    const porTipo = new Map();
    for (const ev of ordenados) {
      if (!porTipo.has(ev.tipo)) porTipo.set(ev.tipo, []);
      porTipo.get(ev.tipo).push(ev);
    }

    const lineas = [...porTipo.entries()].map(([tipo, evs]) => {
      const etiqueta = ETIQUETAS_TIPO[tipo] || tipo;
      const horas = evs.map((e) => _formatHora(e.fechaHora)).join(' / ');
      const prefijo = evs.length > 1 ? `${evs.length}x ` : '';
      return `   • ${prefijo}${etiqueta} (${horas})`;
    });

    return `${titulo}\n${lineas.join('\n')}`;
  });

  const cantidad = eventos.length;
  const titulo =
    cantidad === 1
      ? '1 evento crítico en las últimas 24h:'
      : `${cantidad} eventos críticos en las últimas 24h:`;

  const fecha = _formatFecha(new Date());
  return (
    `${saludo}.\n\n` +
    `📊 Resumen diario — Alertas HIGH (${fecha})\n\n` +
    `${titulo}\n\n` +
    `${bloques.join('\n\n')}\n\n` +
    `${FIRMA}`
  );
}

/** "HH:MM" en TZ del proceso. */
function _formatHora(d) {
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  return `${hh}:${mm}`;
}

/** "DD/MM/AAAA" en TZ del proceso. */
function _formatFecha(d) {
  const dd = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const yyyy = d.getFullYear();
  return `${dd}/${mm}/${yyyy}`;
}

module.exports = {
  buildResumenDiario,
  ETIQUETAS_TIPO,
  FIRMA,
};
