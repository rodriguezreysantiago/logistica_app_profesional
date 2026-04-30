import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
// `flutter/services` exporta los TextInputFormatter usados por
// `_DatoEditableTexto` (DigitOnlyFormatter hereda de ahí).
import 'package:flutter/services.dart';

import '../../../shared/utils/digit_only_formatter.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/phone_formatter.dart';
import '../../../shared/widgets/app_widgets.dart';

import '../services/empleado_actions.dart';
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
        // El tooltip ayuda en desktop (hover) y a screen readers — el
        // label "NUEVO" del FAB es ambiguo sin contexto fuera del título.
        tooltip: 'Agregar nuevo chofer',
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
    final apodo = (data['APODO'] ?? '').toString().trim();
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
                      child: RichText(
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          children: [
                            TextSpan(text: nombre),
                            if (apodo.isNotEmpty)
                              TextSpan(
                                text: '  ($apodo)',
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
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

/// Wrapper público para abrir la ficha del chofer desde otros features
/// (ej. el CommandPalette / búsqueda Ctrl+K).
///
/// `_DetalleChofer.abrir` es privado por convención del archivo; este
/// alias top-level expone el mismo flujo sin filtrar el detalle interno.
Future<void> abrirDetalleChofer(BuildContext context, String dni) =>
    _DetalleChofer.abrir(context, dni);

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
          // DNI: solo dígitos. Si el admin pega "12.345.678" desde un
          // sheet u otro lado, el formatter lo limpia.
          inputFormatters: [DigitOnlyFormatter(maxLength: 8)],
          keyboardType: TextInputType.number,
          aplicarMayusculas: false,
          onSave: (v) => EmpleadoActions.dato(context, dni, 'DNI', v),
        ),
        _DatoEditableTexto(
          etiqueta: 'CUIL',
          valor: AppFormatters.formatearCUIL(data['CUIL'] ?? '-'),
          inputFormatters: [DigitOnlyFormatter(maxLength: 11)],
          keyboardType: TextInputType.number,
          aplicarMayusculas: false,
          // El AppFormatters muestra "20-12345678-9" pero guardamos crudo.
          onSave: (v) => EmpleadoActions.dato(
              context, dni, 'CUIL', v.replaceAll('-', '')),
        ),
        _DatoEditableTexto(
          etiqueta: 'MAIL',
          valor: (data['MAIL'] ?? '-').toString(),
          keyboardType: TextInputType.emailAddress,
          // El mail va lowercase, no en MAYÚSCULAS como los demás campos.
          aplicarMayusculas: false,
          onSave: (v) =>
              EmpleadoActions.dato(context, dni, 'MAIL', v.toLowerCase()),
        ),
        _DatoEditableTexto(
          etiqueta: 'APODO',
          // Mostramos lo cargado, o '-' si está vacío (visualmente
          // indica al admin que falta cargar). Si el admin guarda
          // string vacío, persistimos null para distinguir "vacío
          // intencional" de "todavía no editado".
          valor: ((data['APODO'] ?? '').toString().isEmpty
              ? '-'
              : data['APODO'].toString()),
          // El apodo respeta como lo escribe el admin: "Carlos" en
          // lugar de "CARLOS" (más natural al saludar).
          aplicarMayusculas: false,
          onSave: (v) => EmpleadoActions.dato(
              context, dni, 'APODO', v.trim().isEmpty ? null : v.trim()),
        ),
        _DatoEditableTexto(
          etiqueta: 'TELÉFONO',
          // Mostramos sin el prefijo 549. El admin reconoce los números
          // por código de área (291, 11, etc), no por código de país.
          // Al guardar, paraGuardar() agrega 549 automáticamente.
          valor: PhoneFormatter.paraMostrar(data['TELEFONO']?.toString()),
          // Teléfono: solo dígitos. El admin puede tipear con/sin 549,
          // con/sin guiones, etc. — `paraGuardar` normaliza al persistir.
          inputFormatters: [DigitOnlyFormatter()],
          keyboardType: TextInputType.phone,
          aplicarMayusculas: false,
          onSave: (v) => EmpleadoActions.dato(
            context,
            dni,
            'TELEFONO',
            PhoneFormatter.paraGuardar(v),
          ),
        ),
        _DatoEditableEmpresa(
          valor: (data['EMPRESA'] ?? '-').toString(),
          onSave: (v) => EmpleadoActions.dato(context, dni, 'EMPRESA', v),
        ),

        const Divider(color: Colors.white10),
        const _SectionTitle(
            icon: Icons.folder_shared, label: 'Vencimientos críticos'),
        _FilaVencimiento(
          dni: dni,
          etiqueta: 'LICENCIA DE CONDUCIR',
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
                onTap: () => EmpleadoActions.fotoPerfil(context, dni, urlPerfil),
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
  /// Formatters opcionales (ej. `DigitOnlyFormatter` para TELÉFONO).
  final List<TextInputFormatter>? inputFormatters;
  /// Tipo de teclado (default text). Útil para teléfono / mail.
  final TextInputType? keyboardType;
  /// Si es false, el dialog NO aplica `.toUpperCase()` al guardar — útil
  /// para campos como mail (lowercase) o teléfono (solo dígitos).
  final bool aplicarMayusculas;

  const _DatoEditableTexto({
    required this.etiqueta,
    required this.valor,
    required this.onSave,
    this.inputFormatters,
    this.keyboardType,
    this.aplicarMayusculas = true,
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

    String transform(String raw) {
      final t = raw.trim();
      return aplicarMayusculas ? t.toUpperCase() : t;
    }

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text('Editar $etiqueta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          // Solo aplicamos textCapitalization cuando el caller espera
          // mayúsculas — evita pisar el formatter numérico del TELÉFONO
          // o el mail en lowercase.
          textCapitalization: aplicarMayusculas
              ? TextCapitalization.characters
              : TextCapitalization.none,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
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
            onSave(transform(controller.text));
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
              onSave(transform(controller.text));
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
      onTap: () => EmpleadoActions.documento(
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
                        color: C