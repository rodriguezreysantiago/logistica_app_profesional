// Limpia los 8 campos viejos en docs EMPLEADOS que quedaron como
// espacio muerto al pasar los 4 docs laborales (Póliza ART, F. 931,
// Seguro de Vida / SCVO, Libre deuda sindical) a nivel empresa
// empleadora (EMPRESAS_EMPLEADORAS) el 2026-05-08.
//
// Campos que se borran (con FieldValue.delete()):
//   VENCIMIENTO_ART, ARCHIVO_ART
//   VENCIMIENTO_931, ARCHIVO_931
//   VENCIMIENTO_SEGURO_DE_VIDA, ARCHIVO_SEGURO_DE_VIDA
//   VENCIMIENTO_LIBRE_DE_DEUDA_SINDICAL, ARCHIVO_LIBRE_DE_DEUDA_SINDICAL
//
// Solo afecta a EMPLEADOS donde alguno de esos campos está poblado
// (no escribe en docs limpios). Best-effort: si Storage tiene PDFs
// asociados a los ARCHIVO_*, NO se borran de Storage (puede haber
// referencias en otros lugares de la app o histórico). Si querés
// limpiar Storage también, script aparte.
//
// Uso:
//   node scripts/cleanup_campos_viejos_empleados.js --dry-run
//   node scripts/cleanup_campos_viejos_empleados.js --apply

const path = require('path');
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

const CAMPOS_VIEJOS = [
  'VENCIMIENTO_ART',
  'ARCHIVO_ART',
  'VENCIMIENTO_931',
  'ARCHIVO_931',
  'VENCIMIENTO_SEGURO_DE_VIDA',
  'ARCHIVO_SEGURO_DE_VIDA',
  'VENCIMIENTO_LIBRE_DE_DEUDA_SINDICAL',
  'ARCHIVO_LIBRE_DE_DEUDA_SINDICAL',
];

(async () => {
  const apply = process.argv.includes('--apply');
  const dry = process.argv.includes('--dry-run');
  if (!apply && !dry) {
    console.log('Pasale --dry-run o --apply.');
    process.exit(1);
  }

  const snap = await db.collection('EMPLEADOS').get();
  console.log(`Total empleados: ${snap.size}`);

  let conCamposViejos = 0;
  let totalCamposABorrar = 0;
  const updates = [];

  for (const d of snap.docs) {
    const data = d.data();
    const campos = CAMPOS_VIEJOS.filter((c) => data[c] !== undefined);
    if (campos.length === 0) continue;
    conCamposViejos++;
    totalCamposABorrar += campos.length;
    updates.push({
      docId: d.id,
      nombre: (data.NOMBRE || '').toString().trim() || '(sin nombre)',
      campos,
    });
  }

  console.log(`Empleados con campos viejos: ${conCamposViejos}`);
  console.log(`Total campos a borrar: ${totalCamposABorrar}`);
  console.log('');
  for (const u of updates.slice(0, 10)) {
    console.log(`  - ${u.docId} (${u.nombre}): ${u.campos.join(', ')}`);
  }
  if (updates.length > 10) {
    console.log(`  ... y ${updates.length - 10} más`);
  }

  if (dry || updates.length === 0) {
    console.log('\nDRY-RUN — no se modificó nada. Para aplicar: --apply');
    process.exit(0);
  }

  // Borramos en batches de 500 (límite Firestore).
  let aplicados = 0;
  for (let i = 0; i < updates.length; i += 500) {
    const batch = db.batch();
    for (const u of updates.slice(i, i + 500)) {
      const ref = db.collection('EMPLEADOS').doc(u.docId);
      const updatePayload = {};
      for (const c of u.campos) {
        updatePayload[c] = admin.firestore.FieldValue.delete();
      }
      batch.update(ref, updatePayload);
    }
    await batch.commit();
    aplicados += Math.min(500, updates.length - i);
    console.log(`  Updates ${aplicados}/${updates.length}`);
  }
  console.log(`\nOK. ${updates.length} empleados limpiados, ${totalCamposABorrar} campos borrados.`);
})().catch((e) => {
  console.error('Error:', e);
  process.exit(1);
});
