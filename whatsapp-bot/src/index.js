// Entrypoint del bot. Orquesta:
//   1. Carga de .env
//   2. Inicialización de Firebase Admin
//   3. Conexión a WhatsApp Web (con persistencia de sesión)
//   4. Listener de COLA_WHATSAPP que procesa mensajes uno por uno
//      respetando horario hábil y delay aleatorio.

require('dotenv').config();

// Fijamos la TZ del proceso EN EL TOP, antes de cualquier require que
// dependa de fechas (cron, historico, calcularDiasRestantes). Sin esto
// el bot heredaria la TZ del host -- si maniana migramos a Cloud Run
// region US, los avisos se desfasarian un dia (medianoche ART vs UTC).
// Configurable via env: BOT_TIMEZONE=America/Argentina/Buenos_Aires
// (default si no esta seteada).
process.env.TZ = process.env.BOT_TIMEZONE || 'America/Argentina/Buenos_Aires';

const fsNode = require('fs');
const path = require('path');
const os = require('os');

const admin = require('firebase-admin');
const log = require('./logger');

// Handlers globales de excepciones no atrapadas. Antes el bot las
// dejaba burbujear: NSSM reiniciaba el proceso y nadie sabia que paso
// (timer rejection en polling? heartbeat? watchdog?). Ahora siempre
// queda el stack en stdout/NSSM logs.
//
// Decision sobre exit:
//   - unhandledRejection: NO matamos. Una promesa puntual que falla
//     (ej. Firestore timeout en un .get()) no debe tirar el proceso
//     entero -- los polling loops y el cron deben seguir. Solo logear.
//   - uncaughtException: SI matamos. Excepcion sincronica = bug
//     serio en estado dificil de razonar. Mejor reset limpio y que
//     NSSM reinicie. exit(1) hace que el supervisor lo detecte como
//     fallo y aplique backoff.
process.on('unhandledRejection', (reason, _promise) => {
  log.error('UNHANDLED PROMISE REJECTION:', reason);
  if (reason instanceof Error && reason.stack) {
    log.error(reason.stack);
  }
});
process.on('uncaughtException', (error) => {
  log.error('UNCAUGHT EXCEPTION:', error);
  if (error instanceof Error && error.stack) {
    log.error(error.stack);
  }
  process.exit(1);
});

const fs = require('./firestore');
const wa = require('./whatsapp');
const cron = require('./cron');
const health = require('./health');
const control = require('./control');
const messageHandler = require('./message_handler');

// Identificador de esta PC. Configurable via env var BOT_PC_ID
// (recomendado: "casa", "oficina", "server-prod"). Si no se setea,
// usamos el hostname del SO como fallback ("DESKTOP-XYZ123"). Lo
// usamos para detectar el caso "el bot ya esta corriendo en otra PC"
// y evitar dos instancias procesando la misma cola.
const PC_ID = process.env.BOT_PC_ID || os.hostname() || 'desconocida';
const {
  enHorarioHabil,
  delayAleatorioMs,
  sleep,
  normalizarTelefonoAWid,
} = require('./humano');
const { aLocalDateTime } = require('./fechas');

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
        `(${aLocalDateTime(cuando)})`
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

    // Lock atómico: si otra instancia se adelantó (race poco probable
    // ya que el anti-doble-bot debería garantizar single-instance, pero
    // defensa en profundidad), retorna false y skipeamos sin enviar.
    const tomamosElLock = await fs.marcarProcesandoSiPendiente(docRef);
    if (!tomamosElLock) {
      log.debug(`${docId}: otro proceso lo tomó primero, salto.`);
      return;
    }
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
      // Si _despacharFalloEnvio falla (típicamente Firestore caído al
      // momento de marcar PENDIENTE/ERROR), el doc queda en estado
      // inconsistente. Antes el bot llamaba `procesarSiguiente()` de
      // inmediato → martillaba Firestore varias veces por segundo. Ahora
      // marcamos la flag para que el `finally` salte la siguiente
      // iteración y deje al polling reintentar dentro de 15s.
      log.error(
        `No se pudo despachar fallo de envío: ${e2.message}. ` +
        `Cortando procesarSiguiente — el polling reintenta en el próximo ciclo.`
      );
      _despachoFalloErrorReciente = Date.now();
    }
  } finally {
    procesando = false;
    // Si hubo fallo en el despacho hace poco, no llamamos
    // procesarSiguiente — esperamos al polling. Esto da tiempo a que
    // Firestore se recupere y evita el loop apretado.
    const haceCuanto = Date.now() - _despachoFalloErrorReciente;
    const recienHuboFallo = haceCuanto < 5000;
    if (!recienHuboFallo && colaProcesar.length > 0) {
      await sleep(500);
      procesarSiguiente();
    }
  }
}

// Timestamp del último fallo en `_despacharFalloEnvio()`. Si fue hace
// menos de 5s, `procesarSiguiente()` corta para no martillar Firestore
// con reintentos sincrónicos. El polling normal (cada 15s) toma el
// relevo. 0 = nunca falló (no hay corte activo).
let _despachoFalloErrorReciente = 0;

// ─── Polling de COLA_WHATSAPP ───────────────────────────────────────
let _pollingTimer = null;
// Trackea el ultimo estado de horario habil visto por el polling
// para loguear SOLO al cruzar el umbral (no cada 15s). null = primer
// poll de la sesion.
let _ultimoEstadoHorario = null;

// Guard contra overlap del polling: si un ciclo tarda más que
// POLLING_INTERVAL_SECONDS (típicamente 15s, pero Firestore lento puede
// hacer que tarde 30s+), el setInterval dispara uno nuevo antes de que
// termine el anterior → dos pollings concurrentes encolan los mismos
// docs → un doc se procesa dos veces. Esta flag serializa.
let _polleando = false;

const POLL_TIMEOUT_MS = parseInt(
  process.env.POLL_TIMEOUT_MS || '10000',
  10
);

/**
 * Envuelve una promesa con un timeout. Si la promesa no resuelve en
 * `ms`, se rechaza con un error etiquetado. Útil para queries de
 * Firestore que de otro modo podrían quedar colgadas indefinidamente
 * cuando hay problemas de red.
 */
function _withTimeout(promise, ms, label) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(
        () => reject(new Error(`Timeout (${ms}ms): ${label}`)),
        ms
      )
    ),
  ]);
}

async function pollearCola(db) {
  if (_polleando) {
    log.debug('Polling previo aún en curso, skip este ciclo.');
    return;
  }
  _polleando = true;
  try {
    // Sweeper de docs stale en PROCESANDO: si el bot crasheo durante
    // un envio anterior (entre marcarProcesando y marcarEnviado), el
    // doc quedo PROCESANDO y nadie lo repesca. Lo devolvemos a
    // PENDIENTE para que entre al ciclo actual. Corre SIEMPRE -- aun
    // fuera de horario habil queremos mantener el estado de la cola.
    try {
      const recuperados = await _withTimeout(
        fs.recuperarStaleProcesando(db),
        POLL_TIMEOUT_MS,
        'sweeper PROCESANDO'
      );
      if (recuperados > 0) {
        log.warn(`Sweeper: recupere ${recuperados} doc(s) stale en PROCESANDO → PENDIENTE.`);
      }
    } catch (e) {
      log.warn(`Sweeper de PROCESANDO fallo: ${e.message}`);
    }

    // Skip rapido si estamos fuera de horario habil (incluye fines de
    // semana, noches, y feriados nacionales). Sin esto, el polling
    // re-traia el mismo doc PENDIENTE cada 15s y logueaba "Fuera de
    // horario..." en cada vuelta -> ~35K lineas inutiles en un fin
    // de semana largo, que ahogan los logs reales.
    //
    // Loguear solo al cruzar el umbral: cuando entramos a fuera de
    // horario, una linea; cuando volvemos a horario habil, otra.
    const enHorario = enHorarioHabil();
    if (_ultimoEstadoHorario === null) {
      log.info(enHorario
        ? 'Polling: en horario habil -- procesando envios.'
        : 'Polling: fuera de horario habil -- pausa hasta proximo dia habil.');
    } else if (_ultimoEstadoHorario !== enHorario) {
      log.info(enHorario
        ? 'Horario habil reanudado -- polling activo.'
        : 'Fuera de horario habil -- pausa hasta proximo dia habil.');
    }
    _ultimoEstadoHorario = enHorario;
    if (!enHorario) return;

    const qs = await _withTimeout(
      db
        .collection(fs.COLECCION)
        .where('estado', '==', fs.ESTADO.pendiente)
        .get(),
      POLL_TIMEOUT_MS,
      'pollearCola query'
    );
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
  } finally {
    _polleando = false;
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

// Umbral en segundos para considerar un heartbeat como "fresco".
// Si la otra PC envio heartbeat hace menos que esto, asumimos que
// esta viva. El default es 150s (2.5x el heartbeat default de 60s),
// que da un margen razonable para cubrir un ciclo perdido por red
// o lentitud sin generar falsos positivos.
const UMBRAL_HEARTBEAT_FRESCO_SEG = parseInt(
  process.env.UMBRAL_OTRA_INSTANCIA_SEG || '150',
  10
);

async function _verificarNoHayOtraInstancia(db) {
  if (String(process.env.FORCE_START || '').toLowerCase() === 'true') {
    log.warn('FORCE_START=true -- saltando check de otra instancia.');
    return;
  }

  // Check + claim atómico: usamos transacción para que dos PCs que
  // arranquen casi simultáneamente NO pasen el check ambas. Una gana
  // la transacción y escribe su pcId; la otra ve la escritura ganadora
  // y aborta. Sin transacción había race window de ~100ms en que dos
  // bots procesaban la misma cola → mensajes duplicados → baneo.
  const ref = db.collection('BOT_HEALTH').doc('main');
  let abortInfo = null;

  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);

      if (snap.exists) {
        const data = snap.data();
        const ultimoHb = data.ultimoHeartbeat;
        const otroPcId = data.pcId || 'desconocida';
        if (ultimoHb) {
          const ultimoMs = typeof ultimoHb.toMillis === 'function'
            ? ultimoHb.toMillis()
            : new Date(ultimoHb).getTime();
          const segDesdeUltimo = Math.round((Date.now() - ultimoMs) / 1000);
          const fresco = segDesdeUltimo <= UMBRAL_HEARTBEAT_FRESCO_SEG;
          if (fresco && otroPcId !== PC_ID) {
            // Heartbeat fresco de OTRA PC — la otra está viva. Vamos
            // a abortar después de salir de la transacción (no
            // queremos process.exit dentro de una tx).
            abortInfo = { otroPcId, segDesdeUltimo };
            // Lanzamos error para abortar la tx (no queremos escribir).
            throw new Error('OTRA_INSTANCIA_VIVA');
          }
        }
      }

      // Llegamos acá si: no había doc, no había heartbeat, el heartbeat
      // estaba viejo (otra PC muerta), o el heartbeat era nuestro
      // (somos nosotros reiniciado). En todos los casos, claimeamos el
      // lock escribiendo nuestro pcId con un heartbeat fresco. Si dos
      // PCs llegan acá simultáneamente, Firestore detecta conflicto en
      // commit y reintenta — la perdedora va a ver el heartbeat de la
      // ganadora y entrar al branch de abort.
      tx.set(
        ref,
        {
          pcId: PC_ID,
          ultimoHeartbeat: admin.firestore.FieldValue.serverTimestamp(),
          estadoCliente: 'INICIANDO',
          ultimoStartup: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    });
  } catch (e) {
    if (abortInfo) {
      // Branch de abort: hay otra PC viva. Mostramos mensaje claro y
      // exit(1). NSSM se va a quedar quieto (NO reinicia indefinidamente
      // porque el exit es deliberado, no por crash).
      log.error(
        `\nABORTANDO: el bot YA esta corriendo en otra PC.\n\n` +
        `  PC remota:        ${abortInfo.otroPcId}\n` +
        `  Mi PC:            ${PC_ID}\n` +
        `  Ultimo heartbeat: hace ${abortInfo.segDesdeUltimo}s\n` +
        `  Umbral:           ${UMBRAL_HEARTBEAT_FRESCO_SEG}s\n\n` +
        `Para evitar que dos bots procesen la misma cola y dupliquen ` +
        `mensajes (riesgo de baneo de WhatsApp), no arranco.\n\n` +
        `Soluciones:\n` +
        `  1. Detener el bot en "${abortInfo.otroPcId}" (recomendado).\n` +
        `  2. Si sabes que esa PC esta muerta y el heartbeat es residual, ` +
        `seteá FORCE_START=true en .env y reintentá.\n`
      );
      process.exit(1);
    }
    // Otro error de transacción (red, rules, conflicto irrecuperable) —
    // arrancamos igual. Mejor un bot arrancando con riesgo bajo de
    // duplicado que un bot bloqueado por una falla intermitente.
    log.warn(
      `Error en transacción de check de instancia: ${e.message}. ` +
      `Arrancando igual (best-effort).`
    );
  }
}

async function main() {
  log.info(`Iniciando whatsapp-bot (PC_ID=${PC_ID})...`);
  limpiarLocksChromium();

  const db = fs.inicializar();

  // ─── Check anti-doble-bot ────────────────────────────────────────
  // Antes de inicializar WhatsApp Web (lo mas pesado y lo que dispara
  // un linkeo de dispositivo), verificamos que no haya OTRA PC ya
  // corriendo el bot. El criterio es: si el ultimo heartbeat de
  // BOT_HEALTH/main es de hace menos de UMBRAL_FRESCO segundos Y el
  // pcId del heartbeat es DISTINTO al nuestro, asumimos que esta otra
  // PC esta procesando la cola y abortamos. Si es del mismo pcId
  // (yo, simplemente reiniciado), o no hay heartbeat reciente, sigo.
  //
  // Bypass: setear FORCE_START=true en .env si querias arrancar igual
  // (util para casos raros tipo "la otra PC se colgo y yo se que esta
  // muerta aunque el heartbeat sea reciente").
  await _verificarNoHayOtraInstancia(db);

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
