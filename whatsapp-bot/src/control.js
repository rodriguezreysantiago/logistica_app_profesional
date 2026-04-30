// Lectura del flag de pausa del bot.
//
// La pantalla "Estado del Bot" del admin tiene un toggle Pausar/Reanudar
// que escribe a `BOT_CONTROL/main.pausado: true|false`. El bot consulta
// ese flag antes de procesar cada item de la cola — si está pausado,
// salta y deja el doc en PENDIENTE para reintentarlo cuando se reanude.
//
// Performance: cacheamos el valor en memoria con TTL corto (default 10s)
// para no leer Firestore en cada item de la cola. La latencia para que
// un cambio del admin se refleje es <= TTL + intervalo de polling.
//
// Diseño:
//   - Si el doc no existe → asumimos NO pausado (default seguro:
//     "el bot funciona si nadie lo pausó").
//   - Si la lectura falla (Firestore caído, timeout) → asumimos NO
//     pausado y logueamos warning. Mejor un envío de más durante un
//     outage que dejar la cola muerta.

const log = require('./logger');

let _db = null;
let _cache = { pausado: false, motivo: null, leidoEn: 0 };

function _ttlMs() {
  return parseInt(process.env.BOT_CONTROL_CACHE_TTL_MS || '10000', 10);
}

/**
 * Inicializar con la instancia de Firestore. Hay que llamarlo una vez
 * antes de usar `estaPausado()`.
 */
function inicializar(db) {
  _db = db;
}

/**
 * Devuelve true si el bot está pausado por el admin desde la app.
 * Cachea durante BOT_CONTROL_CACHE_TTL_MS para no martillar Firestore.
 */
async function estaPausado() {
  if (!_db) return false;
  const ahora = Date.now();
  if (ahora - _cache.leidoEn < _ttlMs()) {
    return _cache.pausado;
  }
  try {
    const snap = await _db.collection('BOT_CONTROL').doc('main').get();
    const data = snap.exists ? snap.data() || {} : {};
    const pausado = data.pausado === true;
    const motivo = data.motivo || null;
    // Logueamos solo cuando cambia el estado, no en cada lectura.
    if (pausado !== _cache.pausado) {
      if (pausado) {
        log.warn(
          `Bot PAUSADO por admin${motivo ? ` (motivo: "${motivo}")` : ''}.`
        );
      } else {
        log.info('Bot REANUDADO por admin.');
      }
    }
    _cache = { pausado, motivo, leidoEn: ahora };
    return pausado;
  } catch (e) {
    log.warn(`Lectura de BOT_CONTROL/main falló: ${e.message}`);
    // Default seguro: si no podemos leer, asumimos no pausado.
    return false;
  }
}

/**
 * Devuelve los datos crudos del último estado conocido (cacheado).
 * Útil para que el heartbeat los exponga al doc BOT_HEALTH/main sin
 * tener que duplicar otra lectura a Firestore.
 */
function ultimoEstado() {
  return { pausado: _cache.pausado, motivo: _cache.motivo };
}

module.exports = {
  inicializar,
  estaPausado,
  ultimoEstado,
};
