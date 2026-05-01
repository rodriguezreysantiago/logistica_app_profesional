/**
 * Feriados nacionales obligatorios de Argentina.
 *
 * NO incluye puentes turisticos (los lunes / viernes "puente" que el
 * gobierno declara como dias no laborables) porque el cliente prefiere
 * que el bot trabaje normal en esos dias y solo respete los feriados
 * obligatorios.
 *
 * MANTENIMIENTO ANUAL: hay que actualizar la lista cada par de anios.
 * Los feriados moviles (Carnaval, Viernes Santo, Pascua, San Martin,
 * Diversidad Cultural, Soberania Nacional, Belgrano) cambian de fecha
 * exacta segun el calendario. Las fuentes oficiales son:
 *   - https://www.argentina.gob.ar/interior/feriados-nacionales
 *   - https://www.argentina.gob.ar/normativa/nacional/decreto
 *
 * Cuando se agreguen feriados de 2028, mantener el mismo formato
 * 'YYYY-MM-DD' y orden cronologico para que sea facil de leer.
 */

const FERIADOS = {
  // ─── 2026 ──────────────────────────────────────────────────────────
  '2026-01-01': 'Anio Nuevo',
  '2026-02-16': 'Carnaval (lunes)',
  '2026-02-17': 'Carnaval (martes)',
  '2026-03-24': 'Dia Nacional de la Memoria por la Verdad y la Justicia',
  '2026-04-02': 'Dia del Veterano y de los Caidos en la Guerra de Malvinas',
  '2026-04-03': 'Viernes Santo',
  '2026-05-01': 'Dia del Trabajador',
  '2026-05-25': 'Dia de la Revolucion de Mayo',
  '2026-06-15': 'Paso a la Inmortalidad del Gral. Guemes (trasladado)',
  '2026-07-09': 'Dia de la Independencia',
  '2026-08-17': 'Paso a la Inmortalidad del Gral. Jose de San Martin',
  '2026-10-12': 'Dia del Respeto a la Diversidad Cultural',
  '2026-11-20': 'Dia de la Soberania Nacional',
  '2026-12-08': 'Dia de la Inmaculada Concepcion de Maria',
  '2026-12-25': 'Navidad',

  // ─── 2027 ──────────────────────────────────────────────────────────
  '2027-01-01': 'Anio Nuevo',
  '2027-02-08': 'Carnaval (lunes)',
  '2027-02-09': 'Carnaval (martes)',
  '2027-03-24': 'Dia Nacional de la Memoria por la Verdad y la Justicia',
  '2027-03-26': 'Viernes Santo',
  '2027-04-02': 'Dia del Veterano y de los Caidos en la Guerra de Malvinas',
  '2027-05-01': 'Dia del Trabajador',
  '2027-05-25': 'Dia de la Revolucion de Mayo',
  '2027-06-21': 'Paso a la Inmortalidad del Gral. Belgrano (trasladado)',
  '2027-07-09': 'Dia de la Independencia',
  '2027-08-16': 'Paso a la Inmortalidad del Gral. Jose de San Martin (trasladado)',
  '2027-10-11': 'Dia del Respeto a la Diversidad Cultural (trasladado)',
  '2027-11-22': 'Dia de la Soberania Nacional (trasladado)',
  '2027-12-08': 'Dia de la Inmaculada Concepcion de Maria',
  '2027-12-25': 'Navidad',
};

/**
 * Devuelve YYYY-MM-DD de un Date usando componentes LOCALES.
 * Asume que el proceso esta en TZ ART (forzada por process.env.TZ
 * en index.js). Sin esto, en horarios nocturnos podriamos preguntar
 * por el dia equivocado.
 */
function _toIsoLocal(d) {
  const year = d.getFullYear();
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * @param {Date} date
 * @returns {boolean}
 */
function esFeriado(date) {
  if (!(date instanceof Date) || isNaN(date.getTime())) return false;
  return Object.prototype.hasOwnProperty.call(FERIADOS, _toIsoLocal(date));
}

/**
 * @param {Date} date
 * @returns {string|null} Nombre del feriado, o null si no es feriado.
 */
function descripcionFeriado(date) {
  if (!(date instanceof Date) || isNaN(date.getTime())) return null;
  return FERIADOS[_toIsoLocal(date)] || null;
}

module.exports = {
  esFeriado,
  descripcionFeriado,
  // Exportado para tests.
  FERIADOS,
};
