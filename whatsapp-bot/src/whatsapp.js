// Wrapper sobre whatsapp-web.js. Encapsula:
//   - LocalAuth para que la sesión persista en .wwebjs_auth/
//   - QR rendering en consola al primer login
//   - Estado del cliente (autenticado / pronto para enviar)
//   - Verificación de número antes de enviar (evita "el chofer no tiene WhatsApp")
//   - Watchdog del evento READY (resuelve cuelgue del A/B testing)
//   - Modo dry-run (BOT_DRY_RUN=true): no envía mensajes reales

const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const log = require('./logger');
const health = require('./health');

let client = null;
let listo = false;
const callbacksAlEstarListo = [];

function inicializar() {
  if (client) return _esperarListo();

  client = new Client({
    authStrategy: new LocalAuth({}),
    // ─── webVersionCache remoto ───
    // Crítico para evitar el bug "autenticado pero nunca ready".
    // El cache remoto baja siempre una versión estable conocida del
    // repo de wppconnect (que monitorea cuál anda y cuál no).
    webVersionCache: {
      type: 'remote',
      remotePath:
        'https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/{version}.html',
      strict: false,
    },
    puppeteer: {
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
      ],
    },
  });

  client.on('qr', (qr) => {
    health.setEstadoCliente('AUTH_PENDIENTE');
    log.info('QR recibido — escaneá desde WhatsApp en el teléfono descartable.');
    log.info('Ajustes → Dispositivos vinculados → Vincular un dispositivo.');
    qrcode.generate(qr, { small: true });
  });

  client.on('authenticated', () => {
    health.setEstadoCliente('AUTENTICADO');
    log.info('Sesión de WhatsApp autenticada y persistida en .wwebjs_auth/');
    // Arranca el watchdog: si ready no llega en READY_TIMEOUT_SEC,
    // matamos el cliente y reintentamos. Resuelve el bug conocido
    // "autenticado pero never ready" del A/B testing de WhatsApp Web.
    _arrancarWatchdogReady();
  });

  client.on('auth_failure', (msg) => {
    health.setEstadoCliente('AUTH_FALLO');
    health.registrarError('cliente_wa', `Auth failure: ${msg}`);
    log.error(`Auth failure: ${msg}`);
  });

  client.on('ready', () => {
    listo = true;
    health.setEstadoCliente('LISTO');
    _intentosReconexion = 0;
    _intentosReadyTimeout = 0;
    _detenerWatchdogReady();
    log.info('WhatsApp listo para enviar.');
    callbacksAlEstarListo.splice(0).forEach((cb) => cb());
  });

  client.on('disconnected', (reason) => {
    listo = false;
    health.setEstadoCliente('DESCONECTADO');
    health.registrarError('cliente_wa', `Cliente desconectado: ${reason}`);
    log.warn(`Cliente desconectado: ${reason}.`);
    _intentarReconexion();
  });

  client.initialize();

  return _esperarListo();
}

function _esperarListo() {
  if (listo) return Promise.resolve();
  return new Promise((resolve) => callbacksAlEstarListo.push(resolve));
}

// ─── Reconexión con backoff exponencial ─────────────────────────────
let _reconexionEnCurso = false;
let _intentosReconexion = 0;
const _maxReconexiones = 5;

function _intentarReconexion() {
  if (_reconexionEnCurso) return;
  _reconexionEnCurso = true;

  if (_intentosReconexion >= _maxReconexiones) {
    log.error(
      `${_maxReconexiones} reintentos fallidos. Saliendo para que el supervisor reinicie limpio.`
    );
    process.exit(1);
  }

  _intentosReconexion++;
  const delayMs = Math.min(1000 * Math.pow(2, _intentosReconexion - 1), 16000);
  log.info(
    `Reintentando conexión (intento ${_intentosReconexion}/${_maxReconexiones}) en ${delayMs}ms...`
  );

  setTimeout(async () => {
    try {
      await client.initialize();
    } catch (e) {
      log.warn(`Reconexión falló: ${e.message}`);
    } finally {
      _reconexionEnCurso = false;
    }
  }, delayMs);
}

// ─── Watchdog de READY ─────────────────────────────────────────────
//
// Bug conocido: después del evento `authenticated`, a veces el `ready`
// nunca llega — el cliente queda colgado en pantalla de carga al 99%.
// Causado por A/B testing del lado de WhatsApp Web 2.3000.x.
//
// Mitigación: timeout configurable (default 90s). Si no llega `ready`,
// matamos el cliente Chromium y reintentamos `initialize()`. La sesión
// persistida en .wwebjs_auth/ NO se borra, así que no requiere
// reescanear el QR.
//
// Si el watchdog dispara MAX_READY_TIMEOUTS veces seguidas, exit con
// código 1 — en producción NSSM reinicia el proceso desde cero.

let _readyWatchdogTimer = null;
let _readyProgressTimer = null;
let _intentosReadyTimeout = 0;
const _maxReadyTimeouts = parseInt(
  process.env.MAX_READY_TIMEOUTS || '3',
  10
);

function _arrancarWatchdogReady() {
  _detenerWatchdogReady();
  const timeoutSeg = parseInt(process.env.READY_TIMEOUT_SEC || '90', 10);
  // Cantidad de tics progresivos que vamos a emitir (uno cada 30s).
  // Para timeoutSeg=90, son 3 tics: 1/3, 2/3, 3/3.
  const totalTics = Math.max(1, Math.floor(timeoutSeg / 30));
  let ticActual = 0;

  // Log periódico cada 30s para ver el progreso desde la consola.
  // El contador se resetea cada vez que se arranca el watchdog (cada
  // reinicio del cliente arranca uno nuevo), así que en cada intento
  // vas a ver 1/3, 2/3, 3/3 desde cero.
  _readyProgressTimer = setInterval(() => {
    ticActual++;
    log.info(`Esperando WhatsApp listo... ${ticActual}/${totalTics}`);
  }, 30000);

  _readyWatchdogTimer = setTimeout(async () => {
    _detenerWatchdogReady();
    _intentosReadyTimeout++;

    log.warn(
      `Watchdog: ready no llegó en ${timeoutSeg}s ` +
      `(intento ${_intentosReadyTimeout}/${_maxReadyTimeouts}).`
    );
    health.registrarError(
      'cliente_wa',
      `Ready timeout (${timeoutSeg}s) — bug del A/B testing de WhatsApp Web. Reintentando.`
    );

    if (_intentosReadyTimeout >= _maxReadyTimeouts) {
      log.error(
        `${_maxReadyTimeouts} timeouts seguidos. Saliendo para que el supervisor reinicie limpio.`
      );
      process.exit(1);
    }

    try {
      await client.destroy();
    } catch (e) {
      log.warn(`Error cerrando cliente para reintento: ${e.message}`);
    }
    health.setEstadoCliente('INICIANDO');
    log.info('Reinicializando cliente WhatsApp...');
    try {
      await client.initialize();
    } catch (e) {
      log.error(`Reinicialización falló: ${e.message}`);
    }
  }, timeoutSeg * 1000);
}

function _detenerWatchdogReady() {
  if (_readyWatchdogTimer) {
    clearTimeout(_readyWatchdogTimer);
    _readyWatchdogTimer = null;
  }
  if (_readyProgressTimer) {
    clearInterval(_readyProgressTimer);
    _readyProgressTimer = null;
  }
}

// ─── API pública ───────────────────────────────────────────────────

async function tieneWhatsApp(wid) {
  if (!client || !listo) throw new Error('Cliente no inicializado');
  const numberId = await client.getNumberId(wid.replace('@c.us', ''));
  return numberId !== null;
}

/**
 * Envía un mensaje de texto. Devuelve el id de WhatsApp del mensaje
 * recién enviado.
 *
 * **Modo dry-run**: si BOT_DRY_RUN=true, NO envía nada real. Loguea
 * el destino + texto y devuelve un id sintético `dryrun_*`. Útil para
 * validar cambios al cron / al builder sin spammear a los choferes.
 */
async function enviarMensaje(wid, texto) {
  const dryRun =
    String(process.env.BOT_DRY_RUN || 'false').toLowerCase() === 'true';
  if (dryRun) {
    log.info(
      `[DRY-RUN] enviarMensaje a ${wid} — ${texto.length} chars (no se envía).`
    );
    log.debug(`[DRY-RUN] Cuerpo: ${texto.slice(0, 200)}${texto.length > 200 ? '…' : ''}`);
    return `dryrun_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
  }
  if (!client || !listo) throw new Error('Cliente no inicializado');
  const sent = await client.sendMessage(wid, texto);
  try {
    return sent && sent.id && sent.id._serialized ? sent.id._serialized : null;
  } catch (_) {
    return null;
  }
}

function onMensajeEntrante(handler) {
  if (!client) throw new Error('Cliente no inicializado');
  // `message_create` dispara para TODOS los mensajes (entrantes y
  // salientes). Es más permisivo que `message`, que en algunas
  // versiones de wwebjs no dispara en conversaciones nuevas
  // (la primera vez que un número no-contacto escribe al bot).
  // El handler filtra `msg.fromMe` para descartar los nuestros.
  client.on('message_create', handler);
}

async function responder(msg, texto) {
  if (!client || !listo) throw new Error('Cliente no inicializado');
  await msg.reply(texto);
}

async function destroy() {
  if (client) {
    try {
      await client.destroy();
    } catch (e) {
      log.warn(`Error cerrando cliente: ${e.message}`);
    }
  }
}

module.exports = {
  inicializar,
  tieneWhatsApp,
  enviarMensaje,
  onMensajeEntrante,
  responder,
  destroy,
};
