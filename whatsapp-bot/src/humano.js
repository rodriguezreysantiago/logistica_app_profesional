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
 * Devuelve `true` si la hora local actual está dentro del rango hábil
 * configurado en `.env` (`WORKING_HOURS_START` y `WORKING_HOURS_END`).
 *
 * Si los valores no están definidos, default 8-21 hs. Mensajes a las
 * 3 AM son la señal más obvia de bot.
 *
 * **IMPORTANTE — Zona horaria:** `now.getHours()` devuelve la hora en
 * la zona horaria LOCAL del proceso (PC donde corre el bot). El bot
 * se diseñó para correr en una PC en Bahía Blanca, Argentina (ART,
 * UTC-3). Si lo corrés en otra zona horaria (server cloud en UTC,
 * Linux en otra TZ, etc.), los avisos saldrán a horas raras desde
 * la perspectiva del chofer.
 *
 * Bug M9 del code review: si en el futuro se necesita correr en
 * otra zona, hay dos opciones:
 *   - Setear `TZ=America/Argentina/Buenos_Aires` en el entorno antes
 *     de arrancar Node.
 *   - Sumar variable BOT_TIMEZONE al .env y usar
 *     `Intl.DateTimeFormat({ timeZone: ... }).formatToParts(now)`
 *     para extraer la hora.
 */
function enHorarioHabil(now = new Date()) {
  const inicio = parseInt(process.env.WORKING_HOURS_START || '8', 10);
  const fin = parseInt(process.env.WORKING_HOURS_END || '21', 10);
  const hora = now.getHours();
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
