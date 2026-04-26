import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminPersonalFormScreen extends StatefulWidget {
  const AdminPersonalFormScreen({super.key});

  @override
  State<AdminPersonalFormScreen> createState() => _AdminPersonalFormScreenState();
}

class _AdminPersonalFormScreenState extends State<AdminPersonalFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _dniCtrl = TextEditingController();
  final TextEditingController _nombreCtrl = TextEditingController();
  final TextEditingController _cuilCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  
  String _rolSeleccionado = 'USER';
  String _empresaSeleccionada = "VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)";
  bool _guardando = false; // ✅ MENTOR: Control de estado para el botón

  final List<String> _empresas = [
    "VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)", 
    "SUCESION DE VECCHI CARLOS LUIS: (20-08569424-4)"
  ];

  @override
  void dispose() {
    _dniCtrl.dispose();
    _nombreCtrl.dispose();
    _cuilCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardarNuevoChofer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_guardando) return;

    setState(() => _guardando = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final String dniLimpio = _dniCtrl.text.trim();

      // 1. Verificamos si el DNI ya existe
      final doc = await FirebaseFirestore.instance
          .collection('EMPLEADOS')
          .doc(dniLimpio)
          .get();
      
      if (doc.exists) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Error: Este DNI ya está registrado"), backgroundColor: Colors.redAccent)
        );
        setState(() => _guardando = false);
        return;
      }

      // 2. Creamos el legajo
      await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dniLimpio).set({
        'NOMBRE': _nombreCtrl.text.trim().toUpperCase(),
        'CUIL': _cuilCtrl.text.trim(),
        'CONTRASEÑA': _passCtrl.text.trim(),
        'ROL': _rolSeleccionado,
        'EMPRESA': _empresaSeleccionada,
        'VEHICULO': '-', 
        'ENGANCHE': '-',
        'ARCHIVO_PERFIL': '-',
        'estado_cuenta': 'ACTIVO',
        'fecha_creacion': FieldValue.serverTimestamp(),
        'ultima_modificacion': FieldValue.serverTimestamp(),
      });

      messenger.showSnackBar(
        const SnackBar(content: Text("Chofer creado con éxito"), backgroundColor: Colors.green)
      );
      navigator.pop(); 

    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Error al guardar: $e"), backgroundColor: Colors.redAccent)
      );
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // Cierra el teclado al tocar fuera
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Nuevo Legajo de Personal"),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInput(
                  label: "DNI (Será el usuario)", 
                  ctrl: _dniCtrl, 
                  icon: Icons.badge, 
                  isNumeric: true, 
                  maxLength: 8,
                ),
                _buildInput(
                  label: "Nombre y Apellido Completo", 
                  ctrl: _nombreCtrl, 
                  icon: Icons.person,
                  textCapitalization: TextCapitalization.words,
                ),
                _buildInput(
                  label: "CUIL (sin guiones)", 
                  ctrl: _cuilCtrl, 
                  icon: Icons.assignment_ind, 
                  isNumeric: true, 
                  maxLength: 11,
                  isCuil: true,
                ),
                _buildInput(
                  label: "Contraseña Inicial", 
                  ctrl: _passCtrl, 
                  icon: Icons.lock_outline,
                  textInputAction: TextInputAction.done,
                ),
                
                const SizedBox(height: 10),
                const Text("Empresa Asignada", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                _buildDropdownEmpresa(),
                
                const SizedBox(height: 25),
                const Text("Rol en el Sistema", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _buildRoleSelectorModerno(),
                
                const SizedBox(height: 40),
                _buildBotonGuardar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBotonGuardar() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton.icon(
        onPressed: _guardando ? null : _guardarNuevoChofer,
        icon: _guardando 
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
          : const Icon(Icons.person_add_alt_1),
        label: Text(
          _guardando ? "PROCESANDO..." : "CREAR LEGAJO", 
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
        ),
      ),
    );
  }

  Widget _buildInput({
    required String label, 
    required TextEditingController ctrl, 
    required IconData icon, 
    bool isNumeric = false, 
    int? maxLength,
    bool isCuil = false,
    TextCapitalization textCapitalization = TextCapitalization.characters,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: ctrl,
        maxLength: maxLength,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          counterText: "", // Limpiamos el contador visual para que sea más minimalista
          labelText: label,
          prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return "Campo obligatorio";
          if (isNumeric && value.length < (maxLength ?? 0)) return "Dato incompleto";
          if (isCuil && value.length != 11) return "El CUIL debe tener 11 dígitos";
          return null;
        },
      ),
    );
  }

  Widget _buildDropdownEmpresa() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _empresaSeleccionada,
          isExpanded: true,
          dropdownColor: const Color(0xFF132538),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: _empresas.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: _guardando ? null : (val) => setState(() => _empresaSeleccionada = val!),
        ),
      ),
    );
  }

  Widget _buildRoleSelectorModerno() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'USER', label: Text('Chofer'), icon: Icon(Icons.drive_eta, size: 18)),
          ButtonSegment(value: 'ADMIN', label: Text('Admin'), icon: Icon(Icons.security, size: 18)),
        ],
        selected: {_rolSeleccionado},
        onSelectionChanged: _guardando ? null : (Set<String> newSelection) => setState(() => _rolSeleccionado = newSelection.first),
      ),
    );
  }
}