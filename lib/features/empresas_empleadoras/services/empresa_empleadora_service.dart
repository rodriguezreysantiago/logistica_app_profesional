// Service para los documentos laborales que viven a NIVEL EMPRESA
// (no por empleado): Póliza ART + Formulario 931.
//
// Cada empresa es un doc en EMPRESAS_EMPLEADORAS con docId = CUIT. La
// pantalla admin (admin_empresas_empleadoras_screen) usa este service
// para subir/reemplazar archivo y editar fecha. Los empleados acceden
// read-only desde MIS VENCIMIENTOS.
//
// Paralelo deliberado a `EmpleadoActions.documento` pero sobre otra
// colección y sin lógica de revisiones (las pólizas las carga ADMIN
// directamente, no pasan por flujo de aprobación).

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/constants/app_constants.dart';

class EmpresaEmpleadoraService {
  EmpresaEmpleadoraService._();

  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  /// Stream del doc de la empresa. Si no existe, el caller debe poder
  /// manejar `data() == null` (la pantalla admin auto-seedea con un
  /// `set(... merge: true)` cuando el admin hace el primer cambio).
  static Stream<DocumentSnapshot<Map<String, dynamic>>> stream(String cuit) {
    return _db
        .collection(AppCollections.empresasEmpleadoras)
        .doc(cuit)
        .snapshots();
  }

  /// Get one-shot — útil para queries puntuales (notificaciones,
  /// reportes Excel, etc.).
  static Future<DocumentSnapshot<Map<String, dynamic>>> getOnce(
      String cuit) {
    return _db
        .collection(AppCollections.empresasEmpleadoras)
        .doc(cuit)
        .get();
  }

  /// Setea/actualiza la fecha de vencimiento de un campo
  /// (`VENCIMIENTO_POLIZA_ART` o `VENCIMIENTO_FORMULARIO_931`). Usa
  /// `set(merge: true)` para crear el doc si no existe — la primera
  /// vez que el admin carga los datos de una empresa nueva.
  static Future<void> actualizarFecha({
    required String cuit,
    required String campoFecha,
    required String fechaIso,
    required String? actualizadoPorDni,
  }) async {
    final ref = _db
        .collection(AppCollections.empresasEmpleadoras)
        .doc(cuit);
    final info = AppEmpresasEmpleadoras.infoPorCuit(cuit);
    await ref.set({
      'cuit': cuit,
      if (info != null) 'nombre': info.nombre,
      campoFecha: fechaIso,
      'actualizado_en': FieldValue.serverTimestamp(),
      if (actualizadoPorDni != null && actualizadoPorDni.isNotEmpty)
        'actualizado_por_dni': actualizadoPorDni,
    }, SetOptions(merge: true));
  }

  /// Sube el archivo a Storage y guarda la URL pública en
  /// `ARCHIVO_*`. Si había un archivo viejo en ese campo, lo borra
  /// best-effort para no acumular basura en Storage (mismo patrón que
  /// `EmpleadoActions._subirArchivo`).
  static Future<String> subirArchivo({
    required String cuit,
    required String campoUrl,
    required Uint8List bytes,
    required String nombreOriginal,
    required String extension,
    required String? actualizadoPorDni,
  }) async {
    final ref = _db
        .collection(AppCollections.empresasEmpleadoras)
        .doc(cuit);

    // Leer URL vieja antes de subir la nueva — si existe la borramos
    // después del upload exitoso (best-effort).
    String? urlVieja;
    try {
      final snap = await ref.get();
      final data = snap.data();
      final raw = data?[campoUrl]?.toString();
      if (raw != null && raw.isNotEmpty && raw != '-') {
        urlVieja = raw;
      }
    } catch (_) {/* ignore */}

    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath =
        'EMPRESAS_EMPLEADORAS/$cuit/${campoUrl}_$ts.$extension';
    final storageRef = _storage.ref(storagePath);
    await storageRef.putData(bytes);
    final url = await storageRef.getDownloadURL();

    final info = AppEmpresasEmpleadoras.infoPorCuit(cuit);
    await ref.set({
      'cuit': cuit,
      if (info != null) 'nombre': info.nombre,
      campoUrl: url,
      'actualizado_en': FieldValue.serverTimestamp(),
      if (actualizadoPorDni != null && actualizadoPorDni.isNotEmpty)
        'actualizado_por_dni': actualizadoPorDni,
    }, SetOptions(merge: true));

    if (urlVieja != null) {
      // Best-effort cleanup: si la URL vieja no es de Firebase Storage
      // o fue borrada manualmente, no fallamos.
      // ignore: unawaited_futures
      _storage.refFromURL(urlVieja).delete().catchError((_) {});
    }

    return url;
  }
}
