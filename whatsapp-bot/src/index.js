// Entrypoint del bot. Orquesta:
//   1. Carga de .env
//   2. Inicialización de Firebase Admin
//   3. Conexión a WhatsApp Web (con persistencia de sesión)
//   4. Listener de COLA_WHATSAPP que procesa mensajes uno por uno
//      respetando horario hábil y delay aleatorio.

require('dotenv').config();

const fsNode = require('fs');
const path = require('path');

const log = require('./logger');
const fs = require('./firestore');
const wa = require('./whatsapp');
const cron = require('./cron');
const health = require('./health');
const control = require('./control');
const messageHandler = require('./message_handler');
const {
  enHorarioHabil,
  delayAleatorioMs,
  sleep,
  normalizarTelefonoAWid,
} = require('./humano');

// Limpieza preventiva al arrancar — desbloquea Chromium si quedó
// medio muerto del proceso anterior.
//
// Bugs recurrentes de `whatsapp-web.js` cuando el proceso anterior no
// cerró limpio (Ctrl+C contestando "S" a la pregunta de PowerShell,
// crash, kill -9, etc.):
//
//   1. Cache corrupto en `.wwebjs_cache/` → arranque cuelga sin llegar
//      a "WhatsApp listo".
//   2. **SingletonLock / SingletonCookie / SingletonSocket** dentro de
//      `.wwebjs_auth/` → Chromium nuevo cree que hay otra instancia
//      viva y se queda esperando. ESTE es el más jodido porque NO se
//      ve en el log; el bot queda en "Sesión autenticada" eternamente.
//
// La sesión real (cookies, login persistido) está en otros archivos
// que NO empiezan con "Singleton". Borrar los Singleton* no requiere
// reescanear QR.
function limpiarLocksChromium() {
  const root = path.resolve(__dirname, '..');

  // (1) Cache: borrar la carpeta entera. Se reconstruye sola.
  const cacheDir = path.join(root, '.wwebjs_cache');
  if (fsNode.existsSync(cacheDir)) {
    try {
      fsNode.rmSync(cacheDir, { recursive: true, force: true });
      log.info('Cache de Chromium limpiado (.wwebjs_cache/).');
    } catch (e) {
      log.warn(`No pude limpiar .wwebjs_cache/: ${e.message}`);
    }
  }

  // (2) Singleton locks dentro de la sesión persistida.
  // wwebjs los guarda dentro de `.wwebjs_auth/` en una ubicación que
  // depende de la versión (`session/`, `session/Default/`, etc).
  // Búsqueda RECURSIVA para cubrir cualquier layout. Solo borramos
  // archivos que matchean "Singleton*" — la sesión real (Cookies,
  // Local State, Login Data) NO tiene ese prefijo y queda intacta.
  const authRoot = path.join(root, '.wwebjs_auth');
  let borrados = 0;
  if (fsNode.existsSync(authRoot)) {
    const stack = [authRoot];
    while (stack.length > 0) {
      const dir = stack.pop();
      let entries;
      try {
        entries = fsNode.readdirSync(dir, { withFileTypes: true });
      } catch (_) {
        continue;
      }
      for (const ent of entries) {
        const full = path.join(dir, ent.name);
        if (ent.isDirectory()) {
          stack.push(full);
        } else if (ent.name.startsWith('Singleton')) {
          try {
            fsNode.rmSync(full, { force: true });
            borrados++;
          } catch (e) {
            log.warn(`No pude borrar ${full}: ${e.message}`);
          }
        }
      }
    }
  }
  if (borrados > 0) {
    log.info(`Locks de Chromium previos limpiados (${borrados} archivos Singleton*).`);
  } else {
    log.info('No había locks Singleton* previos (sesión limpia).');
  }
}

// Cola en memoria con los doc IDs pendientes en orden FIFO.
const colaProcesar = [];
let procesando = false;

function encolar(doc) {
  if (colaProcesar.includes(doc.id)) return;
  colaProcesar.push(doc.id);
  log.info(`+ Encolado ${doc.id} (total en cola: ${colaProcesar.length})`);
  if (!procesando) procesarSiguiente();
}

// ─── Reintentos automáticos con backoff ──────────────────────────────
const _PATRONES_TRANSITORIOS = [
  /timeout/i,
  /timed out/i,
  /network/i,
  /econn(reset|refused|aborted)/i,
  /etimedout/i,
  /socket hang up/i,
  /cliente no inicializado/i,
  /session closed/i,
  /protocol error/i,
  /target closed/i,
  /execution context was destroyed/i,
  /evaluate failed/i,
];

function _esErrorTransitorio(error) {
  const msg = (error && error.message) || String(error || '');
  return _PATRONES_TRANSITORIOS.some((re) => re.test(msg));
}

function _backoffSegundos(intento) {
  const raw = process.env.RETRY_BACKOFF_SEC || '30,120,600';
  const arr = raw
    .split(',')
    .map((s) => parseInt(s.trim(), 10))
    .filter((n) => !isNaN(n) && n > 0);
  if (arr.length === 0) return 60;
  const idx = Math.min(Math.max(intento - 1, 0), arr.length - 1);
  return arr[idx];
}

async function _despacharFalloEnvio(docRef, error) {
  const maxRetries = parseInt(process.env.MAX_RETRIES || '3', 10);
  const transitorio = _esErrorTransitorio(error);
  const snap = await docRef.get();
  const intentos = (snap.exists && snap.data().intentos) || 0;

  if (transitorio && intentos < maxRetries) {
    const backoffSeg = _backoffSegundos(intentos);
    const cuando = new Date(Date.now() + backoffSeg * 1000);
    await fs.marcarReintento(docRef, error.message, cuando);
    log.info(
      `↻ Reintento ${intentos}/${maxRetries} de ${docRef.id} en ${backoffSeg}s ` +
        `(${cuando.toISOString()})`
    );
    return;
  }

  const motivo = transitorio
    ? `agotados ${maxRetries} reintentos`
    : 'error no transitorio';
  await fs.marcarError(docRef, `${error.message} (${motivo})`);
  log.warn(`✗ ${docRef.id}: ERROR definitivo (${motivo}).`);
}

async function procesarSiguiente() {
  if (procesando) return;
  if (colaProcesar.length === 0) return;
  procesando = true;

  const docId = colaProcesar.shift();
  const db = fs.inicializar();
  const docRef = db.collection(fs.COLECCION).doc(docId);

  try {
    const snap = await docRef.get();
    if (!snap.exists) {
      log.warn(`${docId} ya no existe; salto.`);
      return;
    }
    const data = snap.data();
    if (data.estado !== fs.ESTADO.pendiente) {
      log.debug(`${docId} ya no está PENDIENTE (es ${data.estado}); salto.`);
      return;
    }

    if (!enHorarioHabil()) {
      log.info(`Fuera de horario hábil. ${docId} queda PENDIENTE para que el polling lo reintente.`);
      return;
    }

    // ─── Validación: kill-switch del admin ───
    // El admin puede pausar el bot desde la app (BOT_CONTROL/main.pausado).
    // Si está pausado, dejamos el doc en PENDIENTE — el polling lo va a
    // re-detectar cuando se reanude. Importante: no marcamos ERROR para
    // no inflar el contador de errores con algo que no es realmente fallo.
    if (await control.estaPausado()) {
      log.info(`Bot pausado por admin. ${docId} queda PENDIENTE.`);
      return;
    }

    const wid = normalizarTelefonoAWid(data.telefono);
    if (!wid) {
      log.warn(`${docId} con teléfono inválido: ${data.telefono}`);
      await fs.marcarError(
        docRef,
        `Teléfono inválido: "${data.telefono}". Esperado E.164 (+5492914567890).`
      );
      return;
    }

    let existe;
    try {
      existe = await wa.tieneWhatsApp(wid);
    } catch (e) {
      log.warn(`Verificación de ${wid} falló (transient): ${e.message}`);
      await docRef.update({ estado: fs.ESTADO.pendiente });
      return;
    }
    if (!existe) {
      log.warn(`${docId}: ${wid} no tiene WhatsApp.`);
      await fs.marcarError(docRef, 'El número no tiene WhatsApp registrado.');
      return;
    }

    await fs.marcarProcesando(docRef);
    const delay = delayAleatorioMs();
    log.info(`→ Enviando ${docId} a ${data.telefono} en ${Math.round(delay / 1000)}s...`);
    await sleep(delay);

    const waMessageId = await wa.enviarMensaje(wid, data.mensaje);
    await fs.marcarEnviado(docRef, { waMessageId });
    health.registrarEnvio();
    log.info(`✓ Enviado ${docId} (wa_id: ${waMessageId || '?'})`);
  } catch (e) {
    log.error(`✗ Falló ${docId}: ${e.message}`);
    health.registrarError('envio', `${docId}: ${e.message}`);
    try {
      await _despacharFalloEnvio(docRef, e);
    } catch (e2) {
      log.error(`No se pudo despachar fallo de envío: ${e2.message}`);
    }
  } finally {
    procesando = false;
    if (colaProcesar.length > 0) {
      await sleep(500);
      procesarSiguiente();
    }
  }
}

// ─── Polling de COLA_WHATSAPP ───────────────────────────────────────
let _pollingTimer = null;

async function pollearCola(db) {
  try {
    const qs = await db
      .collection(fs.COLECCION)
      .where('estado', '==', fs.ESTADO.pendiente)
      .get();
    const ahora = Date.now();
    qs.forEach((doc) => {
      const data = doc.data();
      const prox = data.proximoIntentoEn;
      if (prox) {
        const t = typeof prox.toMillis === 'function'
          ? prox.toMillis()
          : new Date(prox).getTime();
        if (!isNaN(t) && t > ahora) return;
      }
      encolar(doc);
    });
  } catch (e) {
    log.warn(`Polling Firestore falló: ${e.message}`);
  }
}

function iniciarPolling(db) {
  if (_pollingTimer) return;
  const intervaloSeg = parseInt(process.env.POLLING_INTERVAL_SECONDS || '15', 10);
  log.info(`Polling de ${fs.COLECCION} cada ${intervaloSeg}s (modo robusto: sin streams gRPC).`);
  pollearCola(db);
  _pollingTimer = setInterval(() => pollearCola(db), intervaloSeg * 1000);
}

function detenerPolling() {
  if (_pollingTimer) {
    clearInterval(_pollingTimer);
    _pollingTimer = null;
  }
}

async function main() {
  log.info('Iniciando whatsapp-bot...');
  limpiarLocksChromium();

  const db = fs.inicializar();

  log.info('Conectando a WhatsApp Web — esto puede demorar 10-30s...');
  await wa.inicializar();

  iniciarPolling(db);

  // Inicializar lectura del kill-switch BOT_CONTROL/main.
  control.inicializar(db);

  health.iniciar(db, fs, wa);

  cron.start(fs);

  // Handler de mensajes entrantes — registrado SIEMPRE para que los
  // comandos admin (/estado, /pausar, etc) funcionen aunque
  // AUTO_RESPUESTAS_ENABLED esté en false. La lógica de Fase 3
  // (respuestas de choferes que se convierten en revisiones) es lo
  // que se gatea por el flag — no la captura del mensaje.
  const respuestasHabilitado =
    String(process.env.AUTO_RESPUESTAS_ENABLED || 'false').toLowerCase() === 'true';
  log.info(
    respuestasHabilitado
      ? 'Handler de mensajes entrantes: comandos admin + Fase 3.'
      : 'Handler de mensajes entrantes: solo comandos admin (Fase 3 deshabilitada).'
  );
  wa.onMensajeEntrante(messageHandler.crearHandler(fs, wa));

  const delayMaxMs = parseInt(process.env.DELAY_MAX_MS || '60000', 10);
  const graceMs = delayMaxMs + 10000;

  const shutdown = async (sig) => {
    log.info(`Recibido ${sig}, cerrando (grace ${Math.round(graceMs / 1000)}s)...`);
    detenerPolling();
    cron.stop();
    health.detener();

    const start = Date.now();
    while (procesando && Date.now() - start < graceMs) {
      await sleep(200);
    }
    if (procesando) {
      log.warn(
        'Grace period agotado con un envío en curso. ' +
        'El doc queda en PROCESANDO; revisalo manualmente al reiniciar.'
      );
    } else {
      log.info('Cola en pausa, sin envíos en curso.');
    }

    await wa.destroy();
    process.exit(0);
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main().catch((e) => {
  log.error(`Fatal: ${e.stack || e.message}`);
  process.exit(1);
});
