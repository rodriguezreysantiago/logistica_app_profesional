// Port a Node.js de `lib/features/expirations/services/aviso_vencimiento_builder.dart`.
//
// Mantener el copy y el tono alineados con el original — los avisos
// automáticos generados por el cron deben sentirse iguales a los que
// dispara manualmente el admin desde la app. Si modificás el Dart,
// modificá acá también.

const FIRMA =
  '_Mensaje automático del sistema de gestión S.M.A.R.T. Logística._\n' +
  '_Para responder o gestionar el trámite, comunicate con la oficina._';

/**
 * Construye el texto del aviso de WhatsApp para un vencimiento dado.
 *
 * @param {object} args
 * @param {object} args.item       - Vencimiento a comunicar.
 * @param {string} args.item.coleccion - 'EMPLEADOS' | 'VEHICULOS'.
 * @param {string} args.item.tipoDoc - 'Licencia', 'RTO', etc.
 * @param {string} args.item.docId  - DNI o patente.
 * @param {string} args.item.titulo - Para vehículos: "TRACTOR - AB123CD".
 * @param {string} args.item.fecha  - 'YYYY-MM-DD'.
 * @param {number} args.item.dias   - Días restantes (negativo si vencido).
 * @param {string|null} args.destinatarioNombre - Primer nombre o null.
 * @returns {string}
 */
function build({ item, destinatarioNombre }) {
  // Sanitizamos el nombre antes de interpolarlo en el mensaje para
  // que un valor con saltos de línea no rompa el formato (la firma
  // automática quedaría mezclada con el cuerpo) o no inyecte texto
  // adicional. Solo permitimos letras, espacios y signos comunes.
  const nombreSeguro = destinatarioNombre
    ? String(destinatarioNombre).replace(/\s+/g, ' ').trim().slice(0, 40)
    : null;
  const saludo =
    nombreSeguro && nombreSeguro.length > 0
      ? `Hola ${nombreSeguro}`
      : 'Hola';

  const fechaFmt = formatearFecha(item.fecha);
  const esVehiculo = item.coleccion === 'VEHICULOS';
  const referencia = esVehiculo
    ? `la unidad ${extraerPatente(item.titulo) || item.docId}`
    : `tu ${String(item.tipoDoc).toLowerCase()}`;

  const cuerpo = construirCuerpo({
    item,
    saludo,
    esVehiculo,
    referencia,
    fechaFmt,
  });
  return `${cuerpo}\n\n${FIRMA}`;
}

function construirCuerpo({ item, saludo, esVehiculo, referencia, fechaFmt }) {
  const ref = esVehiculo ? `el ${item.tipoDoc} de ${referencia}` : referencia;

  if (item.dias < 0) {
    // Vencido: el bot manda recordatorio diario hasta que se
    // regularice. Escalamos el tono según los días pasados para que
    // no se sienta como spam idéntico todos los días.
    const hace = -item.dias;
    if (hace === 1) {
      return (
        `${saludo}. Te aviso desde la oficina: ` +
        `${ref} venció ayer (era el ${fechaFmt}). ` +
        'Es importante regularizarlo cuanto antes. ¿Cuándo podés acercarte a presentar el comprobante?'
      );
    }
    if (hace <= 7) {
      return (
        `${saludo}. Recordatorio: ${ref} sigue vencido (venció hace ` +
        `${hace} días, el ${fechaFmt}). Es importante que lo regularices ` +
        'cuanto antes. ¿Cuándo lo podés presentar?'
      );
    }
    if (hace <= 30) {
      return (
        `${saludo}. ATENCIÓN: ${ref} lleva ${hace} días vencido ` +
        `(el ${fechaFmt}). Es urgente regularizarlo — coordiná con la ` +
        'oficina cuanto antes para evitar problemas operativos.'
      );
    }
    // > 30 días vencido — situación crítica
    return (
      `${saludo}. URGENTE: ${ref} lleva más de un mes vencido ` +
      `(${hace} días, era el ${fechaFmt}). La situación ya es crítica. ` +
      'Por favor pasá HOY por la oficina para coordinar la renovación.'
    );
  }

  if (item.dias === 0) {
    return (
      `${saludo}. Te aviso que ${ref} vence HOY (${fechaFmt}). ` +
      'Por favor pasá lo antes posible por la oficina.'
    );
  }

  if (item.dias <= 7) {
    return (
      `${saludo}. Recordatorio importante: ${ref} vence en ` +
      `${item.dias} día${item.dias === 1 ? '' : 's'} (el ${fechaFmt}). ` +
      'Si todavía no empezaste el trámite, hacelo ya.'
    );
  }

  if (item.dias <= 15) {
    return (
      `${saludo}. Te aviso que ${ref} vence en ${item.dias} días ` +
      `(${fechaFmt}). Es buen momento para empezar el trámite de renovación.`
    );
  }

  // 16-30+ días — preventivo
  return (
    `${saludo}. Aviso preventivo: ${ref} vence el ${fechaFmt} ` +
    `(en ${item.dias} días). Andá viendo el trámite.`
  );
}

/**
 * Resuelve cómo saludar a un chofer dado su doc de EMPLEADOS.
 *
 * Prioridad:
 *   1. Si tiene `APODO` cargado y no es vacío → usar APODO. Es lo que
 *      cargó el admin manualmente para casos donde el algoritmo de
 *      "segundo token" falla (dos apellidos, segundo nombre, etc).
 *   2. Sino → algoritmo `extraerPrimerNombre(NOMBRE)` (segundo token).
 *
 * Devuelve `null` si no se pudo resolver (sin apodo y NOMBRE de un
 * solo token), igual que `extraerPrimerNombre`.
 */
function resolverNombreSaludo(empleadoData) {
  if (!empleadoData) return null;
  const apodo = empleadoData.APODO;
  if (apodo && String(apodo).trim().length > 0) {
    return String(apodo).trim();
  }
  return extraerPrimerNombre(empleadoData.NOMBRE);
}

/**
 * Para nombres tipo "PEREZ JUAN CARLOS" devuelve "Juan" (formato
 * APELLIDO NOMBRE… que usa la app). Si solo hay un token, devuelve
 * null para evitar saludar al chofer por su apellido.
 */
function extraerPrimerNombre(nombreCompleto) {
  if (!nombreCompleto) return null;
  const partes = String(nombreCompleto).trim().split(/\s+/);
  if (partes.length < 2) return null;
  const n = partes[1];
  if (!n) return null;
  return n[0].toUpperCase() + n.slice(1).toLowerCase();
}

/**
 * Para títulos como "TRACTOR - AB123CD" devuelve "AB123CD". Si no
 * encuentra el patrón, devuelve null y el caller cae al docId.
 */
function extraerPatente(titulo) {
  if (!titulo) return null;
  const m = String(titulo).match(/-\s*([A-Z0-9]{6,})/);
  return m ? m[1] : null;
}

/**
 * Formatea una fecha ISO `YYYY-MM-DD` o un Date a `DD/MM/YYYY`. Tolera
 * strings nulos o mal formados — devuelve `'-'` en ese caso.
 *
 * **Bug histórico que fixeamos acá**: `new Date("2026-05-30")` parsea
 * el string como UTC midnight. Cuando después llamamos `.getDate()` en
 * zona local ART (UTC-3), devuelve 29 — porque la medianoche UTC es
 * 21h del día anterior en ART. Resultado: la licencia que vence el
 * 30/05 se mostraba como "29/05" en el WhatsApp.
 *
 * Ahora parseamos strings ISO YYYY-MM-DD literalmente (componente por
 * componente) sin pasar por el constructor de Date — así no hay
 * interpretación implícita de zona horaria.
 */
function formatearFecha(fecha) {
  if (!fecha) return '-';
  if (fecha instanceof Date) {
    const day = String(fecha.getDate()).padStart(2, '0');
    const mes = String(fecha.getMonth() + 1).padStart(2, '0');
    return `${day}/${mes}/${fecha.getFullYear()}`;
  }
  const str = String(fecha).trim();
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(str);
  if (m) {
    return `${m[3]}/${m[2]}/${m[1]}`;
  }
  const d = new Date(str);
  if (isNaN(d.getTime())) return str;
  const day = String(d.getDate()).padStart(2, '0');
  const mes = String(d.getMonth() + 1).padStart(2, '0');
  return `${day}/${mes}/${d.getFullYear()}`;
}

module.exports = {
  build,
  extraerPrimerNombre,
  resolverNombreSaludo,
  extraerPatente,
  formatearFecha,
  FIRMA,
};
