// Inicialización del Firebase Admin SDK + helpers para la cola.

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');
const log = require('./logger');

let inicializado = false;

/**
 * Levanta el SDK con el service account configurado en `.env`. La ruta
 * puede ser relativa al CWD donde se ejecuta `npm start` (típicamente
 * `whatsapp-bot/`).
 */
function inicializar() {
  if (inicializado) return admin.firestore();

  const credPath =
    process.env.FIREBASE_CREDENTIALS_PATH || '../serviceAccountKey.json';
  const absPath = path.resolve(credPath);

  if (!fs.existsSync(absPath)) {
    throw new Error(
      `Firebase credentials no encontradas en: ${absPath}\n` +
        '→ Ajustar FIREBASE_CREDENTIALS_PATH en .env'
    );
  }

  const serviceAccount = require(absPath);
  // El bucket por default de Firebase es `<projectId>.appspot.com`
  // (legacy) o `<projectId>.firebasestorage.app` en proyectos nuevos.
  // Tomamos el que esté en el `.env` si lo hay, sino caemos al pattern
  // legacy que es el que usa el resto de la app Flutter.
  const projectId =
    process.env.FIREBASE_PROJECT_ID || serviceAccount.project_id;
  const storageBucket =
    process.env.FIREBASE_STORAGE_BUCKET || `${projectId}.appspot.com`;
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId,
    storageBucket,
  });
  inicializado = true;
  log.info(
    `Firebase Admin inicializado (project: ${projectId}, ` +
      `bucket: ${storageBucket})`
  );
  return admin.firestore();
}

/**
 * Sube `bytes` (Buffer) a Firebase Storage en `path` y devuelve la
 * URL pública signed para que la app pueda mostrar el archivo desde
 * cualquier cliente sin token de auth.
 *
 * Usar con `RESPUESTAS_BOT/{dni}_{timestamp}.{ext}` para mantener
 * todos los archivos del bot bajo un mismo prefijo en el bucket.
 */
async function subirAStorage({ path, bytes, contentType }) {
  if (!inicializado) inicializar();
  const bucket = admin.storage().bucket();
  const file = bucket.file(path);
  await file.save(bytes, {
    contentType: contentType || 'application/octet-stream',
    resumable: false, // archivos chicos, no necesitamos chunked upload
  });
  // makePublic() convierte el archivo en world-readable. Equivalente
  // a la URL firmada que devuelve `getDownloadURL` desde el SDK
  // cliente — la app Flutter ya está acostumbrada a usar URLs públicas
  // (todas las que llegan vía StorageService son así).
  await file.makePublic();
  return `https://storage.googleapis.com/${bucket.name}/${encodeURIComponent(
    path
  )}`;
}

/**
 * Constantes de la colección y los estados del workflow. Mantener
 * sincronizadas con `lib/features/whatsapp_bot/services/...` en la app
 * Flutter.
 */
const COLECCION = 'COLA_WHATSAPP';

const ESTADO = {
  pendiente: 'PENDIENTE',
  procesando: 'PROCESANDO',
  enviado: 'ENVIADO',
  error: 'ERROR',
};

/** Marca un doc como en proceso de envío (transitorio). */
async function marcarProcesando(docRef) {
  await docRef.update({
    estado: ESTADO.procesando,
    intentos: admin.firestore.FieldValue.increment(1),
    procesando_en: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/**
 * Marca un doc como enviado exitosamente. Si se pasa el [waMessageId]
 * (id devuelto por wwebjs al enviar) lo guardamos para asociar
 * después las respuestas que cite ese mensaje (Fase 3).
 */
async function marcarEnviado(docRef, { waMessageId } = {}) {
  await docRef.update({
    estado: ESTADO.enviado,
    enviado_en: admin.firestore.FieldValue.serverTimestamp(),
    error: null,
    wa_message_id: waMessageId || null,
  });
}

/** Marca un doc con error y guarda el detalle para que lo vea el admin. */
async function marcarError(docRef, mensaje) {
  await docRef.update({
    estado: ESTADO.error,
    error: String(mensaje).slice(0, 500),
    error_en: admin.firestore.FieldValue.serverTimestamp(),
  });
}

module.exports = {
  inicializar,
  subirAStorage,
  COLECCION,
  ESTADO,
  marcarProcesando,
  marcarEnviado,
  marcarError,
};
