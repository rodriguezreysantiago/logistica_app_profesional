import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminPersonalFormScreen extends StatefulWidget {
  const AdminPersonalFormScreen({super.key});

  @override
  State<AdminPersonalFormScreen> createState() => _AdminPersonalFormScreenState();
}

class _AdminPersonalFormScreenState extends State<AdminPersonalFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers para los datos básicos obligatorios
  final TextEditingController _dniCtrl = TextEditingController();
  final TextEditingController _nombreCtrl = TextEditingController();
  final TextEditingController _cuilCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  
  String _rolSeleccionado = 'USER';
  String _empresaSeleccionada = "VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)";

  final List<String> _empresas = [
    "VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)", 
    "SUCESION DE VECCHI CARLOS LUIS: (20-08569424-4)"
  ];

  Future<void> _guardarNuevoChofer() async {
    if (!_formKey.currentState!.validate()) return;

    // Referencias seguras para evitar errores de BuildContext asíncrono
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      // 1. Verificamos si el DNI ya existe para no pisar datos
      final doc = await FirebaseFirestore.instance
          .collection('EMPLEADOS')
          .doc(_dniCtrl.text.trim())
          .get();
      
      if (doc.exists) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Error: Este DNI ya está registrado"), backgroundColor: Colors.red)
        );
        return;
      }

      // 2. Creamos el legajo con la estructura estándar
      await FirebaseFirestore.instance.collection('EMPLEADOS').doc(_dniCtrl.text.trim()).set({
        'NOMBRE': _nombreCtrl.text.trim().toUpperCase(),
        'CUIL': _cuilCtrl.text.trim(),
        'CONTRASEÑA': _passCtrl.text.trim(),
        'ROL': _rolSeleccionado,
        'EMPRESA': _empresaSeleccionada,
        'VEHICULO': '-', 
        'ENGANCHE': '-',
        'ARCHIVO_PERFIL': '-',
        'fecha_creacion': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Chofer creado con éxito"), backgroundColor: Colors.green)
      );
      navigator.pop(); // Volver a la lista

    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Error al guardar: $e"), backgroundColor: Colors.red)
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1D2D),
      appBar: AppBar(
        title: const Text("Nuevo Legajo de Personal"),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInput("DNI (Será el usuario)", _dniCtrl, Icons.badge, isNumeric: true),
              _buildInput("Nombre y Apellido Completo", _nombreCtrl, Icons.person),
              _buildInput("CUIL (sin guiones)", _cuilCtrl, Icons.assignment_ind, isNumeric: true),
              _buildInput("Contraseña Inicial", _passCtrl, Icons.lock_outline),
              
              const SizedBox(height: 20),
              const Text("Empresa Asignada", style: TextStyle(color: Colors.white70, fontSize: 12)),
              _buildDropdownEmpresa(),
              
              const SizedBox(height: 25),
              const Text("Rol en el Sistema", style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 10),
              _buildRoleSelectorModerno(), // Usamos la versión moderna
              
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: _guardarNuevoChofer,
                  icon: const Icon(Icons.save),
                  label: const Text("CREAR LEGAJO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController ctrl, IconData icon, {bool isNumeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: ctrl,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white60),
          prefixIcon: Icon(icon, color: Colors.orangeAccent, size: 20),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orangeAccent)),
        ),
        validator: (value) => (value == null || value.isEmpty) ? "Campo obligatorio" : null,
      ),
    );
  }

  Widget _buildDropdownEmpresa() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: DropdownButton<String>(
        value: _empresaSeleccionada,
        isExpanded: true,
        dropdownColor: const Color(0xFF1A3A5A),
        style: const TextStyle(color: Colors.white, fontSize: 13),
        underline: const SizedBox(),
        items: _empresas.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (val) => setState(() => _empresaSeleccionada = val!),
      ),
    );
  }

  // REEMPLAZO MODERNO: SegmentedButton evita el error de "groupValue deprecated"
  Widget _buildRoleSelectorModerno() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'USER', 
            label: Text('Chofer'), 
            icon: Icon(Icons.drive_eta, size: 18)
          ),
          ButtonSegment(
            value: 'ADMIN', 
            label: Text('Admin'), 
            icon: Icon(Icons.security, size: 18)
          ),
        ],
        selected: {_rolSeleccionado},
        onSelectionChanged: (Set<String> newSelection) {
          setState(() => _rolSeleccionado = newSelection.first);
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Colors.white.withAlpha(10),
          foregroundColor: Colors.white,
          selectedBackgroundColor: Colors.orangeAccent,
          selectedForegroundColor: Colors.black,
          side: const BorderSide(color: Colors.white24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}