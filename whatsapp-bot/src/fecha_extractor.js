// Port a Node.js de `lib/shared/utils/ocr_service.dart` (función
// `extraerFechaMasLejana`). Mantener el regex y los filtros
// sincronizados con el original — los tests Dart de
// `test/ocr_service_test.dart` cubren el comportamiento esperado.
//
// La heurística "fecha más lejana" se basa en que en un comprobante
// de renovación típicamente conviven la fecha de emisión (próxima al
// presente) y la de vencimiento (más futura). La de vencimiento es la
// que nos interesa.

/**
 * Extrae la fecha más lejana (en el futuro) que encuentre en `texto`.
 *
 * Reconoce formatos `DD/MM/YYYY`, `DD-MM-YYYY` y `DD.MM.YYYY` con día y
 * mes de 1 o 2 dígitos y año de 4 dígitos. Filtra años absurdos (fuera
 * de 2020-2050) y fechas inexistentes (31/02, 32/05, etc.).
 *
 * @param {string} texto
 * @returns {Date|null}
 */
function extraerFechaMasLejana(texto) {
  if (!texto) return null;

  // \b para evitar matchear fechas pegadas a otras palabras
  // (ej. "Texto15/12/2027más texto").
  const regex = /\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})\b/g;
  let mejor = null;
  let m;
  while ((m = regex.exec(texto)) !== null) {
    const dia = parseInt(m[1], 10);
    const mes = parseInt(m[2], 10);
    const anio = parseInt(m[3], 10);
    if (isNaN(dia) || isNaN(mes) || isNaN(anio)) continue;
    if (mes < 1 || mes > 12) continue;
    if (dia < 1 || dia > 31) continue;
    // Validamos construyendo y comparando los componentes (rechaza
    // 31/02 que JS convierte por rollover a 03/03).
    const fecha = new Date(anio, mes - 1, dia);
    if (
      fecha.getFullYear() !== anio ||
      fecha.getMonth() !== mes - 1 ||
      fecha.getDate() !== dia
    ) {
      continue;
    }
    if (anio < 2020 || anio > 2050) continue;
    if (mejor === null || fecha.getTime() > mejor.getTime()) {
      mejor = fecha;
    }
  }
  return mejor;
}

/**
 * Convierte una `Date` (o un ISO string) a `YYYY-MM-DD` para guardar
 * en Firestore con el formato que usa la app.
 */
function aIsoYMD(fecha) {
  if (!fecha) return null;
  const d = fecha instanceof Date ? fecha : new Date(fecha);
  if (isNaN(d.getTime())) return null;
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

module.exports = {
  extraerFechaMasLejana,
  aIsoYMD,
};
