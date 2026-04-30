// Fase 3 — manejo de mensajes entrantes.
//
// Cuando un chofer responde al bot con texto + foto del nuevo
// comprobante, este handler:
//
//   1. Filtra mensajes que no nos interesan (grupos, broadcasts,
//      propios, status updates).
//   2. Identifica al chofer cruzando el teléfono con `EMPLEADOS`. Si
//      no es un chofer registrado, ignora el mensaje (cualquiera podría
//      escribirle al bot).
//   3. Asocia la respuesta con un aviso anterior:
//      a) Si la respuesta cita un mensaje del bot (quote de WhatsApp),
//         buscamos por `wa_message_id` el doc original en
//         COLA_WHATSAPP — ahí sabemos qué papel era.
//      b) Si no hay quote pero el chofer tiene un único aviso reciente
//         (≤ 72h, estado ENVIADO) sin respuesta, asociamos a ese.
//      c) Si hay ambigüedad o ningún aviso reciente, marcamos como
//         "ambiguo" y lo dejamos para revisión manual del admin.
//   4. Si hay media (imagen / PDF), la sube a Firebase Storage en
//      `RESPUESTAS_BOT/{dni}_{timestamp}.{ext}`.
//   5. Extrae fecha del texto del mensaje con regex (port del
//      OcrService Dart).
//   6. Crea un doc en `REVISIONES` con la misma forma que las
//      revisiones manuales — el admin lo aprueba/rechaza desde la app
//      como cualquier otra. Marcado con `origen: 'BOT_WHATSAPP'`
//      para distinguirlas en el listado.
//   7. Acusa recibo al chofer.

const admin = require('firebase-admin');
const log = require('./logger');
const fechaExtractor = require('./fecha_extractor');
const commands = require('./commands');
const control = require('./control');
const cron = require('./cron');

// Mapeo de teléfono normalizado (solo dígitos) → DNI del chofer.
// Se rebuilds cada vez que llega un mensaje porque las altas/bajas
// de empleados son raras y la app lista al mes son ~30 docs:
// el costo de la query ad-hoc es despreciable.
async function _resolverChofer(db, fromNumber) {
  const fromDigits = String(fromNumber).replace(/\D+/g, '');
  if (!fromDigits) return null;
  const snap = await db.collection('EMPLEADOS').get();
  for (const doc of snap.docs) {
    const data = doc.data();
    const tel = String(data.TELEFONO || '').replace(/\D+/g, '');
    if (!tel) continue;

    // Match estricto: o coinciden exactamente los dígitos, o uno
    // termina con el otro (caso típico: el chofer guardó "2914567890"
    // y nos llega "5492914567890" con prefijo país, o viceversa).
    //
    // Antes había un match por sufijo de 8 dígitos que era vulnerable:
    // dos números no relacionados con los mismos últimos 8 dígitos
    // matcheaban y un atacante podía impersonar al chofer.
    //
    // Exigimos un mínimo de 10 dígitos en el más corto para asegurar
    // que estamos comparando un teléfono real argentino completo
    // (área + abonado), no solo el abonado local.
    if (fromDigits === tel) {
      return { dni: doc.id, data };
    }
    const corto = fromDigits.length <= tel.length ? fromDigits : tel;
    const largo = fromDigits.length <= tel.length ? tel : fromDigits;
    if (corto.length >= 10 && largo.endsWith(corto)) {
      return { dni: doc.id, data };
    }
  }
  return null;
}

/**
 * Busca el doc de COLA_WHATSAPP que originó la conversación con este
 * chofer. Prioridad:
 *   1. Si la respuesta cita un mensaje (quote), buscar por
 *      `wa_message_id` exacto.
 *   2. Si no hay quote, buscar el último ENVIADO al mismo destinatario
 *      en las últimas 72h.
 *   3. Si hay más de uno reciente y la respuesta no cita, devolver
 *      `{ ambiguo: true }` para que el caller lo deje en bandeja.
 */
async function _asociarConAviso(db, chofer, msg, quotedId) {
  // 1) Por quote
  if (quotedId) {
    const q = await db
      .collection('COLA_WHATSAPP')
      .where('wa_message_id', '==', quotedId)
      .limit(1)
      .get();
    if (!q.empty) {
      return { aviso: q.docs[0], razon: 'quote' };
    }
  }

  // 2) Por contexto reciente
  const limite = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - 72 * 60 * 60 * 1000)
  );
  const recientes = await db
    .collection('COLA_WHATSAPP')
    .where('destinatario_id', '==', chofer.dni)
    .where('estado', '==', 'ENVIADO')
    .where('enviado_en', '>=', limite)
    .orderBy('enviado_en', 'desc')
    .limit(5)
    .get();

  if (recientes.empty) {
    return { aviso: null, razon: 'sin_aviso_reciente' };
  }
  if (recientes.docs.length === 1) {
    return { aviso: recientes.docs[0], razon: 'unico_reciente' };
  }
  // Múltiples avisos sin respuesta — no podemos elegir solos.
  return { aviso: null, razon: 'ambiguo', candidatos: recientes.docs };
}

/**
 * Sube la media adjunta del mensaje a Firebase Storage. wwebjs entrega
 * media como base64 — la convertimos a Buffer y delegamos al helper de
 * `firestore.js`.
 */
async function _subirMedia(fs, msg, dni) {
  const media = await msg.downloadMedia();
  if (!media) return null;
  const ext = _extensionDeMime(media.mimetype) || 'bin';
  const ts = Date.now();
  // Defense-in-depth: aunque hoy el DNI viene de doc.id de EMPLEADOS y
  // está garantizado a ser dígitos por DigitOnlyFormatter en la app,
  // sanitizamos acá para que un DNI mal cargado (vía consola Firebase
  // u otra herramienta) no permita path traversal en Storage.
  const dniSeguro = String(dni).replace(/[^0-9]/g, '') || 'desconocido';
  const path = `RESPUESTAS_BOT/${dniSeguro}_${ts}.${ext}`;
  const bytes = Buffer.from(media.data, 'base64');
  return await fs.subirAStorage({
    path,
    bytes,
    contentType: media.mimetype,
  });
}

function _extensionDeMime(mime) {
  if (!mime) return null;
  if (mime.includes('jpeg')) return 'jpg';
  if (mime.includes('png')) return 'png';
  if (mime.includes('pdf')) return 'pdf';
  if (mime.includes('webp')) return 'webp';
  return null;
}

/**
 * Crea un doc en `REVISIONES` con la misma forma que las revisiones
 * que crea la app cuando el chofer las sube manualmente. El admin las
 * va a ver mezcladas en la pantalla "Revisiones Pendientes" — las del
 * bot se identifican por `origen: 'BOT_WHATSAPP'`.
 */
async function _crearRevision(db, { chofer, avisoData, urlArchivo, pathStorage, fechaIso, mensajeOriginal }) {
  await db.collection('REVISIONES').add({
    dni: chofer.dni,
    nombre_usuario: chofer.data.NOMBRE || chofer.dni,
    campo: avisoData.campo_base
      ? `VENCIMIENTO_${avisoData.campo_base}`
      : 'VENCIMIENTO_DESCONOCIDO',
    coleccion_destino: avisoData.destinatario_coleccion || 'EMPLEADOS',
    etiqueta: avisoData.campo_base || 'Documento',
    fecha_vencimiento: fechaIso,
    url_archivo: urlArchivo || '',
    path_storage: pathStorage || '',
    estado: 'PENDIENTE',
    fecha_solicitud: admin.firestore.FieldValue.serverTimestamp(),
    origen: 'BOT_WHATSAPP',
    mensaje_chofer: String(mensajeOriginal || '').slice(0, 1000),
  });
}

/**
 * Cuando no podemos asociar la respuesta con confianza, va a una
 * bandeja para que el admin la procese manualmente. La pantalla
 * `AdminBotBandejaScreen` la lee y permite convertirla en revisión
 * eligiendo el papel.
 */
async function _crearAmbiguo(db, { chofer, msg, urlArchivo, fechaIso, razon, candidatos }) {
  await db.collection('RESPUESTAS_BOT_AMBIGUAS').add({
    dni: chofer.dni,
    nombre_usuario: chofer.data.NOMBRE || chofer.dni,
    telefono: String(msg.from || '').replace('@c.us', ''),
    mensaje_chofer: String(msg.body || '').slice(0, 1000),
    url_archivo: urlArchivo || '',
    fecha_detectada: fechaIso || null,
    razon, // 'ambiguo' | 'sin_aviso_reciente'
    candidatos: candidatos
      ? candidatos.map((d) => ({
          cola_doc_id: d.id,
          campo_base: d.data().campo_base,
          enviado_en: d.data().enviado_en,
        }))
      : [],
    estado: 'PENDIENTE',
    creado_en: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Punto de entrada. Se registra como handler del evento `message`
 * de wwebjs.
 *
 * @param {object} fs - módulo firestore.js (DB + helper de storage)
 * @param {object} wa - módulo whatsapp.js (para responder)
 */
function crearHandler(fs, wa) {
  const db = fs.inicializar();

  return async (msg) => {
    try {
      // ─── Filtros básicos ───
      if (msg.fromMe) return; // mensajes del propio bot
      if (msg.isStatus) return; // status updates
      if (msg.from && msg.from.endsWith('@g.us')) return; // grupo
      if (!msg.from || !msg.from.endsWith('@c.us')) return; // broadcast / unknown

      // ─── Comandos admin (early return si matchea) ───
      // Si el mensaje empieza con `/` y viene de un admin autorizado
      // (whitelist en .env: ADMIN_PHONES), lo procesamos como comando
      // y NO seguimos al flujo de Fase 3.
      const eraComando = await commands.manejarSiEsComando(msg, {
        db, fs, control, cron,
      });
      if (eraComando) return;

      // ─── Identificar al chofer ───
      const fromNumber = msg.from.replace('@c.us', '');
      const chofer = await _resolverChofer(db, fromNumber);
      if (!chofer) {
        log.debug(`Mensaje de número no registrado ${fromNumber}, ignoro.`);
        return;
      }

      // ─── Quote del aviso original (si vino) ───
      let quotedId = null;
      if (msg.hasQuotedMsg) {
        try {
          const quoted = await msg.getQuotedMessage();
          if (quoted && quoted.id && quoted.id._serialized) {
            quotedId = quoted.id._serialized;
          }
        } catch (_) {
          // ignoramos — caemos al fallback por contexto
        }
      }

      // ─── Asociar con un aviso ───
      const asoc = await _asociarConAviso(db, chofer, msg, quotedId);
      log.info(
        `← Mensaje de ${chofer.dni} asociación=${asoc.razon}` +
          (asoc.aviso ? ` (cola ${asoc.aviso.id})` : '')
      );

      // ─── Procesar media + extraer fecha ───
      let urlArchivo = null;
      let pathStorage = null;
      if (msg.hasMedia) {
        try {
          urlArchivo = await _subirMedia(fs, msg, chofer.dni);
          if (urlArchivo) {
            // El path se puede deducir de la URL pero conviene guardarlo
            // explícito para que `revision_service.finalizarRevision`
            // sepa qué borrar de Storage si rechaza la solicitud.
            pathStorage = urlArchivo
              .split('storage.googleapis.com/')
              .pop()
              .split('?')[0];
          }
        } catch (e) {
          log.error(`No se pudo subir media: ${e.message}`);
        }
      }

      const fecha = fechaExtractor.extraerFechaMasLejana(msg.body);
      const fechaIso = fechaExtractor.aIsoYMD(fecha);

      // ─── Crear el doc destino ───
      if (asoc.aviso) {
        await _crearRevision(db, {
          chofer,
          avisoData: asoc.aviso.data(),
          urlArchivo,
          pathStorage,
          fechaIso,
          mensajeOriginal: msg.body,
        });
        log.info(`✓ Revisión creada para ${chofer.dni}`);
        try {
          await wa.responder(
            msg,
            'Recibí el comprobante. La oficina lo va a revisar en breve.'
          );
        } catch (e) {
          log.warn(`No pude acusar recibo: ${e.message}`);
        }
      } else {
        await _crearAmbiguo(db, {
          chofer,
          msg,
          urlArchivo,
          fechaIso,
          razon: asoc.razon,
          candidatos: asoc.candidatos,
        });
        log.info(
          `⚠️  Mensaje de ${chofer.dni} fue a bandeja ambigua (razón: ${asoc.razon})`
        );
        try {
          await wa.responder(
            msg,
            'Recibí tu mensaje, pero no pude asociarlo automáticamente. ' +
              'La oficina lo va a revisar y te confirma.'
          );
        } catch (_) {
          // best-effort
        }
      }
    } catch (e) {
      log.error(`Error procesando mensaje entrante: ${e.stack || e.message}`);
    }
  };
}

module.exports = {
  crearHandler,
  // Exportados para tests:
  _resolverChofer,
  _asociarConAviso,
};
