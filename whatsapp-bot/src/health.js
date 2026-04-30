// Heartbeat del bot — mantiene un doc `BOT_HEALTH/main` en Firestore con
// el estado actual, para que la app Flutter pueda mostrar una pantalla
// "Estado del bot" sin necesidad de SSH al server.
//
// Cómo encaja con el resto del bot:
//   - `iniciar(db, fs, wa)`: arranca un setInterval que cada
//     HEARTBEAT_INTERVAL_SECONDS escribe el doc.
//   - `registrarEnvio()`: hook que index.js llama después de cada envío
//     OK. Bumpea el contador de "mensajes hoy" y refresca el ts.
//   - `registrarError(contexto, mensaje)`: agrega un error al ring buffer
//     (últimos 10) y refresca el ts.
//   - `registrarCicloCron(stats)`: hook que cron.js llama al cerrar un
//     ciclo. Guarda timestamp + stats.
//   - `setEstadoCliente(estado)`: hook que whatsapp.js llama cuando el
//     cliente WA cambia de estado (LISTO / DESCONECTADO / etc).
//
// La lógica de "el bot está caído" la hace la app del lado del cliente:
// si `ultimoHeartbeat` es de hace > 2 minutos, el bot no está respondiendo.
// Acá no escribimos un campo "vivo: true/false" porque sería mentira:
// si el bot crashea, no hay nadie que lo ponga en false.

const admin = require('firebase-admin');
const log = require('./logger');

// ─── Estado en memoria ─────────────────────────────────────────────
//
// Todo esto es efímero — si el bot reinicia, vuelve a 0 y se va
// rellenando a medida que pasan cosas. Lo que persiste entre reinicios
// es lo que ya escribimos al doc de Firestore.

const BUFFER_ERRORES_MAX = 10;
const VERSION = require('../package.json').version || 'desconocida';

let _db = null;
let _fs = null; // módulo firestore.js (para leer COLECCION/ESTADO)
let _wa = null; // módulo whatsapp.js (para leer estado del cliente)
let _timer = null;

const _state = {
  estadoCliente: 'INICIANDO',
  ultimoCicloCron: null, // Date | null
  ultimoCicloStats: null, // { encolados, salteados, errores } | null
  ultimoMensajeEnviado: null, // Date | null
  mensajesEnviadosHoy: 0,
  fechaContadorHoy: _hoyIso(), // YYYY-MM-DD en TZ del server
  erroresRecientes: [], // [{ en: Date, contexto, mensaje }]
};

function _hoyIso() {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${dd}`;
}

// ─── Hooks que llaman los otros módulos ────────────────────────────

/**
 * Cambia el estado del cliente WhatsApp. Estados posibles:
 *   - 'INICIANDO'        — proceso arrancando, todavía no hay cliente.
 *   - 'AUTH_PENDIENTE'   — esperando QR o login.
 *   - 'AUTENTICADO'      — pasó el auth pero todavía no llegó el ready.
 *   - 'LISTO'            — puede enviar mensajes.
 *   - 'DESCONECTADO'     — el cliente cayó (sesión expiró, internet, etc).
 *   - 'AUTH_FALLO'       — auth_failure del cliente, requiere reescaneo de QR.
 */
function setEstadoCliente(estado) {
  _state.estadoCliente = estado;
}

/**
 * Llamar después de cada envío exitoso.
 * Bumpea el contador del día y registra el timestamp.
 */
function registrarEnvio() {
  // Si cambió el día desde el último envío, reseteamos el contador.
  // Esto evita acumular el contador para siempre (ahora la app puede
  // mostrar "X mensajes enviados HOY" sin lógica extra).
  const hoy = _hoyIso();
  if (hoy !== _state.fechaContadorHoy) {
    _state.mensajesEnviadosHoy = 0;
    _state.fechaContadorHoy = hoy;
  }
  _state.mensajesEnviadosHoy++;
  _state.ultimoMensajeEnviado = new Date();
}

/**
 * Llamar cuando ocurre un error que conviene mostrar al admin.
 *
 * @param {string} contexto - corto: 'envio', 'cron', 'cliente_wa', 'firestore'.
 * @param {string} mensaje  - mensaje de error legible (sin stack trace).
 */
function registrarError(contexto, mensaje) {
  _state.erroresRecientes.unshift({
    en: new Date(),
    contexto: String(contexto || '').slice(0, 40),
    mensaje: String(mensaje || '').slice(0, 300),
  });
  // Mantener solo los últimos N — si el bot tiene un mal día con
  // muchos errores, no queremos que el doc crezca sin límite.
  if (_state.erroresRecientes.length > BUFFER_ERRORES_MAX) {
    _state.erroresRecientes.length = BUFFER_ERRORES_MAX;
  }
}

/**
 * Llamar al final de cada ciclo del cron.
 *
 * @param {{encolados: number, salteados: number, errores: number}} stats
 */
function registrarCicloCron(stats) {
  _state.ultimoCicloCron = new Date();
  _state.ultimoCicloStats = stats || null;
}

// ─── Loop de heartbeat ─────────────────────────────────────────────

/**
 * Arranca el heartbeat. Idempotente: una segunda llamada no duplica el timer.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {object} firestoreModule - el módulo `./firestore` (necesitamos
 *   acceso a COLECCION y ESTADO para contar la cola).
 * @param {object} whatsappModule  - el módulo `./whatsapp` (opcional;
 *   si está, intentamos leer estado actual del cliente como fallback).
 */
function iniciar(db, firestoreModule, whatsappModule) {
  if (_timer) return; // ya arrancado

  _db = db;
  _fs = firestoreModule;
  _wa = whatsappModule;

  const intervaloSeg = parseInt(
    process.env.HEARTBEAT_INTERVAL_SECONDS || '60',
    10
  );
  log.info(`Heartbeat cada ${intervaloSeg}s a BOT_HEALTH/main.`);

  // Primera escritura inmediata para que la app vea algo enseguida.
  escribirHeartbeat().catch((e) => {
    log.warn(`Heartbeat inicial falló: ${e.message}`);
  });

  _timer = setInterval(() => {
    escribirHeartbeat().catch((e) => {
      // Si Firestore está caído o hay un problema de red, no abortamos
      // el bot — el próximo intervalo lo intenta de nuevo. Solo
      // logueamos para que el operador vea el patrón si se vuelve crónico.
      log.warn(`Heartbeat falló: ${e.message}`);
    });
  }, intervaloSeg * 1000);
}

function detener() {
  if (_timer) {
    clearInterval(_timer);
    _timer = null;
  }
}

/**
 * Construye el documento y lo escribe en `BOT_HEALTH/main`.
 *
 * Decisión: usamos `set` con merge para que cada heartbeat sobreescriba
 * solo los campos que conoce. Si en algún futuro otro proceso escribe a
 * `BOT_HEALTH/main` (no debería, pero por las dudas), no lo pisamos
 * entero.
 */
async function escribirHeartbeat() {
  if (!_db || !_fs) {
    throw new Error('health.iniciar() no fue llamado');
  }

  // Contadores de cola — una query por estado. Son livianas porque
  // sólo hacemos count(), no traemos los docs. Si Firestore no soporta
  // count() en tu versión del SDK Admin, cae a get().size.
  const cola = await _contarCola();

  // Importamos acá para no crear ciclo de require en boot. `humano.js`
  // depende solo de variables de entorno.
  const { enHorarioHabil } = require('./humano');

  // Calculamos próximo ciclo del cron sumando el intervalo configurado
  // al último ciclo registrado. Si nunca corrió, dejamos null.
  const cronIntervaloMin = parseInt(
    process.env.CRON_INTERVAL_MINUTES || '60',
    10
  );
  const proximoCicloCron = _state.ultimoCicloCron
    ? new Date(_state.ultimoCicloCron.getTime() + cronIntervaloMin * 60 * 1000)
    : null;

  const doc = {
    ultimoHeartbeat: admin.firestore.FieldValue.serverTimestamp(),
    estadoCliente: _state.estadoCliente,

    cola,

    cron: {
      ultimoCiclo: _state.ultimoCicloCron
        ? admin.firestore.Timestamp.fromDate(_state.ultimoCicloCron)
        : null,
      proximoCicloAprox: proximoCicloCron
        ? admin.firestore.Timestamp.fromDate(proximoCicloCron)
        : null,
      ultimoCicloStats: _state.ultimoCicloStats,
      intervaloMinutos: cronIntervaloMin,
    },

    mensajes: {
      ultimoEnviado: _state.ultimoMensajeEnviado
        ? admin.firestore.Timestamp.fromDate(_state.ultimoMensajeEnviado)
        : null,
      enviadosHoy: _state.mensajesEnviadosHoy,
      fechaContadorHoy: _state.fechaContadorHoy,
    },

    erroresRecientes: _state.erroresRecientes.map((e) => ({
      en: admin.firestore.Timestamp.fromDate(e.en),
      contexto: e.contexto,
      mensaje: e.mensaje,
    })),

    config: {
      enHorarioHabil: enHorarioHabil(),
      autoAvisos:
        String(process.env.AUTO_AVISOS_ENABLED || 'false').toLowerCase() ===
        'true',
      autoRespuestas:
        String(
          process.env.AUTO_RESPUESTAS_ENABLED || 'false'
        ).toLowerCase() === 'true',
      workingHoursStart: parseInt(process.env.WORKING_HOURS_START || '8', 10),
      workingHoursEnd: parseInt(process.env.WORKING_HOURS_END || '20', 10),
      timezone:
        process.env.WORKING_TIMEZONE || 'America/Argentina/Buenos_Aires',
    },

    bot: {
      version: VERSION,
      pid: process.pid,
      nodeVersion: process.version,
      // process.uptime() devuelve segundos como float. Lo redondeamos
      // para que el doc no tenga ruido decimal.
      uptimeSegundos: Math.round(process.uptime()),
    },
  };

  await _db.collection('BOT_HEALTH').doc('main').set(doc, { merge: true });
}

/**
 * Cuenta los docs en COLA_WHATSAPP por estado. Devuelve un objeto con
 * `pendientes`, `procesando`, `error`, `reintentando`. Los `enviados`
 * no los contamos porque el contador crece sin límite y no aporta
 * información útil en tiempo real.
 *
 * `reintentando` es un subset de `pendientes`: docs que están
 * técnicamente en estado PENDIENTE pero con `proximoIntentoEn` en el
 * futuro (vinieron de un reintento fallido y todavía esperan el
 * próximo turno). La suma `pendientes + procesando + error` sigue
 * siendo el total de la cola activa (sin doble contar).
 *
 * Para PENDIENTE traemos los docs (no count) porque necesitamos
 * inspeccionar `proximoIntentoEn` campo a campo. La cola es chica
 * (decenas, no miles) así que el costo es despreciable. Para
 * PROCESANDO y ERROR usamos count() que es una sola lectura agregada.
 */
async function _contarCola() {
  const colRef = _db.collection(_fs.COLECCION);
  const out = { pendientes: 0, procesando: 0, error: 0, reintentando: 0 };

  // PENDIENTES + REINTENTANDO (mismo estado, distinguidos por proximoIntentoEn).
  try {
    const snap = await colRef.where('estado', '==', _fs.ESTADO.pendiente).get();
    out.pendientes = snap.size;
    const ahoraMs = Date.now();
    snap.forEach((d) => {
      const prox = d.data().proximoIntentoEn;
      if (!prox) return;
      const t = typeof prox.toMillis === 'function'
        ? prox.toMillis()
        : new Date(prox).getTime();
      if (!isNaN(t) && t > ahoraMs) out.reintentando++;
    });
  } catch (err) {
    // Si la query falla, dejamos los contadores en 0 — es preferible
    // mostrar 0 que tirar el heartbeat entero por una lectura.
  }

  // PROCESANDO y ERROR — count() agregado.
  for (const e of ['procesando', 'error']) {
    const valor = _fs.ESTADO[e];
    try {
      const snap = await colRef.where('estado', '==', valor).count().get();
      const n = snap.data().count;
      if (e === 'procesando') out.procesando = n;
      if (e === 'error') out.error = n;
    } catch (err) {
      const snap = await colRef.where('estado', '==', valor).get();
      const n = snap.size;
      if (e === 'procesando') out.procesando = n;
      if (e === 'error') out.error = n;
    }
  }

  return out;
}

module.exports = {
  iniciar,
  detener,
  setEstadoCliente,
  registrarEnvio,
  registrarError,
  registrarCicloCron,
  // Para tests / debugging:
  _state,
  escribirHeartbeat,
};
