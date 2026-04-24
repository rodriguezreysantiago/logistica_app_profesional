import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminPersonalFormScreen extends StatefulWidget {
  const AdminPersonalFormScreen({super.key});

  @override
  State<AdminPersonalFormScreen> createState() => _AdminPersonalFormScreenState();
}

class _AdminPersonalFormScreenState extends State<AdminPersonalFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
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

  // ✅ Mentora: REGLA DE ORO. Siempre cerrar los controladores.
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

    // Referencias para evitar el error de context en procesos asíncronos
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Mostramos un circulito de carga para que no toquen el botón dos veces
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orangeAccent)),
    );

    try {
      final String dniLimpio = _dniCtrl.text.trim();

      // 1. Verificamos si el DNI ya existe
      final doc = await FirebaseFirestore.instance
          .collection('EMPLEADOS')
          .doc(dniLimpio)
          .get();
      
      if (doc.exists) {
        if (mounted) Navigator.pop(context); // Cerramos el loading
        messenger.showSnackBar(
          const SnackBar(content: Text("Error: Este DNI ya está registrado"), backgroundColor: Colors.red)
        );
        return;
      }

      // 2. Creamos el legajo
      // ✅ Mentora: Agregué campos de control que te van a servir para auditoría después
      await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dniLimpio).set({
        'NOMBRE': _nombreCtrl.text.trim().toUpperCase(),
        'CUIL': _cuilCtrl.text.trim(),
        'CONTRASEÑA': _passCtrl.text.trim(),
        'ROL': _rolSeleccionado,
        'EMPRESA': _empresaSeleccionada,
        'VEHICULO': '-', 
        'ENGANCHE': '-',
        'ARCHIVO_PERFIL': '-',
        'estado_cuenta': 'ACTIVO', // Por si algún día querés dar de baja a alguien sin borrarlo
        'fecha_creacion': FieldValue.serverTimestamp(),
        'ultima_modificacion': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context); // Cerramos el loading
      messenger.showSnackBar(
        const SnackBar(content: Text("Chofer creado con éxito"), backgroundColor: Colors.green)
      );
      navigator.pop(); 

    } catch (e) {
      if (mounted) Navigator.pop(context); // Cerramos el loading
      messenger.showSnackBar(
        SnackBar(content: Text("Error al guardar: $e"), backgroundColor: Colors.red)
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // [El resto de tu UI está muy bien lograda, Santi. El uso de SegmentedButton es el correcto para Flutter moderno]
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
              _buildInput("DNI (Será el usuario)", _dniCtrl, Icons.badge, isNumeric: true, maxLength: 8),
              _buildInput("Nombre y Apellido Completo", _nombreCtrl, Icons.person),
              _buildInput("CUIL (sin guiones)", _cuilCtrl, Icons.assignment_ind, isNumeric: true, maxLength: 11),
              _buildInput("Contraseña Inicial", _passCtrl, Icons.lock_outline),
              
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
    );
  }

  // ✅ Mentora: Factorizar (separar) los widgets hace que el código sea más legible
  Widget _buildBotonGuardar() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton.icon(
        onPressed: _guardarNuevoChofer,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text("CREAR LEGAJO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orangeAccent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController ctrl, IconData icon, {bool isNumeric = false, int? maxLength}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: ctrl,
        maxLength: maxLength,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          counterStyle: const TextStyle(color: Colors.white24),
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white60),
          prefixIcon: Icon(icon, color: Colors.orangeAccent, size: 20),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orangeAccent)),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) return "Campo obligatorio";
          if (isNumeric && value.length < (maxLength ?? 0)) return "Dato incompleto";
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
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _empresaSeleccionada,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A3A5A),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items: _empresas.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (val) => setState(() => _empresaSeleccionada = val!),
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
        onSelectionChanged: (Set<String> newSelection) => setState(() => _rolSeleccionado = newSelection.first),
        style: SegmentedButton.styleFrom(
          backgroundColor: Colors.white.withAlpha(10),
          foregroundColor: Colors.white,
          selectedBackgroundColor: Colors.orangeAccent,
          selectedForegroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}