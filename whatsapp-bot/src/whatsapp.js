// Wrapper sobre whatsapp-web.js. Encapsula:
//   - LocalAuth para que la sesión persista en .wwebjs_auth/
//   - QR rendering en consola al primer login
//   - Estado del cliente (autenticado / pronto para enviar)
//   - Verificación de número antes de enviar (evita "el chofer no tiene WhatsApp")

const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const log = require('./logger');
const health = require('./health');

let client = null;
let listo = false;
const callbacksAlEstarListo = [];

/**
 * Inicializa el cliente de WhatsApp Web. Devuelve una promesa que
 * resuelve cuando el cliente está autenticado y listo para enviar.
 *
 * En el primer arranque se imprime un QR en consola — el usuario
 * escanea con el teléfono descartable. La sesión se guarda en
 * `.wwebjs_auth/` (gitignored). En arranques siguientes no hay QR.
 */
function inicializar() {
  if (client) return _esperarListo();

  client = new Client({
    authStrategy: new LocalAuth({
      // dataPath default es .wwebjs_auth/ — lo dejamos así para
      // que el .gitignore que ya está cubra el caso.
    }),
    // ─── webVersionCache remoto ───
    // Crítico para evitar el bug "autenticado pero nunca ready".
    // Default `local` cachea la versión de WhatsApp Web que vio en el
    // primer login. WhatsApp del lado servidor cambió en enero 2026 y
    // lanza A/B testing que deja a algunas versiones rotas. El cache
    // remoto baja siempre una versión estable conocida del repo de
    // wppconnect (que monitorea cuál anda y cuál no).
    //
    // Si el remotePath estuviera caído (servidor de wppconnect down),
    // strict:false hace que caiga al default local — el bot no muere
    // por una razón de cache. Es el balance correcto: preferimos boot
    // funcional con versión vieja que crash por dependencia externa.
    webVersionCache: {
      type: 'remote',
      remotePath:
        'https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/{version}.html',
      strict: false,
    },
    puppeteer: {
      // headless: true es default en versions nuevas. Lo dejamos
      // implícito para que tome lo que la lib considere mejor.
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        // Reduce uso de memoria en VPS chicos.
        '--disable-dev-shm-usage',
      ],
    },
  });

  client.on('qr', (qr) => {
    health.setEstadoCliente('AUTH_PENDIENTE');
    log.info(
      'QR recibido — escaneá desde WhatsApp en el teléfono descartable.'
    );
    log.info('Ajustes → Dispositivos vinculados → Vincular un dispositivo.');
    qrcode.generate(qr, { small: true });
  });

  client.on('authenticated', () => {
    health.setEstadoCliente('AUTENTICADO');
    log.info('Sesión de WhatsApp autenticada y persistida en .wwebjs_auth/');
    // Arranca el watchdog: si ready no llega en READY_TIMEOUT_SEC,
    // matamos el cliente y reintentamos. Esto resuelve el bug
    // conocido "autenticado pero never ready" del A/B testing de
    // WhatsApp Web 2.3000.x.
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
    _intentosReadyTimeout = 0; // reset del watchdog también
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

/**
 * Reconexión con backoff exponencial. Cuando wwebjs se desconecta
 * (sesión expirada, internet caído, etc.) intenta reconectar 1s,
 * 2s, 4s, 8s, 16s. Si después de 5 intentos no se restablece,
 * salimos del proceso para que el supervisor (nssm / Task Scheduler)
 * lo reinicie limpio.
 *
 * Esto evita el escenario "100 reconexiones por segundo" si WhatsApp
 * cierra la sesión repetidamente.
 */
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
      // wwebjs reinicializa internamente con `client.initialize()`.
      // Si la sesión `.wwebjs_auth/` sigue válida, no requiere QR.
      await client.initialize();
      // Si llegó al `ready` event, el contador se resetea ahí.
    } catch (e) {
      log.warn(`Reconexión falló: ${e.message}`);
    } finally {
      _reconexionEnCurso = false;
      // Si en este intento no se completó el `ready`, el siguiente
      // `disconnected` event va a llamar de nuevo.
    }
  }, delayMs);
}

// ─── Watchdog de READY ─────────────────────────────────────────────
//
// Bug conocido (issue #5758, #127084 en wwebjs): después del evento
// `authenticated`, a veces el `ready` nunca llega — el cliente queda
// colgado en pantalla de carga al 99%. Causado por A/B testing del
// lado de WhatsApp Web 2.3000.x.
//
// Mitigación: timeout configurable (default 90s). Si no llega `ready`,
// matamos el cliente Chromium y reintentamos `initialize()`. La sesión
// persistida en .wwebjs_auth/ NO se borra, así que no requiere
// reescanear el QR.
//
// Si el watchdog dispara MAX_READY_TIMEOUTS veces seguidas, exit con
// código 1 — en producción NSSM reinicia el proceso desde cero (que
// puede limpiar más estado del que podemos limpiar internamente).

let _readyWatchdogTimer = null;
let _readyProgressTimer = null;
let _intentosReadyTimeout