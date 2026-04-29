// Builder de mensajes de aviso de SERVICE preventivo (mantenimiento
// programado del tractor según km recorridos).
//
// Espejo conceptual de `aviso_builder.js` que arma los avisos por
// vencimientos de papeles. La diferencia clave: la métrica acá es KM
// restantes hasta el próximo service (no días hasta una fecha).
//
// Si modificás el copy, mantené coherencia con el tono "Te aviso desde
// la oficina..." que usa el bot para los demás avisos.

const FIRMA =
  '_Mensaje automático del sistema de gestión S.M.A.R.T. Logística._\n' +
  '_Para coordinar el ingreso al taller, comunicate con la oficina._';

/**
 * Construye el texto de WhatsApp para un aviso de service preventivo.
 *
 * @param {object} args
 * @param {string} args.patente               - Patente del tractor (ej. AB493CP).
 * @param {string} [args.marca]               - Marca (ej. VOLVO).
 * @param {string} [args.modelo]              - Modelo (ej. 460 4X2T).
 * @param {number} args.serviceDistanceKm     - KM restantes (negativo = vencido).
 * @param {string|null} args.destinatarioNombre - Primer nombre o null.
 * @returns {string}
 */
function build({
  patente,
  marca,
  modelo,
  serviceDistanceKm,
  destinatarioNombre,
}) {
  const nombreSeguro = destinatarioNombre
    ? String(destinatarioNombre).replace(/\s+/g, ' ').trim().slice(0, 40)
    : null;
  const saludo =
    nombreSeguro && nombreSeguro.length > 0
      ? `Hola ${nombreSeguro}`
      : 'Hola';

  // Identificador legible del tractor: "el VOLVO 460 (AB493CP)" si
  // tenemos marca+modelo, "el tractor AB493CP" como fallback.
  const ref = construirReferenciaUnidad({ patente, marca, modelo });
  const km = Math.round(serviceDistanceKm);

  const cuerpo = construirCuerpo({ saludo, ref, km });
  return `${cuerpo}\n\n${FIRMA}`;
}

function construirReferenciaUnidad({ patente, marca, modelo }) {
  const m = String(marca || '').trim();
  const mo = String(modelo || '').trim();
  const cleanPatente = String(patente || '').trim();
  if (m && mo) return `el ${m} ${mo} (${cleanPatente})`;
  if (m) return `el ${m} ${cleanPatente}`;
  return `el tractor ${cleanPatente}`;
}

/**
 * Texto del aviso según urgencia. Los umbrales son los mismos que la
 * pantalla "Service" del cliente Flutter:
 *   km > 5000          → no avisamos (no llamamos a esta función)
 *   km ≤ 5000          → atención (faltan ~5000 km)
 *   km ≤ 2500          → programar
 *   km ≤ 1000          → urgente
 *   km ≤ 0             → vencido
 */
function construirCuerpo({ saludo, ref, km }) {
  if (km <= 0) {
    // Service vencido: recordatorio diario hasta que se regularice.
    // Escalamos el tono según cuántos KM pasaron del momento previsto.
    const pasados = -km;
    if (pasados <= 500) {
      return (
        `${saludo}. Aviso desde la oficina: ${ref} acaba de pasar el ` +
        `momento del SERVICE (${pasados} km pasados). Hay que llevarlo ` +
        'al taller — ¿cuándo podés coordinar el ingreso?'
      );
    }
    if (pasados <= 2000) {
      return (
        `${saludo}. ATENCIÓN: ${ref} ya recorrió ${pasados} km con el ` +
        'SERVICE VENCIDO. Coordiná HOY con la oficina cuándo entrar al ' +
        'taller — cada día que pasa es más riesgo para la unidad.'
      );
    }
    // > 2000 km pasados — situación crítica
    return (
      `${saludo}. URGENTE: ${ref} lleva ${pasados} km con el SERVICE ` +
      'VENCIDO. La situación ya es crítica — pasá HOY por la oficina ' +
      'para coordinar el ingreso al taller cuanto antes.'
    );
  }
  if (km <= 1000) {
    return (
      `${saludo}. Aviso urgente: ${ref} necesita SERVICE en ${km} km. ` +
      'Coordiná lo antes posible con la oficina cuándo entrar al taller.'
    );
  }
  if (km <= 2500) {
    return (
      `${saludo}. Recordatorio: ${ref} necesita SERVICE en ${km} km. ` +
      'Es buen momento para coordinar el turno con el taller.'
    );
  }
  // km <= 5000: atención preventiva
  return (
    `${saludo}. Aviso preventivo: ${ref} va a necesitar SERVICE en ` +
    `aproximadamente ${km} km. Andá viendo cuándo coordinar el ingreso ` +
    'al taller.'
  );
}

module.exports = {
  build,
  FIRMA,
};
