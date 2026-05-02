// =============================================================================
// COMPONENTES VISUALES de "mis vencimientos" — extraídos para mantener
// navegable el screen principal. Comparten privacidad via `part of`.
// =============================================================================

part of 'user_mis_vencimientos_screen.dart';

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
          // .toLocal() defensivo: Timestamp.toDate() en Dart suele
          // devolver local pero no esta garantizado en todos los runtimes.
          // Sin esto, format en zonas UTC podria mostrar dia anterior.
          final fechaDoc =
              (snap.data!.docs.first['FECHA'] as Timestamp).toDate().toLocal();
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
    } catch (e, s) {
      if (mounted) {
        setState(() => _procesando = false);
        AppFeedback.errorTecnicoOn(
          messenger,
          usuario: 'No pude leer la fecha de la foto. Tipeala a mano abajo.',
          tecnico: e,
          stack: s,
        );
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
