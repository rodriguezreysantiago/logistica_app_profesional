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
//      `.wwebjs_auth/session/` → Chromium nuevo cree que hay otra
//      instancia viva y se queda esperando. ESTE es el más jodido
//      porque NO se ve en el log; el bot queda en "Sesión autenticada"
//      eternamente.
//
// La sesión real (cookies, login persistido) está en otros archivos
// de `.wwebjs_auth/session/` que NO tocamos. Borrar SOLO los Singleton
// locks no requiere reescanear QR.
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

  // (2) Singleton locks dentro de la sesión persistida. Si quedan
  // de un proceso muerto, el nuevo Chromium se cuelga.
  const sessionDir = path.join(root, '.wwebjs_auth', 'session');
  const singletonFiles = [
    'SingletonLock',
    'SingletonCookie',
    'SingletonSocket',
  ];
  let borrados = 0;
  for (const name of singletonFiles) {
    const p = path.join(sessionDir, name);
    if (fsNode.existsSync(p)) {
      try {
        fsNode.rmSync(p, { force: true });
        borrados++;
      } catch (e) {
        log.warn(`No pude borrar ${name}: ${e.message}`);
      }
    }
  }
  if (borrados > 0) {
    log.info(
      `Locks de Chromium previos limpiados (${borrados} archivos Singleton*).`
    );
  }
}

// Cola en memoria con los doc IDs pendientes en orden FIFO.
// Procesamos uno a la vez para mantener el delay entre envíos
// determinístico y para no abrir múltiples sesiones de envío en
// paralelo (que dispararía el detector de bots).
const colaProcesar = [];
let procesando = false;

/**
 * Encola un doc para envío y arranca el loop si no estaba corriendo.
 */
function encolar(doc) {
  // Evitamos duplicados si por algún motivo Firestore emite el mismo
  // change dos veces (nos pasó con cambios de estado intermedios).
  if (colaProcesar.includes(doc.id)) return;
  colaProcesar.push(doc.id);
  log.info(`+ Encolado ${doc.id} (total en cola: ${colaProcesar.length})`);
  if (!procesando) procesarSiguiente();
}

async function procesarSiguiente() {
  if (procesando) return;
  if (colaProcesar.length === 0) return;
  procesando = true;

  const docId = colaProcesar.shift();
  const db = fs.inicializar();
  const docRef = db.collection(fs.COLECCION).doc(docId);

  try {
    // Releemos el doc — el estado puede haber cambiado entre que
    // entró al array y que llegamos a procesarlo (ej. el admin
    // canceló desde la app).
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

    // ─── Validación: horario hábil ───
    if (!enHorarioHabil()) {
      log.info(
        `Fuera de horario hábil. ${docId} queda en estado PENDIENTE para que el polling lo reintente cuando vuelva el horario.`
      );
      return;
    }

    // ─── Validación: número ───
    const wid = normalizarTelefonoAWid(data.telefono);
    if (!wid) {
      log.warn(`${docId} con teléfono inválido: ${data.telefono}`);
      await fs.marcarError(
        docRef,
        `Teléfono inválido: "${data.telefono}". Esperado E.164 (+5492914567890).`
      );
      return;
    }

    // ─── Validación: el número tiene WhatsApp ───
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

    // ─── Marca PROCESANDO + delay anti-bot + envío ───
    await fs.marcarProcesando(docRef);
    const delay = delayAleatorioMs();
    log.info(
      `→ Enviando ${docId} a ${data.telefono} en ${Math.round(delay / 1000)}s...`
    );
    await sleep(delay);

    const waMessageId = await wa.enviarMensaje(wid, data.mensaje);
    await fs.marcarEnviado(docRef, { waMessageId });
    health.registrarEnvio();
    log.info(`✓ Enviado ${docId} (wa_id: ${waMessageId || '?'})`);
  } catch (e) {
    log.error(`✗ Falló ${docId}: ${e.message}`);
    health.registrarError('envio', `${docId}: ${e.message}`);
    try {
      await fs.marcarError(docRef, e.message);
    } catch (e2) {
      log.error(`No se pudo marcar como ERROR: ${e2.message}`);
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
//
// En vez de mantener un `onSnapshot` con stream gRPC abierto (que se
// cae cada ~2 min en redes con NAT/firewall agresivo cortando
// conexiones idle), hacemos polling con `get()` cada N segundos. Más
// resiliente, menos elegante pero confiable.

let _pollingTimer = null;

async function pollearCola(db) {
  try {
    const qs = await db
      .collection(fs.COLECCION)
      .where('estado', '==', fs.ESTADO.pendiente)
      .get();
    qs.forEach((doc) => encolar(doc));
  } catch (e) {
    log.warn(`Polling Firestore falló: ${e.message}`);
  }
}

function iniciarPolling(db) {
  if (_pollingTimer) return; // idempotente
  const intervaloSeg = parseInt(
    process.env.POLLING_INTERVAL_SECONDS || '15',
    10
  );
  log.info(
    `Polling de ${fs.COLECCION} cada ${intervaloSeg}s (modo robusto: sin streams gRPC).`
  );
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

  // Cleanup preventivo (cache + singleton locks) antes de levantar Chromium.
  limpiarLocksChromium();

  const db = fs.inicializar();

  log.info('Conectando a WhatsApp Web — esto puede demorar 10-30s...');
  await wa.inicializar();

  iniciarPolling(db);

  // Heartbeat a BOT_HEALTH/main para que la app pueda mostrar estado
  // del bot en vivo. Arranca después de que WhatsApp esté listo
  // (asegura que health.setEstadoCliente('LISTO') ya se llamó).
  health.iniciar(db, fs, wa);

  // Cron de avisos automáticos (Fase 2).
  cron.start(fs);

  // Handler de respuestas (Fase 3).
  const respuestasHabilitado =
    String(process.env.AUTO_RESPUESTAS_ENABLED || 'false').toLowerCase() ===
    'true';
  if (respuestasHabilitado) {
    log.info('Handler de respuestas HABILITADO.');
    wa.onMensajeEntrante(messageHandler.crearHandler(fs, wa));
  } else {
    log.info(
      'Handler de respuestas DESHABILITADO (AUTO_RESPUESTAS_ENABLED=false).'
    );
  }

  // Manejo de señales para cerrar limpio.
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
