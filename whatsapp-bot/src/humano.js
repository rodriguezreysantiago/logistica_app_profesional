// Heurísticas para que el patrón de envío parezca humano.
//
// WhatsApp tiene detectores de bots que miran:
//   - Ráfagas de mensajes (10 mensajes en 30s).
//   - Mensajes 24x7 sin pausa nocturna.
//   - Mensajes idénticos a contactos distintos.
//   - Tiempo entre login y primer mensaje sospechosamente corto.
//
// No podemos eliminar la huella de bot, pero la podemos suavizar.

/**
 * Devuelve `true` si el momento actual está dentro de la ventana hábil
 * configurada para enviar mensajes automáticos.
 *
 * Reglas hardcodeadas (configurables vía .env):
 *   - **Días**: lunes a viernes (skip sábado y domingo).
 *   - **Horas**: 8 a 20 (`WORKING_HOURS_START` y `WORKING_HOURS_END`).
 *   - **Zona horaria**: `WORKING_TIMEZONE`, default
 *     `America/Argentina/Buenos_Aires`.
 *
 * Usa `Intl.DateTimeFormat` con zona explícita en lugar de
 * `now.getHours()` — eso es CRÍTICO porque el servidor puede correr
 * en otra TZ (cloud, contenedor, PC con reloj cambiado, etc.). Sin
 * la TZ explícita, los avisos pueden salir a las 3 AM hora real.
 *
 * Para cambiar el horario, editá `whatsapp-bot/.env`:
 *   WORKING_HOURS_START=8
 *   WORKING_HOURS_END=20
 *   WORKING_TIMEZONE=America/Argentina/Buenos_Aires
 *
 * Para incluir sábado/domingo (no recomendado, llama spam attention
 * en WhatsApp), hay que comentar el `if (esFinDeSemana)` adentro.
 */
function enHorarioHabil(now = new Date()) {
  const inicio = parseInt(process.env.WORKING_HOURS_START || '8', 10);
  const fin = parseInt(process.env.WORKING_HOURS_END || '20', 10);
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

  // Skip sábado y domingo.
  const esFinDeSemana = weekday === 'Sat' || weekday === 'Sun';
  if (esFinDeSemana) return false;

  return hora >= inicio && hora < fin;
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
  // Argentina suele tener 12 o 13 dígitos con el prefijo internacional
  // (54). Mínimo razonable 10. Máximo 15 (E.164).
  if (digitos.length < 10 || digitos.length > 15) return null;
  return `${digitos}@c.us`;
}

module.exports = {
  enHorarioHabil,
  delayAleatorioMs,
  sleep,
  normalizarTelefonoAWid,
};
