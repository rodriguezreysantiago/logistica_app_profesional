// Entrypoint del bot. Orquesta:
//   1. Carga de .env
//   2. Inicialización de Firebase Admin
//   3. Conexión a WhatsApp Web (con persistencia de sesión)
//   4. Listener de COLA_WHATSAPP que procesa mensajes uno por uno
//      respetando horario hábil y delay aleatorio.

require('dotenv').config();

const log = require('./logger');
const fs = require('./firestore');
const wa = require('./whatsapp');
const cron = require('./cron');
const messageHandler = require('./message_handler');
const {
  enHorarioHabil,
  delayAleatorioMs,
  sleep,
  normalizarTelefonoAWid,
} = require('./humano');

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
        `Fuera de horario hábil. ${docId} queda en cola para más tarde.`
      );
      // Lo volvemos a encolar al final para reintentar después.
      colaProcesar.push(docId);
      // Esperamos 15 minutos antes de mirar de nuevo.
      await sleep(15 * 60 * 1000);
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
    // tieneWhatsApp devuelve false solo cuando WhatsApp confirma que
    // el número NO tiene cuenta. Si lanza, es un error transient
    // (timeout, sesión caída) — lo dejamos propagar para que el catch
    // exterior haga retry vía el listener de Firestore.
    let existe;
    try {
      existe = await wa.tieneWhatsApp(wid);
    } catch (e) {
      // Volvemos a poner el doc en PENDIENTE para que el listener lo
      // levante en el próximo cambio. Si el problema es la sesión, se
      // resuelve cuando wwebjs reconecte.
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
    log.info(`✓ Enviado ${docId} (wa_id: ${waMessageId || '?'})`);
  } catch (e) {
    log.error(`✗ Falló ${docId}: ${e.message}`);
    try {
      await fs.marcarError(docRef, e.message);
    } catch (e2) {
      log.error(`No se pudo marcar como ERROR: ${e2.message}`);
    }
  } finally {
    procesando = false;
    // Si quedan más, seguimos.
    if (colaProcesar.length > 0) {
      // Pequeña pausa entre items para evitar que un error rápido
      // genere un loop tight de marcado de errores.
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
//
// El intervalo lo configura POLLING_INTERVAL_SECONDS en .env (default
// 15s). Cada ciclo:
//   1. Consulta los docs en estado PENDIENTE.
//   2. Para cada uno que NO esté ya en la cola en memoria, lo encola.
//   3. La guardia `if (colaProcesar.includes(doc.id))` en `encolar`
//      evita duplicados entre ciclos consecutivos.
//
// Si querés volver al modo onSnapshot (cuando la red lo soporte),
// alcanza con revertir este commit.

let _pollingTimer = null;

async function pollearCola(db) {
  try {
    const qs = await db
      .collection(fs.COLECCION)
      .where('estado', '==', fs.ESTADO.pendiente)
      .get();
    qs.forEach((doc) => encolar(doc));
  } catch (e) {
    // Si una corrida falla, logueamos y seguimos con la próxima.
    // No abandonamos el polling — la siguiente iteración intenta de
    // nuevo. Esto resiste cortes de red transitorios sin necesitar
    // reconexión explícita.
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
  // Primera corrida inmediata para no esperar 15s.
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

  const db = fs.inicializar();

  log.info('Conectando a WhatsApp Web — esto puede demorar 10-30s...');
  await wa.inicializar();

  iniciarPolling(db);

  // Cron de avisos automáticos (Fase 2). Solo arranca si
  // AUTO_AVISOS_ENABLED=true en .env. Es idempotente: si ya se mandó
  // el mismo aviso (mismo nivel de urgencia, misma fecha de
  // vencimiento), no se duplica.
  cron.start(fs);

  // Handler de respuestas (Fase 3). Cuando el chofer manda un
  // comprobante por WhatsApp, el bot crea automáticamente la
  // revisión para que el admin la apruebe desde la app.
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
  //
  // Grace period: si hay un mensaje en proceso (`procesando=true`),
  // esperamos hasta 10 segundos a que termine antes de exit. Eso
  // evita dejar docs en estado PROCESANDO sin avanzar cuando el
  // admin reinicia el bot. Si después del grace sigue corriendo,
  // forzamos exit igual para no quedar colgados indefinidamente.
  const shutdown = async (sig) => {
    log.info(`Recibido ${sig}, cerrando...`);
    detenerPolling();
    cron.stop();

    // Esperar a que termine el item en curso (si lo hay).
    const start = Date.now();
    const graceMs = 10000;
    while (procesando && Date.now() - start < graceMs) {
      await sleep(200);
    }
    if (procesando) {
      log.warn('Grace period agotado; saliendo aunque hay un envío en curso.');
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
