// Wrapper sobre whatsapp-web.js. Encapsula:
//   - LocalAuth para que la sesión persista en .wwebjs_auth/
//   - QR rendering en consola al primer login
//   - Estado del cliente (autenticado / pronto para enviar)
//   - Verificación de número antes de enviar (evita "el chofer no tiene WhatsApp")

const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const log = require('./logger');

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
    log.info(
      'QR recibido — escaneá desde WhatsApp en el teléfono descartable.'
    );
    log.info('Ajustes → Dispositivos vinculados → Vincular un dispositivo.');
    qrcode.generate(qr, { small: true });
  });

  client.on('authenticated', () => {
    log.info('Sesión de WhatsApp autenticada y persistida en .wwebjs_auth/');
  });

  client.on('auth_failure', (msg) => {
    log.error(`Auth failure: ${msg}`);
  });

  client.on('ready', () => {
    listo = true;
    // Reset del contador — si después de andar bien se desconecta,
    // arrancamos los reintentos otra vez desde 0.
    _intentosReconexion = 0;
    log.info('WhatsApp listo para enviar.');
    callbacksAlEstarListo.splice(0).forEach((cb) => cb());
  });

  client.on('disconnected', (reason) => {
    listo = false;
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

/**
 * Verifica si un número está registrado en WhatsApp.
 *
 * Devuelve:
 * - `true` cuando WhatsApp confirma que el número tiene cuenta.
 * - `false` cuando WhatsApp confirma que el número NO tiene cuenta
 *   (caso terminal: marcamos el doc como ERROR para que el admin
 *   sepa que tiene que cargar otro número).
 *
 * Lanza la excepción original cuando hay un error transient (timeout,
 * sesión caída, etc.) — el caller decide si reintentar. Antes
 * tragábamos esos errores y devolvíamos `false`, lo que confundía
 * "no tiene WhatsApp" con "WhatsApp no respondió".
 */
async function tieneWhatsApp(wid) {
  if (!client || !listo) throw new Error('Cliente no inicializado');
  const numberId = await client.getNumberId(wid.replace('@c.us', ''));
  return numberId !== null;
}

/**
 * Envía un mensaje de texto. Devuelve el id de WhatsApp del mensaje
 * recién enviado, útil para asociar después respuestas con quote
 * (Fase 3). Lanza si el envío falla.
 */
async function enviarMensaje(wid, texto) {
  if (!client || !listo) throw new Error('Cliente no inicializado');
  const sent = await client.sendMessage(wid, texto);
  // `sent.id._serialized` es el id estable que después aparece como
  // `quotedMsg.id._serialized` cuando alguien responde citando.
  try {
    return sent && sent.id && sent.id._serialized ? sent.id._serialized : null;
  } catch (_) {
    return null;
  }
}

/**
 * Registra un handler para mensajes entrantes. wwebjs emite todos los
 * mensajes que llegan al número del bot — el caller filtra los que le
 * importan (sender registrado, no de grupo, no propios, etc.).
 */
function onMensajeEntrante(handler) {
  if (!client) throw new Error('Cliente no inicializado');
  client.on('message', handler);
}

/**
 * Cuando el bot recibe un mensaje, opcionalmente puede responder al
 * mismo hilo con una contestación corta. Lo usamos en Fase 3 para
 * acusar recibo: "Recibí, lo va a revisar la oficina."
 */
async function responder(msg, texto) {
  if (!client || !listo) throw new Error('Cliente no inicializado');
  await msg.reply(texto);
}

/**
 * Cierra ordenadamente el cliente. Llamar en SIGINT/SIGTERM para
 * que la sesión guardada quede consistente.
 */
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
