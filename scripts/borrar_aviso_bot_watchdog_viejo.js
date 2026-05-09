// Borra docs huérfanos de COLA_WHATSAPP del watchdog viejo
// (origen: 'bot_watchdog'). Quedaron en cola al cambiar el sistema
// 2026-05-08: ahora el watchdog NO encola WhatsApp inmediato, los
// avisos van consolidados al día siguiente vía resumenBotDiario.
//
// Uso:
//   node scripts/borrar_aviso_bot_watchdog_viejo.js --dry-run
//   node scripts/borrar_aviso_bot_watchdog_viejo.js --apply

const path = require('path');
// firebase-admin desde whatsapp-bot/node_modules (mismo patrón que
// los otros scripts del repo — no duplicamos node_modules en raíz).
let admin;
try {
  admin = require('firebase-admin');
} catch (_) {
  admin = require(
    path.join(__dirname, '..', 'whatsapp-bot', 'node_modules', 'firebase-admin')
  );
}

const sa = path.resolve(__dirname, '..', 'serviceAccountKey.json');
admin.initializeApp({credential: admin.credential.cert(require(sa))});

const db = admin.firestore();

(async () => {
  const apply = process.argv.includes('--apply');
  const dry = process.argv.includes('--dry-run');
  if (!apply && !dry) {
    console.log('Pasale --dry-run o --apply.');
    process.exit(1);
  }

  const snap = await db
    .collection('COLA_WHATSAPP')
    .where('origen', '==', 'bot_watchdog')
    .get();

  console.log(`Encontrados ${snap.size} docs con origen=bot_watchdog.`);
  for (const d of snap.docs) {
    const data = d.data();
    console.log(
      `  - ${d.id} | estado=${data.estado} | encolado_en=${data.encolado_en?.toDate?.() ?? data.encolado_en}`
    );
  }

  if (dry) {
    console.log('\nDRY-RUN — no se borró nada. Para borrar: --apply');
    process.exit(0);
  }

  if (snap.size === 0) {
    console.log('Nada que borrar.');
    process.exit(0);
  }

  const batch = db.batch();
  snap.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();
  console.log(`\nOK ${snap.size} docs borrados.`);
})().catch((e) => {
  console.error('Error:', e);
  process.exit(1);
});
