import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/app_widgets.dart';

/// Form de alta de un nuevo vehículo (tractor / batea / tolva).
class AdminVehiculoAltaScreen extends StatefulWidget {
  const AdminVehiculoAltaScreen({super.key});

  @override
  State<AdminVehiculoAltaScreen> createState() =>
      _AdminVehiculoAltaScreenState();
}

class _AdminVehiculoAltaScreenState
    extends State<AdminVehiculoAltaScreen> {
  final _formKey = GlobalKey<FormState>();

  final _patenteCtrl = TextEditingController();
  final _marcaCtrl = TextEditingController();
  final _modeloCtrl = TextEditingController();
  final _anioCtrl = TextEditingController();
  final _vinCtrl = TextEditingController();

  String _tipo = 'TRACTOR';
  String _empresa =
      'VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)';
  bool _guardando = false;

  static const _empresas = [
    'VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)',
    'SUCESION DE VECCHI CARLOS LUIS: (20-08569424-4)',
  ];

  @override
  void initState() {
    super.initState();
    // Pre-cargamos marca por defecto VOLVO (el 95% de la flota es VOLVO).
    _marcaCtrl.text = 'VOLVO';
  }

  @override
  void dispose() {
    _patenteCtrl.dispose();
    _marcaCtrl.dispose();
    _modeloCtrl.dispose();
    _anioCtrl.dispose();
    _vinCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_guardando) return;

    setState(() => _guardando = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final patente =
        _patenteCtrl.text.trim().toUpperCase().replaceAll(' ', '');

    try {
      // 1) ¿Ya existe?
      final doc = await FirebaseFirestore.instance
          .collection('VEHICULOS')
          .doc(patente)
          .get();

      if (doc.exists) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
                'Error: esta patente ya está registrada en la flota'),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() => _guardando = false);
        return;
      }

      // 2) Crear el vehículo
      await FirebaseFirestore.instance
          .collection('VEHICULOS')
          .doc(patente)
          .set({
        'DOMINIO': patente,
        'TIPO': _tipo,
        'MARCA': _marcaCtrl.text.trim().toUpperCase(),
        'MODELO': _modeloCtrl.text.trim().toUpperCase(),
        'ANIO': int.tryParse(_anioCtrl.text.trim()) ?? 0,
        'VIN': _tipo == 'TRACTOR'
            ? _vinCtrl.text.trim().toUpperCase()
            : '-',
        'EMPRESA': _empresa,
        'ESTADO': 'LIBRE',
        'KM_ACTUAL': 0,
        'fecha_alta': FieldValue.serverTimestamp(),
        'ARCHIVO_RTO': '-',
        'ARCHIVO_SEGURO': '-',
        'VENCIMIENTO_RTO': '',
        'VENCIMIENTO_SEGURO': '',
      });

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unidad registrada con éxito'),
          backgroundColor: Colors.green,
        ),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AppScaffold(
        title: 'Alta de Nueva Unidad',
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _VInput(
                  label: 'Patente / Dominio',
                  controller: _patenteCtrl,
                  icon: Icons.pin,
                  hint: 'Ej: AA123BB o AAA123',
                  isPatente: true,
                ),
                const _LabelCampo('Tipo de unidad'),
                const SizedBox(height: 10),
                _SelectorTipo(
                  tipo: _tipo,
                  enabled: !_guardando,
                  onChanged: (val) {
                    setState(() {
                      _tipo = val;
                      // Limpiamos el VIN si cambia a un acoplado
                      if (val != 'TRACTOR') _vinCtrl.clear();
                    });
                  },
                ),
                const SizedBox(height: 25),
                _VInput(
                  label: 'Marca',
                  controller: _marcaCtrl,
                  icon: Icons.factory,
                  readOnly: true,
                ),
                _VInput(
                  label: 'Modelo',
                  controller: _modeloCtrl,
                  icon: Icons.commute,
                ),
                _VInput(
                  label: 'Año (modelo)',
                  controller: _anioCtrl,
                  icon: Icons.calendar_today,
                  isNumeric: true,
                  maxLength: 4,
                  isAnio: true,
                ),
                if (_tipo == 'TRACTOR')
                  _VInput(
                    label: 'Código VIN',
                    controller: _vinCtrl,
                    icon: Icons.fingerprint,
                    hint: 'Obligatorio (17 caracteres)',
                    isVin: true,
                    textInputAction: TextInputAction.done,
                  ),
                const _LabelCampo('Empresa propietaria'),
                const SizedBox(height: 10),
                _DropdownEmpresa(
                  value: _empresa,
                  empresas: _empresas,
                  enabled: !_guardando,
                  onChanged: (val) =>
                      setState(() => _empresa = val ?? _empresa),
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
// COMPONENTES (similares a admin_personal_form pero con validaciones de patente/VIN/año)
// =============================================================================

class _LabelCampo extends StatelessWidget {
  final String label;
  const _LabelCampo(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _VInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final bool isNumeric;
  final String? hint;
  final int? maxLength;
  final bool isVin;
  final bool isPatente;
  final bool isAnio;
  final bool readOnly;
  final TextInputAction textInputAction;

  const _VInput({
    required this.label,
    required this.controller,
    required this.icon,
    this.isNumeric = false,
    this.hint,
    this.maxLength,
    this.isVin = false,
    this.isPatente = false,
    this.isAnio = false,
    this.readOnly = false,
    this.textInputAction = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: controller,
        keyboardType:
            isNumeric ? TextInputType.number : TextInputType.text,
        textInputAction: textInputAction,
        maxLength: maxLength,
        readOnly: readOnly,
        textCapitalization: TextCapitalization.characters,
        style: TextStyle(
          color: readOnly ? Colors.white54 : Colors.white,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          counterText: '',
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
          prefixIcon: Icon(
            icon,
            color: readOnly
                ? Colors.white24
                : Theme.of(context).colorScheme.primary,
            size: 20,
          ),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Campo obligatorio';
          }
          if (isPatente) {
            final regex = RegExp(r'^([A-Z]{2}\d{3}[A-Z]{2}|[A-Z]{3}\d{3})$');
            final clean =
                value.trim().toUpperCase().replaceAll(' ', '');
            if (!regex.hasMatch(clean)) {
              return 'Formato inválido (Ej: AA123BB o AAA123)';
            }
          }
          if (isAnio) {
            final anio = int.tryParse(value.trim());
            if (anio == null) return 'Ingrese un año válido';
            if (anio < 2015) {
              return 'Solo se admiten unidades modelo 2015 en adelante';
            }
            if (anio > DateTime.now().year + 1) {
              return 'Año fuera de rango';
            }
          }
          if (isVin && value.trim().length != 17) {
            return 'El código VIN debe tener exactamente 17 caracteres';
          }
          return null;
        },
      ),
    );
  }
}

class _SelectorTipo extends StatelessWidget {
  final String tipo;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _SelectorTipo({
    required this.tipo,
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
            value: 'TRACTOR',
            label: Text('Tractor', style: TextStyle(fontSize: 12)),
            icon: Icon(Icons.local_shipping, size: 16),
          ),
          ButtonSegment(
            value: 'BATEA',
            label: Text('Batea', style: TextStyle(fontSize: 12)),
            icon: Icon(Icons.view_agenda, size: 16),
          ),
          ButtonSegment(
            value: 'TOLVA',
            label: Text('Tolva', style: TextStyle(fontSize: 12)),
            icon: Icon(Icons.difference, size: 16),
          ),
        ],
        selected: {tipo},
        onSelectionChanged:
            enabled ? (set) => onChanged(set.first) : null,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: Theme.of(context).colorScheme.surface,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items: empresas
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(e, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: enabled ? onChanged : null,
        ),
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
            : const Icon(Icons.cloud_upload),
        label: Text(
          guardando ? 'REGISTRANDO...' : 'REGISTRAR EN FLOTA',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.greenAccent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: Colors.greenAccent.withAlpha(100),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
