// Heurísticas para que el patrón de envío parezca humano.
//
// WhatsApp tiene detectores de bots que miran:
//   - Ráfagas de mensajes (10 mensajes en 30s).
//   - Mensajes 24x7 sin pausa nocturna.
//   - Mensajes idénticos a contactos distintos.
//   - Tiempo entre login y primer mensaje sospechosamente corto.
//
// No podemos eliminar la huella de bot, pero la podemos suavizar.

const { esFeriado, descripcionFeriado } = require('./feriados_ar');

/**
 * Devuelve `true` si el momento actual está dentro de la ventana hábil
 * configurada para enviar mensajes automáticos.
 *
 * Reglas (configurables vía .env):
 *   - **Lunes a viernes**: ventana `WORKING_HOURS_START` a
 *     `WORKING_HOURS_END` (default 8 a 20). Para mandar hasta las
 *     23:59 setear `WORKING_HOURS_END=24`.
 *   - **Sábado**: si `WORKING_HOURS_SAT_END > 0`, ventana
 *     `WORKING_HOURS_SAT_START` a `WORKING_HOURS_SAT_END`. Default
 *     ambos en 0 → sábado NO manda.
 *   - **Domingo**: nunca manda (señal de bot demasiado obvia).
 *   - **Feriados nacionales AR**: nunca manda (lista hardcodeada en
 *     `feriados_ar.js`). Aplica también si el feriado cae sábado.
 *   - **Zona horaria**: `WORKING_TIMEZONE`, default
 *     `America/Argentina/Buenos_Aires`.
 *
 * Usa `Intl.DateTimeFormat` con zona explícita en lugar de
 * `now.getHours()` — eso es CRÍTICO porque el servidor puede correr
 * en otra TZ (cloud, contenedor, PC con reloj cambiado, etc.). Sin
 * la TZ explícita, los avisos pueden salir a las 3 AM hora real.
 *
 * Configuración operativa Vecchi 2026-05-08:
 *   WORKING_HOURS_START=8
 *   WORKING_HOURS_END=24
 *   WORKING_HOURS_SAT_START=8
 *   WORKING_HOURS_SAT_END=12
 *   WORKING_TIMEZONE=America/Argentina/Buenos_Aires
 */
function enHorarioHabil(now = new Date()) {
  const inicio = parseInt(process.env.WORKING_HOURS_START || '8', 10);
  const fin = parseInt(process.env.WORKING_HOURS_END || '20', 10);
  const satInicio = parseInt(
    process.env.WORKING_HOURS_SAT_START || '0',
    10
  );
  const satFin = parseInt(process.env.WORKING_HOURS_SAT_END || '0', 10);
  const tz =
    process.env.WORKING_TIMEZONE || 'America/Argentina/Buenos_Aires';

  // Extraemos día de la semana y hora EN la zona horaria objetivo —
  // independiente del reloj del proceso. Intl.DateTimeFormat es la
  // forma estándar de hacer esto en Node desde v10+.
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    weekday: 'short', // 'Mon'..'Sun'
    hour: '2-digit',
    hour12: false,
  });
  const parts = fmt.formatToParts(now);
  const weekday = parts.find((p) => p.type === 'weekday')?.value || '';
  const horaStr = parts.find((p) => p.type === 'hour')?.value || '0';
  // Algunas implementaciones devuelven "24" para medianoche; lo
  // normalizamos a 0.
  let hora = parseInt(horaStr, 10);
  if (hora === 24) hora = 0;

  // Domingo: skip duro (no configurable — mandar domingo es señal
  // obvia de bot y dispara baneo de WhatsApp).
  if (weekday === 'Sun') return false;

  // Feriados nacionales obligatorios de Argentina: skip antes que
  // cualquier ventana horaria. Aplica también si el feriado cae
  // sábado. Lista hardcodeada en feriados_ar.js (mantener anualmente).
  if (esFeriado(now)) return false;

  // Sábado: ventana propia. Si WORKING_HOURS_SAT_END no está seteado
  // (o queda en 0 por compatibilidad con configs viejas), sábado NO
  // manda — preserva el comportamiento histórico del bot.
  if (weekday === 'Sat') {
    if (satFin <= 0) return false;
    return hora >= satInicio && hora < satFin;
  }

  // Lunes a viernes: ventana normal.
  return hora >= inicio && hora < fin;
}

/**
 * Devuelve la descripcion del feriado actual, o null si no es feriado.
 * Util para logs y para que el admin entienda por que el bot no
 * mando nada un dia particular.
 */
function feriadoHoy(now = new Date()) {
  return descripcionFeriado(now);
}

/**
 * Devuelve un delay aleatorio en milisegundos para esperar antes de
 * enviar el próximo mensaje. Default 15-60 segundos.
 *
 * El delay es uniforme dentro del rango — no exponencial — porque no
 * estamos modelando "tiempo entre mensajes humanos" sino "ritmo
 * razonable de operador con tareas concurrentes".
 */
function delayAleatorioMs() {
  const min = parseInt(process.env.DELAY_MIN_MS || '15000', 10);
  const max = parseInt(process.env.DELAY_MAX_MS || '60000', 10);
  return Math.floor(min + Math.random() * (max - min));
}

/**
 * `await sleep(ms)` para usar en async/await sin libs.
 */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Convierte un número de teléfono al formato que espera WhatsApp Web
 * (`<numero>@c.us`). Acepta entradas con `+`, espacios y guiones.
 * Devuelve `null` si el número no parece válido.
 *
 * Ejemplos:
 *   "+54 291 456-7890"  → "5492914567890@c.us"
 *   "5492914567890"     → "5492914567890@c.us"
 *   "abc"               → null
 */
function normalizarTelefonoAWid(telefono) {
  if (!telefono) return null;
  const digitos = String(telefono).replace(/\D+/g, '');
  if (digitos.length < 10 || digitos.length > 15) return null;
  return `${digitos}@c.us`;
}

module.exports = {
  enHorarioHabil,
  feriadoHoy,
  delayAleatorioMs,
  sleep,
  normalizarTelefonoAWid,
};
