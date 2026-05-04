// Builder de mensajes de aviso de SERVICE preventivo (mantenimiento
// programado del tractor según km recorridos).
//
// Espejo conceptual de `aviso_builder.js` que arma los avisos por
// vencimientos de papeles. La diferencia clave: la métrica acá es KM
// restantes hasta el próximo service (no días hasta una fecha).
//
// Si modificás el copy, mantené coherencia con el tono "Te aviso desde
// la oficina..." que usa el bot para los demás avisos.

// Banner que se muestra al final del mensaje mientras la app esté en
// etapa de prueba. Quitar (junto con su uso en FIRMA) cuando se pase a
// producción real con todos los choferes/admins onboardeados.
const BANNER_TESTING =
  '⚠️ *Etapa de prueba* — si ves un error o algo no encaja, avisanos. ' +
  'No tomes el contenido al 100%.\n\n';

const FIRMA =
  BANNER_TESTING +
  '_Mensaje automático del sistema de gestión Coopertrans Móvil._\n' +
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
  // Bug A10 del code review: si patente o serviceDistanceKm vienen
  // inválidos (null/NaN/undefined), antes generábamos mensajes tipo
  // "el tractor null necesita SERVICE en NaN km". Ahora devolvemos
  // null y el caller decide (típicamente: no encolar el aviso).
  const cleanPatente = String(patente || '').trim();
  if (!cleanPatente) return null;
  if (
    serviceDistanceKm == null ||
    typeof serviceDistanceKm !== 'number' ||
    !Number.isFinite(serviceDistanceKm)
  ) {
    return null;
  }

  const nombreSeguro = destinatarioNombre
    ? String(destinatarioNombre).replace(/\s+/g, ' ').trim().slice(0, 40)
    : null;
  const saludo =
    nombreSeguro && nombreSeguro.length > 0
      ? `Hola ${nombreSeguro}`
      : 'Hola';

  // Identificador legible del tractor: "el VOLVO 460 (AB493CP)" si
  // tenemos marca+modelo, "el tractor AB493CP" como fallback.
  const ref = construirReferenciaUnidad({
    patente: cleanPatente,
    marca,
    modelo,
  });
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


// ============================================================================
// RESUMEN DIARIO CONSOLIDADO PARA EL ENCARGADO DE MANTENIMIENTO
// ============================================================================
//
// Una sola persona (definida por SERVICE_DESTINATARIO_DNI en .env) recibe
// UN mensaje por dia con el listado completo de tractores que requieren
// atencion. Si no hay ninguno, igual se le manda un "todo en orden" para
// que sepa que el cron corrio.

const ICONO_URGENCIA = {
  service_vencido: '🔴',
  service_urgente: '🟠',
  service_programar: '🟡',
  service_atencion: '🟢',
};

const ETIQUETA_URGENCIA = {
  service_vencido: 'VENCIDO',
  service_urgente: 'URGENTE',
  service_programar: 'PROGRAMAR',
  service_atencion: 'ATENCION',
};

// Orden de severidad (mas alta primero) para que el listado salga
// ordenado: vencidos arriba, despues urgentes, etc.
const ORDEN_SEVERIDAD = [
  'service_vencido',
  'service_urgente',
  'service_programar',
  'service_atencion',
];

/**
 * Construye el mensaje resumen diario para el encargado de mantenimiento.
 *
 * @param {object} args
 * @param {string|null} args.destinatarioNombre - Apodo o primer nombre.
 * @param {Array<{patente:string, urgencia:string, km:number, marca?:string, modelo?:string}>} args.tractores
 * @returns {string}
 */
function buildResumenDiario({ destinatarioNombre, tractores }) {
  const nombre = destinatarioNombre
    ? String(destinatarioNombre).replace(/\s+/g, ' ').trim().slice(0, 40)
    : null;
  const saludo = nombre ? `Hola ${nombre}` : 'Hola';

  // Caso 1: no hay tractores con urgencia. Mensaje "todo OK" para
  // confirmar al destinatario que el cron corrio (asi sabe que el
  // bot esta vivo y no se olvido de avisarle).
  if (!Array.isArray(tractores) || tractores.length === 0) {
    return (
      `${saludo}. Reporte diario de service preventivo: ` +
      `ningun tractor requiere atencion hoy. ✅

${FIRMA}`
    );
  }

  // Caso 2: hay tractores. Ordenamos por severidad descendente.
  const ordenados = [...tractores].sort((a, b) => {
    const ia = ORDEN_SEVERIDAD.indexOf(a.urgencia);
    const ib = ORDEN_SEVERIDAD.indexOf(b.urgencia);
    return ia - ib;
  });

  const lineas = ordenados.map((t) => {
    const icono = ICONO_URGENCIA[t.urgencia] || '⚪';
    const etiqueta = ETIQUETA_URGENCIA[t.urgencia] || t.urgencia;
    const ref = construirReferenciaUnidad({
      patente: t.patente,
      marca: t.marca,
      modelo: t.modelo,
    });
    // Mensaje km segun signo. Si km es negativo (vencido), lo
    // redactamos como "paso por X km", sino "faltan X km".
    const kmInt = Number.isFinite(t.km) ? Math.round(t.km) : 0;
    const km =
      kmInt < 0
        ? `paso por ${Math.abs(kmInt)} km`
        : `faltan ${kmInt} km`;
    return `${icono} ${etiqueta}: ${ref} (${km})`;
  });

  const cantidad = ordenados.length;
  const titulo =
    cantidad === 1
      ? '1 tractor requiere atencion:'
      : `${cantidad} tractores requieren atencion:`;

  return (
    `${saludo}. Reporte diario de service preventivo.

` +
    `${titulo}

` +
    `${lineas.join('\n')}

` +
    `${FIRMA}`
  );
}

module.exports = {
  build,
  buildResumenDiario,
  FIRMA,
};
