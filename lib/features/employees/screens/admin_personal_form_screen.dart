import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../shared/utils/app_feedback.dart';
import '../../../shared/utils/digit_only_formatter.dart';
import '../../../shared/utils/password_hasher.dart';
import '../../../shared/utils/upper_case_formatter.dart';
import '../../../shared/widgets/app_widgets.dart';

/// Form de alta de un nuevo legajo de personal (chofer o admin).
class AdminPersonalFormScreen extends StatefulWidget {
  const AdminPersonalFormScreen({super.key});

  @override
  State<AdminPersonalFormScreen> createState() =>
      _AdminPersonalFormScreenState();
}

class _AdminPersonalFormScreenState
    extends State<AdminPersonalFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _dniCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _cuilCtrl = TextEditingController();
  final _mailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  String _rol = 'USER';
  String _empresa =
      'VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)';
  bool _guardando = false;

  static const _empresas = [
    'VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)',
    'SUCESION DE VECCHI CARLOS LUIS: (20-08569424-4)',
  ];

  @override
  void dispose() {
    _dniCtrl.dispose();
    _nombreCtrl.dispose();
    _cuilCtrl.dispose();
    _mailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_guardando) return;

    setState(() => _guardando = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final dni = _dniCtrl.text.trim();

      // 1) Verificar que el DNI no exista
      final doc = await FirebaseFirestore.instance
          .collection('EMPLEADOS')
          .doc(dni)
          .get();

      if (!mounted) return;

      if (doc.exists) {
        AppFeedback.errorOn(messenger, 'Error: este DNI ya está registrado');
        setState(() => _guardando = false);
        return;
      }

      // 2) Crear el legajo
      // ✅ Hash Bcrypt de la contraseña inicial. El plain text NUNCA se
      //    guarda en Firestore.
      final passwordHash =
          PasswordHasher.hashBcrypt(_passCtrl.text.trim());

      await FirebaseFirestore.instance
          .collection('EMPLEADOS')
          .doc(dni)
          .set({
        'NOMBRE': _nombreCtrl.text.trim().toUpperCase(),
        'CUIL': _cuilCtrl.text.trim(),
        'MAIL': _mailCtrl.text.trim().toLowerCase(),
        'CONTRASEÑA': passwordHash,
        'ROL': _rol,
        'EMPRESA': _empresa,
        'VEHICULO': '-',
        'ENGANCHE': '-',
        'ARCHIVO_PERFIL': '-',
        'estado_cuenta': 'ACTIVO',
        'fecha_creacion': FieldValue.serverTimestamp(),
        'ultima_modificacion': FieldValue.serverTimestamp(),
      });

      // Audit log fire-and-forget: el admin ya tiene su feedback
      // visual; si falla el log, no rompemos el flujo.
      unawaited(AuditLog.registrar(
        accion: AuditAccion.crearChofer,
        entidad: 'EMPLEADOS',
        entidadId: dni,
        detalles: {
          'nombre': _nombreCtrl.text.trim().toUpperCase(),
          'rol': _rol,
          'empresa': _empresa,
        },
      ));

      // El widget puede haberse desmontado durante el await; si fue así,
      // no usamos messenger ni navigator (sus referencias quedaron stale).
      if (!mounted) return;

      AppFeedback.successOn(messenger, 'Chofer creado con éxito');
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      AppFeedback.errorOn(messenger, 'Error al guardar: $e');
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AppScaffold(
        title: 'Nuevo chofer',
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FormInput(
                  label: 'DNI (Será el usuario)',
                  controller: _dniCtrl,
                  icon: Icons.badge,
                  isNumeric: true,
                  maxLength: 8,
                ),
                _FormInput(
                  label: 'Nombre y apellido completo',
                  controller: _nombreCtrl,
                  icon: Icons.person,
                  // Nombre va en MAYÚSCULAS para uniformar la base.
                ),
                _FormInput(
                  label: 'CUIL (sin guiones)',
                  controller: _cuilCtrl,
                  icon: Icons.assignment_ind,
                  isNumeric: true,
                  maxLength: 11,
                  isCuil: true,
                ),
                _FormInput(
                  label: 'Mail (opcional)',
                  controller: _mailCtrl,
                  icon: Icons.alternate_email,
                  // El mail va tal cual lo tipea el admin (sin mayúsculas).
                  toUpperCase: false,
                  isMail: true,
                ),
                _FormInput(
                  label: 'Contraseña inicial',
                  controller: _passCtrl,
                  icon: Icons.lock_outline,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 10),
                const _CampoLabel('Empresa asignada'),
                _DropdownEmpresa(
                  value: _empresa,
                  empresas: _empresas,
                  enabled: !_guardando,
                  onChanged: (val) =>
                      setState(() => _empresa = val ?? _empresa),
                ),
                const SizedBox(height: 25),
                const _CampoLabel('Rol en el sistema'),
                const SizedBox(height: 10),
                _RoleSelector(
                  rol: _rol,
                  enabled: !_guardando,
                  onChanged: (val) => setState(() => _rol = val),
                ),
                const SizedBox(height: 40),
                _BotonGuardar(
                  guardando: _guardando,
                  onPressed: _guardar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// COMPONENTES
// =============================================================================

class _CampoLabel extends StatelessWidget {
  final String label;
  const _CampoLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _FormInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final bool isNumeric;
  final int? maxLength;
  final bool isCuil;
  final bool isMail;
  /// Si es true, el texto se transforma a MAYÚSCULAS mientras se tipea.
  /// Default true para que los campos de identificación (DNI, nombre,
  /// CUIL) queden uniformes. Antes se hacía con `textCapitalization`,
  /// pero eso rompe el Backspace en Windows desktop.
  final bool toUpperCase;
  final TextInputAction textInputAction;

  const _FormInput({
    required this.label,
    required this.controller,
    required this.icon,
    this.isNumeric = false,
    this.maxLength,
    this.isCuil = false,
    this.isMail = false,
    this.toUpperCase = true,
    this.textInputAction = TextInputAction.next,
  });

  // Regex muy laxo, solo para evitar typos groseros (espacios, falta de @, etc.).
  static final RegExp _mailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: controller,
        maxLength: maxLength,
        keyboardType: isMail
            ? TextInputType.emailAddress
            : (isNumeric ? TextInputType.number : TextInputType.text),
        textInputAction: textInputAction,
        // Formatters según el tipo de campo:
        // - Numérico (DNI, CUIL, teléfono): solo dígitos. El keyboardType
        //   number ayuda en mobile pero no garantiza nada en desktop ni
        //   en paste, por eso el DigitOnlyFormatter es la red real.
        // - Texto con toUpperCase: mayúsculas vivas, evitando
        //   `textCapitalization` que rompe Backspace en Windows.
        inputFormatters: [
          if (isNumeric) DigitOnlyFormatter(maxLength: maxLength),
          if (!isNumeric && toUpperCase) UpperCaseInputFormatter(),
        ],
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          counterText: '',
          labelText: label,
          prefixIcon: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
        ),
        validator: (value) {
          final v = value?.trim() ?? '';
          // El mail es opcional: si está vacío, OK. Si tiene texto, validamos.
          if (isMail) {
            if (v.isEmpty) return null;
            if (!_mailRegex.hasMatch(v)) return 'Mail inválido';
            return null;
          }
          if (v.isEmpty) {
            return 'Campo obligatorio';
          }
          if (isNumeric && v.length < (maxLength ?? 0)) {
            return 'Dato incompleto';
          }
          if (isCuil && v.length != 11) {
            return 'El CUIL debe tener 11 dígitos';
          }
          return null;
        },
      ),
    );
  }
}

class _DropdownEmpresa extends StatelessWidget {
  final String value;
  final List<String> empresas;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _DropdownEmpresa({
    required this.value,
    required this.empresas,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: Theme.of(context).colorScheme.surface,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: empresas
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(e, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  final String rol;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _RoleSelector({
    required this.rol,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'USER',
            label: Text('Chofer'),
            icon: Icon(Icons.drive_eta, size: 18),
          ),
          ButtonSegment(
            value: 'ADMIN',
            label: Text('Admin'),
            icon: Icon(Icons.security, size: 18),
          ),
        ],
        selected: {rol},
        onSelectionChanged:
            enabled ? (set) => onChanged(set.first) : null,
      ),
    );
  }
}

class _BotonGuardar extends StatelessWidget {
  final bool guardando;
  final VoidCallback onPressed;

  const _BotonGuardar({
    required this.guardando,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton.icon(
        onPressed: guardando ? null : onPressed,
        icon: guardando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : const Icon(Icons.person_add_alt_1),
        label: Text(
          guardando ? 'PROCESANDO...' : 'CREAR LEGAJO',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
