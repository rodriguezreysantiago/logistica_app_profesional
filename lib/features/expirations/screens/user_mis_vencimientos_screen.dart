import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../revisions/services/revision_service.dart';
import '../../../shared/utils/formatters.dart';
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

  @override
  void initState() {
    super.initState();
    _empleadoStream = FirebaseFirestore.instance
        .collection('EMPLEADOS')
        .doc(widget.dniUser)
        .snapshots();
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.greenAccent),
      ),
    );

    try {
      await tarea();
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(mensajeExito,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Colors.redAccent,
      ));
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
                inputFormatters: [_FechaInputFormatter()],
                validator: (value) =>
                    (value == null || value.length < 10)
                        ? 'Fecha incompleta'
                        : null,
              ),
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
                  _enviar(
                    etiqueta: etiqueta,
                    campo: campo,
                    archivo: File(img.path),
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
                final res = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: const ['pdf', 'jpg', 'png', 'jpeg'],
                );
                if (sCtx.mounted) Navigator.pop(sCtx);
                if (res != null && res.files.single.path != null) {
                  _enviar(
                    etiqueta: etiqueta,
                    campo: campo,
                    archivo: File(res.files.single.path!),
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
    required File archivo,
    required String fecha,
    required String idDoc,
    required String coleccion,
    required String nombreUsuario,
  }) {
    _ejecutarTarea(
      tarea: () async => _revisionService.registrarSolicitud(
        dni: idDoc,
        nombreUsuario: nombreUsuario,
        etiqueta: etiqueta,
        campo: campo,
        archivo: archivo,
        fechaS: fecha,
        coleccionDestino: coleccion,
      ),
      mensajeExito: 'Solicitud enviada. Aguarde aprobación de la oficina.',
    );
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

          final data = snapshot.data!.data() as Map<String, dynamic>;
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
                titulo: 'Psicofísico (LINTI)',
                fecha: data['VENCIMIENTO_PSICOFISICO'],
                campo: 'VENCIMIENTO_PSICOFISICO',
                urlArchivo: data['ARCHIVO_PSICOFISICO'],
                idDoc: widget.dniUser,
                onUpload: () => _iniciarTramite(
                  etiqueta: 'PSICOFÍSICO',
                  campo: 'VENCIMIENTO_PSICOFISICO',
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
        final vData = vSnap.data!.data() as Map<String, dynamic>;

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
              _CardVencimientoUser(
                titulo: 'RTO / VTV',
                fecha: vData['VENCIMIENTO_RTO'],
                campo: 'VENCIMIENTO_RTO',
                urlArchivo: vData['ARCHIVO_RTO'],
                idDoc: patente,
                onUpload: () => onTramiteVehiculo(
                  etiqueta: 'RTO',
                  campo: 'VENCIMIENTO_RTO',
                  idDoc: patente,
                  coleccion: 'VEHICULOS',
                  nombreUsuario: nombreChofer,
                ),
              ),
              _CardVencimientoUser(
                titulo: 'Seguro de unidad',
                fecha: vData['VENCIMIENTO_SEGURO'],
                campo: 'VENCIMIENTO_SEGURO',
                urlArchivo: vData['ARCHIVO_SEGURO'],
                idDoc: patente,
                onUpload: () => onTramiteVehiculo(
                  etiqueta: 'SEGURO',
                  campo: 'VENCIMIENTO_SEGURO',
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

// =============================================================================
// FORMATTER DEL CAMPO DE FECHA
// =============================================================================

class _FechaInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 8) text = text.substring(0, 8);
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if ((i == 1 || i == 3) && i != text.length - 1) {
        buffer.write('/');
      }
    }
    final stringFinal = buffer.toString();
    return TextEditingValue(
      text: stringFinal,
      selection: TextSelection.collapsed(offset: stringFinal.length),
    );
  }
}
