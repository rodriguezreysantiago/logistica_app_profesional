import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../revisions/services/revision_service.dart';
import '../../../core/constants/vencimientos_config.dart';
import '../../../core/services/notification_service.dart';
import '../../../shared/utils/app_feedback.dart';
import '../../../shared/utils/fecha_input_formatter.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/ocr_service.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../checklist/screens/user_checklist_form_screen.dart';

/// Pantalla del chofer: lista de sus vencimientos personales y de su equipo.
/// Permite iniciar trámites de renovación (subir comprobante + fecha).
class UserMisVencimientosScreen extends StatefulWidget {
  final String dniUser;
  const UserMisVencimientosScreen({super.key, required this.dniUser});

  @override
  State<UserMisVencimientosScreen> createState() =>
      _UserMisVencimientosScreenState();
}

class _UserMisVencimientosScreenState
    extends State<UserMisVencimientosScreen> {
  final RevisionService _revisionService = RevisionService();
  late final Stream<DocumentSnapshot> _empleadoStream;

  /// Documentos personales del chofer que se auditan. La clave es la
  /// etiqueta visible (la que aparece en la notificación push) y el
  /// valor es el sufijo del campo en Firestore. Replica el listado de
  /// `admin_vencimientos_choferes_screen.dart`; si en el futuro se
  /// centraliza, mover a `vencimientos_config.dart`.
  static const Map<String, String> _docsAgendables = {
    'Licencia': 'LICENCIA_DE_CONDUCIR',
    'Preocupacional': 'PREOCUPACIONAL',
    'Manejo Defensivo': 'CURSO_DE_MANEJO_DEFENSIVO',
    'ART': 'ART',
    'F. 931': '931',
    'Seguro de Vida': 'SEGURO_DE_VIDA',
    'Sindicato': 'LIBRE_DE_DEUDA_SINDICAL',
  };

  @override
  void initState() {
    super.initState();
    _empleadoStream = FirebaseFirestore.instance
        .collection('EMPLEADOS')
        .doc(widget.dniUser)
        .snapshots();
    // Cuando el chofer abre la pantalla, reagendamos sus recordatorios
    // push locales (cancela los viejos primero para no acumular avisos
    // de papeles ya renovados). Es fire-and-forget: si falla el
    // permiso o la plataforma no soporta, no afecta la pantalla.
    unawaited(_reagendarRecordatoriosLocales());
  }

  Future<void> _reagendarRecordatoriosLocales() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('EMPLEADOS')
          .doc(widget.dniUser)
          .get();
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;

      final avisos = <VencimientoAviso>[];
      final hoy = DateTime.now();
      _docsAgendables.forEach((etiqueta, campoBase) {
        final fechaStr = data['VENCIMIENTO_$campoBase']?.toString();
        if (fechaStr == null || fechaStr.isEmpty) return;
        final fecha = DateTime.tryParse(fechaStr);
        if (fecha == null) return;
        // Solo agendamos si el vencimiento es futuro — los pasados ya
        // perdieron sentido de aviso preventivo.
        if (fecha.isBefore(hoy)) return;
        avisos.add(VencimientoAviso(
          fecha: fecha,
          tipoDoc: etiqueta,
          campoBase: campoBase,
        ));
      });

      await NotificationService.cancelarTodosLosRecordatorios();
      if (avisos.isNotEmpty) {
        await NotificationService.agendarRecordatoriosVencimientos(avisos);
      }
    } catch (e) {
      debugPrint('No se pudieron reagendar recordatorios: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // OPERACIONES
  // ---------------------------------------------------------------------------

  Future<void> _ejecutarTarea({
    required Future<void> Function() tarea,
    required String mensajeExito,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    AppLoadingDialog.show(context);

    try {
      await tarea();
      if (!mounted) return;
      AppLoadingDialog.hide(navigator);
      AppFeedback.successOn(messenger, mensajeExito);
    } catch (e) {
      if (!mounted) return;
      AppLoadingDialog.hide(navigator);
      AppFeedback.errorOn(messenger, 'Error: $e');
    }
  }

  void _iniciarTramite({
    required String etiqueta,
    required String campo,
    required String idDoc,
    required String coleccion,
    required String nombreUsuario,
  }) {
    final fechaCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withAlpha(20)),
        ),
        title: Text(
          'Actualizar $etiqueta',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ingresá la fecha que figura en el nuevo carnet o certificado:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: fechaCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
                decoration: InputDecoration(
                  hintText: 'DD/MM/AAAA',
                  hintStyle: const TextStyle(
                      color: Colors.white24, letterSpacing: 2),
                  filled: true,
                  fillColor: Colors.black.withAlpha(80),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLength: 10,
                inputFormatters: [FechaInputFormatter()],
                validator: (value) =>
                    (value == null || value.length < 10)
                        ? 'Fecha incompleta'
                        : null,
              ),
              // Botón "Detectar fecha desde foto" — solo aparece en
              // mobile (Android/iOS), donde ML Kit funciona. El OCR es
              // best-effort: si falla, el chofer tipea como siempre.
              if (OcrService.soportado) ...[
                const SizedBox(height: 12),
                _BotonDetectarFecha(
                  onFechaDetectada: (fecha) {
                    final dd = fecha.day.toString().padLeft(2, '0');
                    final mm = fecha.month.toString().padLeft(2, '0');
                    fechaCtrl.text = '$dd/$mm/${fecha.year}';
                  },
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('CANCELAR',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final partes = fechaCtrl.text.split('/');
                final fechaS = '${partes[2]}-${partes[1]}-${partes[0]}';
                Navigator.pop(dCtx);
                _selectorArchivo(
                  etiqueta: etiqueta,
                  campo: campo,
                  fechaS: fechaS,
                  idDoc: idDoc,
                  coleccion: coleccion,
                  nombreUsuario: nombreUsuario,
                );
              }
            },
            child: const Text('CONTINUAR',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _selectorArchivo({
    required String etiqueta,
    required String campo,
    required String fechaS,
    required String idDoc,
    required String coleccion,
    required String nombreUsuario,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sCtx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(25)),
          border: const Border(
              top: BorderSide(color: Colors.greenAccent, width: 2)),
        ),
        child: SafeArea(
          child: Wrap(children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'FOTO DEL COMPROBANTE',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white70),
              title: const Text('Tomar con la cámara',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500)),
              onTap: () async {
                final img = await ImagePicker()
                    .pickImage(source: ImageSource.camera, imageQuality: 50);
                if (sCtx.mounted) Navigator.pop(sCtx);
                if (img != null) {
                  // readAsBytes() es cross-platform — funciona en Web, donde
                  // img.path es un blob URL no abrible como File.
                  final bytes = await img.readAsBytes();
                  _enviar(
                    etiqueta: etiqueta,
                    campo: campo,
                    archivoBytes: bytes,
                    nombreOriginal: img.name,
                    fecha: fechaS,
                    idDoc: idDoc,
                    coleccion: coleccion,
                    nombreUsuario: nombreUsuario,
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.white70),
              title: const Text('Cargar foto o PDF de la galería',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500)),
              onTap: () async {
                // withData: true asegura que `bytes` venga poblado en todas
                // las plataformas (en Web `path` no existe).
                final res = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: const ['pdf', 'jpg', 'png', 'jpeg'],
                  withData: true,
                );
                if (sCtx.mounted) Navigator.pop(sCtx);
                final picked = res?.files.singleOrNull;
                if (picked != null && picked.bytes != null) {
                  _enviar(
                    etiqueta: etiqueta,
                    campo: campo,
                    archivoBytes: picked.bytes!,
                    nombreOriginal: picked.name,
                    fecha: fechaS,
                    idDoc: idDoc,
                    coleccion: coleccion,
                    nombreUsuario: nombreUsuario,
                  );
                }
              },
            ),
            const SizedBox(height: 25),
          ]),
        ),
      ),
    );
  }

  void _enviar({
    required String etiqueta,
    required String campo,
    required Uint8List archivoBytes,
    required String nombreOriginal,
    required String fecha,
    required String idDoc,
    required String coleccion,
    required String nombreUsuario,
  }) {
    // _ejecutarTarea devuelve Future<void>; lo descartamos explícito
    // por consistencia con el resto del código y por si en el futuro
    // _enviar pasa a ser async (el lint dispararía).
    unawaited(_ejecutarTarea(
      tarea: () async => _revisionService.registrarSolicitud(
        dni: idDoc,
        nombreUsuario: nombreUsuario,
        etiqueta: etiqueta,
        campo: campo,
        archivoBytes: archivoBytes,
        nombreOriginal: nombreOriginal,
        fechaS: fecha,
        coleccionDestino: coleccion,
      ),
      mensajeExito: 'Solicitud enviada. Aguarde aprobación de la oficina.',
    ));
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Mis Vencimientos',
      body: StreamBuilder<DocumentSnapshot>(
        stream: _empleadoStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingState();
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const AppErrorState(
              title: 'No se encontraron tus datos',
            );
          }

          // Cast defensivo: si el documento llegara con un shape
          // distinto al esperado, mostramos error en lugar de crash.
          final raw = snapshot.data!.data();
          if (raw is! Map<String, dynamic>) {
            return const AppErrorState(
              title: 'Datos corruptos',
              subtitle:
                  'El formato de tu legajo no es válido. Contactá a la oficina.',
            );
          }
          final data = raw;
          final nombreChofer = (data['NOMBRE'] ?? 'Chofer').toString();
          final pVehiculo = (data['VEHICULO'] ?? '').toString().trim();
          final pEnganche = (data['ENGANCHE'] ?? '').toString().trim();

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: [
              const _SectionHeader('LICENCIAS Y CARNETS'),
              _CardVencimientoUser(
                titulo: 'Licencia de Conducir',
                fecha: data['VENCIMIENTO_LICENCIA_DE_CONDUCIR'],
                campo: 'VENCIMIENTO_LICENCIA_DE_CONDUCIR',
                urlArchivo: data['ARCHIVO_LICENCIA_DE_CONDUCIR'],
                idDoc: widget.dniUser,
                onUpload: () => _iniciarTramite(
                  etiqueta: 'LICENCIA',
                  campo: 'VENCIMIENTO_LICENCIA_DE_CONDUCIR',
                  idDoc: widget.dniUser,
                  coleccion: 'EMPLEADOS',
                  nombreUsuario: nombreChofer,
                ),
              ),
              _CardVencimientoUser(
                titulo: 'Preocupacional',
                fecha: data['VENCIMIENTO_PREOCUPACIONAL'],
                campo: 'VENCIMIENTO_PREOCUPACIONAL',
                urlArchivo: data['ARCHIVO_PREOCUPACIONAL'],
                idDoc: widget.dniUser,
                onUpload: () => _iniciarTramite(
                  etiqueta: 'PREOCUPACIONAL',
                  campo: 'VENCIMIENTO_PREOCUPACIONAL',
                  idDoc: widget.dniUser,
                  coleccion: 'EMPLEADOS',
                  nombreUsuario: nombreChofer,
                ),
              ),
              _CardVencimientoUser(
                titulo: 'Manejo Defensivo',
                fecha: data['VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO'],
                campo: 'VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO',
                urlArchivo: data['ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO'],
                idDoc: widget.dniUser,
                onUpload: () => _iniciarTramite(
                  etiqueta: 'CURSO MANEJO',
                  campo: 'VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO',
                  idDoc: widget.dniUser,
                  coleccion: 'EMPLEADOS',
                  nombreUsuario: nombreChofer,
                ),
              ),
              const SizedBox(height: 20),

              const _SectionHeader('COBERTURAS LABORALES'),
              _CardVencimientoUser(
                titulo: 'Certificado ART',
                fecha: data['VENCIMIENTO_ART'],
                campo: 'VENCIMIENTO_ART',
                urlArchivo: data['ARCHIVO_ART'],
                idDoc: widget.dniUser,
                onUpload: () => _iniciarTramite(
                  etiqueta: 'ART',
                  campo: 'VENCIMIENTO_ART',
                  idDoc: widget.dniUser,
                  coleccion: 'EMPLEADOS',
                  nombreUsuario: nombreChofer,
                ),
              ),
              const SizedBox(height: 20),

              const _SectionHeader('PAPELES Y CONTROLES DEL EQUIPO'),
              if (pVehiculo.isNotEmpty && pVehiculo != '-')
                _DetalleEquipo(
                  patente: pVehiculo,
                  tipo: 'CAMIÓN',
                  nombreChofer: nombreChofer,
                  onTramiteVehiculo: _iniciarTramite,
                )
              else
                const _CardInformativa(
                    'No tenés un camión asignado'),
              const SizedBox(height: 12),
              if (pEnganche.isNotEmpty && pEnganche != '-')
                _DetalleEquipo(
                  patente: pEnganche,
                  tipo: 'ENGANCHE',
                  nombreChofer: nombreChofer,
                  onTramiteVehiculo: _iniciarTramite,
                )
              else
                const _CardInformativa(
                    'No tenés batea/tolva asignada'),
              const SizedBox(height: 30),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// COMPONENTES INTERNOS
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 5),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.greenAccent,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

/// Card de vencimiento del chofer.
/// Muestra el estado (ok/crítico/vencido/en revisión) y permite iniciar
/// un trámite de renovación o ver el archivo actual.
class _CardVencimientoUser extends StatelessWidget {
  final String titulo;
  final dynamic fecha;
  final String campo;
  final String idDoc;
  final String? urlArchivo;
  final VoidCallback onUpload;

  const _CardVencimientoUser({
    required this.titulo,
    required this.fecha,
    required this.campo,
    required this.idDoc,
    required this.urlArchivo,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('REVISIONES')
          .where('dni', isEqualTo: idDoc)
          .where('campo', isEqualTo: campo)
          .snapshots(),
      builder: (context, snap) {
        final enRevision = snap.hasData && snap.data!.docs.isNotEmpty;

        return AppCard(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          highlighted: enRevision,
          borderColor: enRevision ? Colors.orangeAccent.withAlpha(150) : null,
          child: Row(
            children: [
              AppFileThumbnail(
                url: urlArchivo,
                tituloVisor: '$titulo - $idDoc',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      enRevision
                          ? 'Validación pendiente...'
                          : 'Vence: ${AppFormatters.formatearFecha(fecha)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: enRevision
                            ? Colors.orangeAccent
                            : Colors.white60,
                        fontWeight: enRevision
                            ? FontWeight.bold
                            : FontWeight.normal,
                        letterSpacing: enRevision ? 1 : 0,
                      ),
                    ),
                  ],
                ),
              ),
              if (!enRevision) ...[
                VencimientoBadge(fecha: fecha),
                const SizedBox(width: 8),
                _BotonUpload(onTap: onUpload),
              ] else
                const Icon(Icons.hourglass_top,
                    color: Colors.orangeAccent, size: 20),
            ],
          ),
        );
      },
    );
  }
}

class _BotonUpload extends StatelessWidget {
  final VoidCallback onTap;
  const _BotonUpload({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(50),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.upload_file,
              color: Colors.white70, size: 18),
        ),
      ),
    );
  }
}

class _CardInformativa extends StatelessWidget {
  final String mensaje;
  const _CardInformativa(this.mensaje);

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      margin: EdgeInsets.zero,
      child: Text(
        mensaje,
        style: const TextStyle(
          color: Colors.white54,
          fontStyle: FontStyle.italic,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Card del equipo (camión o enganche) con sus vencimientos + acceso al
/// checklist mensual.
class _DetalleEquipo extends StatelessWidget {
  final String patente;
  final String tipo;
  final String nombreChofer;
  final void Function({
    required String etiqueta,
    required String campo,
    required String idDoc,
    required String coleccion,
    required String nombreUsuario,
  }) onTramiteVehiculo;

  const _DetalleEquipo({
    required this.patente,
    required this.tipo,
    required this.nombreChofer,
    required this.onTramiteVehiculo,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('VEHICULOS')
          .doc(patente)
          .snapshots(),
      builder: (context, vSnap) {
        if (!vSnap.hasData || !vSnap.data!.exists) {
          return _CardInformativa('Unidad $patente no registrada');
        }
        // Cast defensivo (mismo patrón que en el snapshot del empleado).
        final vRaw = vSnap.data!.data();
        if (vRaw is! Map<String, dynamic>) {
          return _CardInformativa('Datos de $patente corruptos');
        }
        final vData = vRaw;

        return AppCard(
          padding: const EdgeInsets.all(16),
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10, left: 5),
                child: Text(
                  '$tipo: $patente',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              // Vencimientos del vehículo: tractor (4) o enganche (2),
              // según AppVencimientos. La etiqueta para iniciar trámite
              // es la parte del campo después de VENCIMIENTO_ (ej.
              // "RTO", "SEGURO", "EXTINTOR_CABINA"), que usa el sistema
              // de revisiones para mapear de vuelta al ARCHIVO_ correcto.
              for (final spec in AppVencimientos.forTipo(
                  vData['TIPO']?.toString() ?? tipo))
                _CardVencimientoUser(
                  titulo: spec.etiqueta,
                  fecha: vData[spec.campoFecha],
                  campo: spec.campoFecha,
                  urlArchivo: vData[spec.campoArchivo],
                  idDoc: patente,
                  onUpload: () => onTramiteVehiculo(
                    etiqueta: spec.etiqueta.toUpperCase(),
                    campo: spec.campoFecha,
                    idDoc: patente,
                    coleccion: 'VEHICULOS',
                    nombreUsuario: nombreChofer,
                  ),
                ),
              const SizedBox(height: 8),
              _AccesoChecklist(patente: patente, tipoLabel: tipo),
            ],
          ),
        );
      },
    );
  }
}

/// Card de acceso al checklist mensual del chofer (con estado visible).
class _AccesoChecklist extends StatelessWidget {
  final String patente;
  final String tipoLabel;

  const _AccesoChecklist({required this.patente, required this.tipoLabel});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final tipoChecklist = tipoLabel == 'CAMIÓN' ? 'TRACTOR' : 'BATEA';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('CHECKLISTS')
          .where('DOMINIO', isEqualTo: patente)
          .where('MES', isEqualTo: now.month)
          .where('ANIO', isEqualTo: now.year)
          .orderBy('FECHA', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('⚠️ Error checklist: ${snap.error}');
        }

        final completado = snap.hasData && snap.data!.docs.isNotEmpty;
        final dia = now.day;

        Color color;
        String mensaje;
        IconData icono;

        if (completado) {
          color = Colors.greenAccent;
          final fechaDoc =
              (snap.data!.docs.first['FECHA'] as Timestamp).toDate();
          mensaje =
              'Control realizado (${DateFormat('dd/MM').format(fechaDoc)})';
          icono = Icons.check_circle;
        } else if (dia > 15) {
          color = Colors.redAccent;
          mensaje = 'VENCIDO: realizar control YA';
          icono = Icons.warning_amber_rounded;
        } else if (dia > 10) {
          color = Colors.orangeAccent;
          mensaje = 'Pendiente (vence el día 15)';
          icono = Icons.fact_check_outlined;
        } else {
          color = Colors.white60;
          mensaje = 'Checklist mensual pendiente';
          icono = Icons.fact_check_outlined;
        }

        return Container(
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withAlpha(60)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserChecklistFormScreen(
                    tipo: tipoChecklist,
                    patente: patente,
                  ),
                ),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(icono, color: color, size: 22),
                title: Text(
                  mensaje,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                trailing:
                    Icon(Icons.arrow_forward_ios, color: color, size: 14),
              ),
            ),
          ),
        );
      },
    );
  }
}

// El _FechaInputFormatter local se reemplazó por FechaInputFormatter
// en lib/shared/utils/fecha_input_formatter.dart (compartido).

/// Botón "Detectar fecha desde foto" — abre la cámara, corre OCR sobre
/// la imagen y, si detecta una fecha válida, llama a [onFechaDetectada]
/// para que el dialog padre la pre-cargue en el TextFormField.
///
/// Best-effort: si el OCR no encuentra nada, se muestra un snackbar
/// informativo y el chofer puede tipear la fecha manualmente.
///
/// Solo se monta cuando `OcrService.soportado` (Android/iOS).
class _BotonDetectarFecha extends StatefulWidget {
  final void Function(DateTime) onFechaDetectada;
  const _BotonDetectarFecha({required this.onFechaDetectada});

  @override
  State<_BotonDetectarFecha> createState() => _BotonDetectarFechaState();
}

class _BotonDetectarFechaState extends State<_BotonDetectarFecha> {
  bool _procesando = false;

  Future<void> _capturar() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _procesando = true);

    try {
      final picker = ImagePicker();
      final foto = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      if (foto == null) {
        if (mounted) setState(() => _procesando = false);
        return;
      }

      final fecha = await OcrService.detectarFecha(foto.path);
      if (!mounted) return;
      setState(() => _procesando = false);

      if (fecha == null) {
        AppFeedback.warningOn(messenger,
            'No se pudo detectar una fecha en la foto. Ingresala manualmente.');
        return;
      }
      widget.onFechaDetectada(fecha);
      AppFeedback.successOn(messenger,
          'Fecha detectada: ${fecha.day}/${fecha.month}/${fecha.year}');
    } catch (e) {
      if (mounted) {
        setState(() => _procesando = false);
        AppFeedback.errorOn(messenger, 'OCR falló: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: _procesando ? null : _capturar,
        style: TextButton.styleFrom(
          backgroundColor: Colors.greenAccent.withAlpha(20),
          foregroundColor: Colors.greenAccent,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.greenAccent.withAlpha(80)),
          ),
        ),
        icon: _procesando
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.greenAccent,
                ),
              )
            : const Icon(Icons.document_scanner_outlined, size: 18),
        label: Text(
          _procesando
              ? 'Analizando comprobante...'
              : 'Detectar fecha desde foto',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
