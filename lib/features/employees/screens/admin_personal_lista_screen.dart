import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/fecha_dialog.dart';

import 'admin_personal_form_screen.dart';

/// Pantalla de Gestión de Personal.
///
/// Migrada al sistema de diseño unificado:
/// AppScaffold + AppListPage + AppCard + AppDetailSheet +
/// VencimientoBadge + AppFileThumbnail.
class AdminPersonalListaScreen extends StatefulWidget {
  const AdminPersonalListaScreen({super.key});

  @override
  State<AdminPersonalListaScreen> createState() =>
      _AdminPersonalListaScreenState();
}

class _AdminPersonalListaScreenState
    extends State<AdminPersonalListaScreen> {
  // Stream cacheado para evitar lecturas duplicadas al buscar/refrescar.
  late final Stream<QuerySnapshot> _empleadosStream;

  @override
  void initState() {
    super.initState();
    _empleadosStream = FirebaseFirestore.instance
        .collection('EMPLEADOS')
        .orderBy('NOMBRE')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Gestión de Personal',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AdminPersonalFormScreen(),
          ),
        ),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('NUEVO'),
      ),
      body: AppListPage(
        stream: _empleadosStream,
        searchHint: 'Buscar por nombre, tractor o enganche...',
        emptyTitle: 'Sin choferes cargados',
        emptySubtitle: 'Tocá el botón + para agregar uno',
        emptyIcon: Icons.badge_outlined,
        filter: (doc, q) {
          final data = doc.data() as Map<String, dynamic>;
          final hay = '${data['NOMBRE'] ?? ''} '
                  '${data['VEHICULO'] ?? ''} ${data['ENGANCHE'] ?? ''} '
                  '${doc.id}'
              .toUpperCase();
          return hay.contains(q);
        },
        itemBuilder: (ctx, doc) => _EmpleadoCard(doc: doc),
      ),
    );
  }
}

// =============================================================================
// CARD DE LA LISTA (vista colapsada)
// =============================================================================

class _EmpleadoCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _EmpleadoCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final dni = doc.id;
    final nombre = (data['NOMBRE'] ?? 'Sin nombre').toString();
    final rol = (data['ROL'] ?? 'USUARIO').toString();
    final tractor = (data['VEHICULO'] ?? '-').toString();
    final enganche = (data['ENGANCHE'] ?? '-').toString();
    final urlPerfil = data['ARCHIVO_PERFIL']?.toString();
    final tieneFoto =
        urlPerfil != null && urlPerfil.isNotEmpty && urlPerfil != '-';

    return AppCard(
      onTap: () => _DetalleChofer.abrir(context, dni),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white12,
            backgroundImage: tieneFoto ? NetworkImage(urlPerfil) : null,
            child: !tieneFoto
                ? const Icon(Icons.person, color: Colors.white54)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (rol.toUpperCase() == 'ADMIN')
                      _RolBadge(rol: rol),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.local_shipping,
                        size: 11, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text(
                      tractor,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.link, size: 11, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text(
                      enganche,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white24),
        ],
      ),
    );
  }
}

class _RolBadge extends StatelessWidget {
  final String rol;
  const _RolBadge({required this.rol});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.redAccent.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.redAccent.withAlpha(80)),
      ),
      child: Text(
        rol.toUpperCase(),
        style: const TextStyle(
          color: Colors.redAccent,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// =============================================================================
// DETALLE DEL CHOFER (bottom sheet)
// =============================================================================

class _DetalleChofer extends StatelessWidget {
  final String dni;
  final ScrollController scrollController;
  const _DetalleChofer({required this.dni, required this.scrollController});

  /// Helper para abrir el detalle desde cualquier parte.
  static Future<void> abrir(BuildContext context, String dni) {
    return AppDetailSheet.show(
      context: context,
      title: 'Ficha del chofer',
      icon: Icons.badge,
      builder: (sheetCtx, scrollCtl) =>
          _DetalleChofer(dni: dni, scrollController: scrollCtl),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('EMPLEADOS')
          .doc(dni)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const AppLoadingState();
        if (!snap.data!.exists) {
          return const AppErrorState(
            title: 'Empleado no encontrado',
            subtitle: 'Puede haber sido eliminado.',
          );
        }
        final data = snap.data!.data() as Map<String, dynamic>;
        return _buildBody(context, data);
      },
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> data) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        _HeaderDetalle(dni: dni, data: data),
        const SizedBox(height: 20),
        const Divider(color: Colors.white10),

        const _SectionTitle(icon: Icons.badge, label: 'Documentación personal'),
        _DatoEditableTexto(
          etiqueta: 'DNI',
          valor: dni,
          onSave: (v) => _Actualizar.dato(context, dni, 'DNI', v),
        ),
        _DatoEditableTexto(
          etiqueta: 'CUIL',
          valor: AppFormatters.formatearCUIL(data['CUIL'] ?? '-'),
          onSave: (v) => _Actualizar.dato(
              context, dni, 'CUIL', v.replaceAll('-', '')),
        ),
        _DatoEditableTexto(
          etiqueta: 'MAIL',
          valor: (data['MAIL'] ?? '-').toString(),
          // El mail se guarda en minúsculas; pisamos el toUpperCase() del
          // dialog estándar dejando el valor crudo.
          onSave: (v) => _Actualizar.dato(
              context, dni, 'MAIL', v.toLowerCase().trim()),
        ),
        _DatoEditableTexto(
          etiqueta: 'TELÉFONO',
          valor: (data['TELEFONO'] ?? '-').toString(),
          // Solo guardamos los dígitos sin trim de mayúsculas (el dialog
          // por default lo aplica). El normalizador de WhatsApp ya tolera
          // espacios y guiones, pero si lo dejamos limpio mejor.
          onSave: (v) => _Actualizar.dato(
              context, dni, 'TELEFONO', v.trim()),
        ),
        _DatoEditableEmpresa(
          valor: (data['EMPRESA'] ?? '-').toString(),
          onSave: (v) => _Actualizar.dato(context, dni, 'EMPRESA', v),
        ),

        const Divider(color: Colors.white10),
        const _SectionTitle(
            icon: Icons.folder_shared, label: 'Vencimientos críticos'),
        _FilaVencimiento(
          dni: dni,
          etiqueta: 'LICENCIA',
          campoFecha: 'VENCIMIENTO_LICENCIA_DE_CONDUCIR',
          campoUrl: 'ARCHIVO_LICENCIA_DE_CONDUCIR',
          data: data,
        ),
        _FilaVencimiento(
          dni: dni,
          etiqueta: 'PREOCUPACIONAL',
          campoFecha: 'VENCIMIENTO_PREOCUPACIONAL',
          campoUrl: 'ARCHIVO_PREOCUPACIONAL',
          data: data,
        ),
        _FilaVencimiento(
          dni: dni,
          etiqueta: 'MANEJO DEFENSIVO',
          campoFecha: 'VENCIMIENTO_CURSO_DE_MANEJO_DEFENSIVO',
          campoUrl: 'ARCHIVO_CURSO_DE_MANEJO_DEFENSIVO',
          data: data,
        ),

        const Divider(color: Colors.white10),
        const _SectionTitle(icon: Icons.work, label: 'Seguros y aportes'),
        _FilaVencimiento(
          dni: dni,
          etiqueta: 'ART',
          campoFecha: 'VENCIMIENTO_ART',
          campoUrl: 'ARCHIVO_ART',
          data: data,
        ),
        _FilaVencimiento(
          dni: dni,
          etiqueta: 'F. 931',
          campoFecha: 'VENCIMIENTO_931',
          campoUrl: 'ARCHIVO_931',
          data: data,
        ),
        _FilaVencimiento(
          dni: dni,
          etiqueta: 'SEGURO VIDA',
          campoFecha: 'VENCIMIENTO_SEGURO_DE_VIDA',
          campoUrl: 'ARCHIVO_SEGURO_DE_VIDA',
          data: data,
        ),

        const Divider(color: Colors.white10),
        const _SectionTitle(
            icon: Icons.local_shipping, label: 'Asignación de unidades'),
        _AsignacionUnidad(
          dni: dni,
          campo: 'VEHICULO',
          label: 'Tractor',
          actual: (data['VEHICULO'] ?? '').toString(),
        ),
        _AsignacionUnidad(
          dni: dni,
          campo: 'ENGANCHE',
          label: 'Enganche',
          actual: (data['ENGANCHE'] ?? '').toString(),
        ),

        const SizedBox(height: 30),
      ],
    );
  }
}

// =============================================================================
// HEADER DEL DETALLE (foto + nombre)
// =============================================================================

class _HeaderDetalle extends StatelessWidget {
  final String dni;
  final Map<String, dynamic> data;
  const _HeaderDetalle({required this.dni, required this.data});

  @override
  Widget build(BuildContext context) {
    final urlPerfil = data['ARCHIVO_PERFIL']?.toString();
    final tieneFoto =
        urlPerfil != null && urlPerfil.isNotEmpty && urlPerfil != '-';

    return Column(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.white12,
              backgroundImage: tieneFoto ? NetworkImage(urlPerfil) : null,
              child: !tieneFoto
                  ? const Icon(Icons.person, size: 50, color: Colors.white24)
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => _Actualizar.fotoPerfil(context, dni, urlPerfil),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.edit, size: 18, color: Colors.black),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          (data['NOMBRE'] ?? 'Sin nombre').toString(),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// COMPONENTES INTERNOS
// =============================================================================

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: Colors.greenAccent, size: 16),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _DatoEditableTexto extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final Function(String) onSave;

  const _DatoEditableTexto({
    required this.etiqueta,
    required this.valor,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        etiqueta,
        style: const TextStyle(fontSize: 11, color: Colors.white38),
      ),
      subtitle: Text(
        valor,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      trailing:
          const Icon(Icons.edit_note, size: 22, color: Colors.greenAccent),
      onTap: () => _mostrarDialogo(context),
    );
  }

  void _mostrarDialogo(BuildContext context) {
    // Pre-cargamos el valor actual y lo dejamos seleccionado completo. Así
    // el admin puede:
    //   - Borrar todo con un solo Delete/Backspace.
    //   - Sobreescribir directamente tipeando (reemplaza la selección).
    // Antes el cursor quedaba al final del texto y el admin tenía que
    // borrar caracter por caracter, lo que llevaba a confusión.
    final controller = TextEditingController(text: valor)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: valor.length,
      );

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text('Editar $etiqueta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Escriba aquí...',
            // Botón X para vaciar el campo de un toque.
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear, color: Colors.white54),
              tooltip: 'Vaciar campo',
              onPressed: () => controller.clear(),
            ),
          ),
          // Permite enviar con Enter sin tener que ir al botón.
          onSubmitted: (_) {
            onSave(controller.text.trim().toUpperCase());
            Navigator.pop(dCtx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              onSave(controller.text.trim().toUpperCase());
              Navigator.pop(dCtx);
            },
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
  }
}

class _DatoEditableEmpresa extends StatelessWidget {
  final String valor;
  final Function(String) onSave;

  const _DatoEditableEmpresa({required this.valor, required this.onSave});

  static const List<String> _empresas = [
    'VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)',
    'SUCESION DE VECCHI CARLOS LUIS: (20-08569424-4)',
  ];

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text(
        'EMPRESA',
        style: TextStyle(fontSize: 11, color: Colors.white38),
      ),
      subtitle: Text(
        valor,
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
      trailing: const Icon(Icons.business_center,
          size: 20, color: Colors.greenAccent),
      onTap: () => _mostrarSelector(context),
    );
  }

  void _mostrarSelector(BuildContext context) {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Seleccionar empresa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _empresas
              .map(
                (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white)),
                  onTap: () {
                    onSave(e);
                    Navigator.pop(dCtx);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _FilaVencimiento extends StatelessWidget {
  final String dni;
  final String etiqueta;
  final String campoFecha;
  final String campoUrl;
  final Map<String, dynamic> data;

  const _FilaVencimiento({
    required this.dni,
    required this.etiqueta,
    required this.campoFecha,
    required this.campoUrl,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final fecha = data[campoFecha];
    final url = data[campoUrl]?.toString();
    final tieneFecha = fecha != null && fecha.toString().isNotEmpty;

    return InkWell(
      onTap: () => _Actualizar.documento(
        context,
        dni: dni,
        etiqueta: etiqueta,
        campoFecha: campoFecha,
        campoUrl: campoUrl,
        fechaActual: fecha?.toString(),
        urlActual: url,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            AppFileThumbnail(
              url: url,
              tituloVisor: '$etiqueta - $dni',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    etiqueta,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tieneFecha
                        ? AppFormatters.formatearFecha(fecha)
                        : 'Sin fecha',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            VencimientoBadge(fecha: fecha),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}

class _AsignacionUnidad extends StatelessWidget {
  final String dni;
  final String campo;
  final String label;
  final String actual;

  const _AsignacionUnidad({
    required this.dni,
    required this.campo,
    required this.label,
    required this.actual,
  });

  @override
  Widget build(BuildContext context) {
    final tieneAsignacion =
        actual.isNotEmpty && actual != '-' && actual != 'SIN ASIGNAR';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        campo == 'VEHICULO' ? Icons.local_shipping : Icons.link,
        color: tieneAsignacion ? Colors.greenAccent : Colors.white24,
      ),
      title: Text('$label: ${tieneAsignacion ? actual : "—"}',
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      trailing:
          const Icon(Icons.sync_alt, size: 20, color: Colors.greenAccent),
      onTap: () => _Actualizar.unidad(context, dni, campo, actual),
    );
  }
}

// =============================================================================
// SERVICIOS DE ACTUALIZACIÓN — NAMESPACE _Actualizar
//
// Centraliza las operaciones que tocan Firestore/Storage. Antes estaban
// dispersas como métodos privados del state. Acá las agrupo en un namespace
// para que sean fáciles de encontrar y, en el futuro, mover a un service.
// =============================================================================

enum _FuenteArchivoChofer { camara, galeria, archivo }

class _Actualizar {
  _Actualizar._();

  /// Actualiza un campo simple en EMPLEADOS.
  static Future<void> dato(
    BuildContext context,
    String dni,
    String campo,
    dynamic valor,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('EMPLEADOS')
          .doc(dni.trim())
          .update({
        campo: valor,
        'fecha_ultima_actualizacion': FieldValue.serverTimestamp(),
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('Dato actualizado: $campo'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error al actualizar: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Abre un sheet con opciones para gestionar la foto de perfil.
  static Future<void> fotoPerfil(
    BuildContext context,
    String dni,
    String? urlActual,
  ) async {
    final picker = ImagePicker();
    final navigator = Navigator.of(context);

    // El Future de showModalBottomSheet se completa cuando el sheet
    // se cierra. Acá solo lo abrimos y nos vamos — la lógica de subir
    // la foto vive dentro de los onTap de los ListTile, no dependemos
    // del valor de retorno.
    unawaited(showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(25)),
          border: const Border(
              top: BorderSide(color: Colors.greenAccent, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Foto de perfil',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 15),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.blueAccent),
              title: const Text('Ver foto actual',
                  style: TextStyle(color: Colors.white)),
              enabled: urlActual != null &&
                  urlActual.isNotEmpty &&
                  urlActual != '-',
              onTap: () {
                navigator.pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PreviewScreen(
                      url: urlActual!,
                      titulo: 'Foto de $dni',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library,
                  color: Colors.greenAccent),
              title: const Text('Subir nueva desde galería',
                  style: TextStyle(color: Colors.white)),
              onTap: () async {
                navigator.pop();
                final image = await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 50,
                );
                if (image != null && context.mounted) {
                  await _subirArchivo(
                    context,
                    dni,
                    File(image.path),
                    'perfiles/$dni.jpg',
                    'ARCHIVO_PERFIL',
                  );
                }
              },
            ),
          ],
        ),
      ),
    ));
  }

  /// Sube un archivo físico a Storage y guarda la URL en Firestore.
  /// Detecta el contentType según la extensión (PDF, JPG, PNG).
  static Future<void> _subirArchivo(
    BuildContext context,
    String id,
    File file,
    String storagePath,
    String dbCampo,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        const SnackBar(content: Text('Subiendo archivo...')),
      );
      final ref = FirebaseStorage.instance.ref().child(storagePath);

      // Detectamos contentType según extensión para que Firebase Storage
      // lo sirva con el header correcto y el visor sepa abrirlo bien.
      final lower = storagePath.toLowerCase();
      String? contentType;
      if (lower.endsWith('.pdf')) {
        contentType = 'application/pdf';
      } else if (lower.endsWith('.png')) {
        contentType = 'image/png';
      } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
        contentType = 'image/jpeg';
      }
      final metadata =
          contentType != null ? SettableMetadata(contentType: contentType) : null;

      await ref.putFile(file, metadata);
      final downloadUrl = await ref.getDownloadURL();
      if (context.mounted) {
        await dato(context, id, dbCampo, downloadUrl);
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error al subir: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Abre un sheet para que el admin elija de dónde tomar el archivo
  /// (cámara, galería, o PDF/imagen del dispositivo) y lo sube.
  /// Pensado para reemplazar papeles del chofer (licencia, ART, etc.).
  static Future<void> _reemplazarDocumentoChofer({
    required BuildContext context,
    required String dni,
    required String etiqueta,
    required String campoUrl,
  }) async {
    final picker = ImagePicker();

    final fuente = await showModalBottomSheet<_FuenteArchivoChofer>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sCtx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(sCtx).colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(25)),
          border: const Border(
              top: BorderSide(color: Colors.greenAccent, width: 2)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  etiqueta,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ListTile(
                leading:
                    const Icon(Icons.camera_alt, color: Colors.greenAccent),
                title: const Text('Tomar foto con la cámara',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sCtx, _FuenteArchivoChofer.camara),
              ),
              ListTile(
                leading:
                    const Icon(Icons.photo_library, color: Colors.blueAccent),
                title: const Text('Foto desde la galería',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sCtx, _FuenteArchivoChofer.galeria),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf,
                    color: Colors.redAccent),
                title: const Text('PDF / archivo del dispositivo',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sCtx, _FuenteArchivoChofer.archivo),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );

    if (fuente == null) return;
    if (!context.mounted) return;

    File? archivo;
    String extension = 'jpg';

    switch (fuente) {
      case _FuenteArchivoChofer.camara:
      case _FuenteArchivoChofer.galeria:
        final source = fuente == _FuenteArchivoChofer.camara
            ? ImageSource.camera
            : ImageSource.gallery;
        final img = await picker.pickImage(source: source, imageQuality: 60);
        if (img == null) return;
        archivo = File(img.path);
        extension = 'jpg';
        break;
      case _FuenteArchivoChofer.archivo:
        final res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        );
        if (res == null || res.files.single.path == null) return;
        archivo = File(res.files.single.path!);
        extension = res.files.single.extension?.toLowerCase() ?? 'pdf';
        break;
    }

    // Después del picker viene otro await: revalidamos contra el mismo
    // BuildContext que vamos a pasar a _subirArchivo (el lint pide eso).
    if (!context.mounted) return;
    final storagePath =
        'EMPLEADOS/$dni/${campoUrl}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    await _subirArchivo(context, dni, archivo, storagePath, campoUrl);
  }

  /// Sheet con opciones para gestionar un documento (fecha + archivo).
  static void documento(
    BuildContext context, {
    required String dni,
    required String etiqueta,
    required String campoFecha,
    required String campoUrl,
    required String? fechaActual,
    required String? urlActual,
  }) {
    final navigator = Navigator.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(25)),
          border: const Border(
              top: BorderSide(color: Colors.greenAccent, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 15),
            ListTile(
              leading:
                  const Icon(Icons.calendar_today, color: Colors.blueAccent),
              title: const Text('Editar fecha de vencimiento',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                navigator.pop();
                _seleccionarFecha(context, dni, campoFecha, fechaActual);
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.greenAccent),
              title: const Text('Ver documento digital',
                  style: TextStyle(color: Colors.white)),
              enabled: urlActual != null &&
                  urlActual.isNotEmpty &&
                  urlActual != '-',
              onTap: () {
                navigator.pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PreviewScreen(
                      url: urlActual!,
                      titulo: '$etiqueta - $dni',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file,
                  color: Colors.orangeAccent),
              title: Text(
                urlActual != null &&
                        urlActual.isNotEmpty &&
                        urlActual != '-'
                    ? 'Reemplazar archivo cargado'
                    : 'Subir archivo nuevo',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Foto o PDF — sin pasar por el flujo de revisión',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              onTap: () {
                navigator.pop();
                _reemplazarDocumentoChofer(
                  context: context,
                  dni: dni,
                  etiqueta: etiqueta,
                  campoUrl: campoUrl,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _seleccionarFecha(
    BuildContext context,
    String dni,
    String campo,
    String? fechaActual,
  ) async {
    final initial = DateTime.tryParse(fechaActual ?? '');
    final picked = await pickFecha(
      context,
      initial: initial,
      titulo: 'Vencimiento ${campo.replaceAll("VENCIMIENTO_", "").replaceAll("_", " ")}',
    );
    if (picked != null && context.mounted) {
      final nuevaFecha = picked.toString().split(' ').first;
      await dato(context, dni, campo, nuevaFecha);
    }
  }

  /// Selector de unidad (tractor o enganche).
  static void unidad(
    BuildContext context,
    String dni,
    String campo,
    String patenteActual,
  ) {
    final tipos = (campo == 'VEHICULO')
        ? <String>[AppTiposVehiculo.tractor]
        : AppTiposVehiculo.enganches;

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title:
            Text("Asignar ${campo == 'VEHICULO' ? 'tractor' : 'enganche'}"),
        content: SizedBox(
          width: double.maxFinite,
          height: 350,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('VEHICULOS')
                .where('TIPO', whereIn: tipos)
                .snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                      color: Colors.greenAccent),
                );
              }

              final unidades = snap.data!.docs;

              Future<void> procesarCambio(String? nueva) async {
                final db = FirebaseFirestore.instance;
                final batch = db.batch();
                final cleanActual = patenteActual.trim();

                if (nueva != null && nueva != '-') {
                  batch.update(
                    db.collection('VEHICULOS').doc(nueva),
                    {'ESTADO': 'OCUPADO'},
                  );
                  batch.update(
                    db.collection('EMPLEADOS').doc(dni),
                    {campo: nueva},
                  );
                } else {
                  batch.update(
                    db.collection('EMPLEADOS').doc(dni),
                    {campo: '-'},
                  );
                }

                await batch.commit();

                if (cleanActual.isNotEmpty &&
                    cleanActual != '-' &&
                    cleanActual != 'S/D') {
                  try {
                    await db
                        .collection('VEHICULOS')
                        .doc(cleanActual)
                        .update({'ESTADO': 'LIBRE'});
                  } catch (_) {
                    // Unidad previa ya no existe / ya estaba libre
                  }
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              }

              return ListView.builder(
                itemCount: unidades.length + 1,
                itemBuilder: (ctx, idx) {
                  if (idx == 0) {
                    return ListTile(
                      leading:
                          const Icon(Icons.link_off, color: Colors.redAccent),
                      title: const Text(
                        'DESVINCULAR',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () => procesarCambio(null),
                    );
                  }

                  final vDoc = unidades[idx - 1];
                  final vData = vDoc.data() as Map<String, dynamic>;
                  final patente = vDoc.id.trim();

                  // Filtrar unidades ocupadas (excepto la actual del chofer)
                  if (vData['ESTADO'] == 'OCUPADO' &&
                      patente != patenteActual.trim()) {
                    return const SizedBox.shrink();
                  }

                  return ListTile(
                    title: Text(
                      patente,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                    ),
                    trailing: patente == patenteActual.trim()
                        ? const Icon(Icons.check_circle,
                            color: Colors.greenAccent)
                        : null,
                    onTap: () => procesarCambio(patente),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}