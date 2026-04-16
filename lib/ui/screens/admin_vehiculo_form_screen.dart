import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminVehiculoFormScreen extends StatefulWidget {
  final String vehiculoId;
  final Map<String, dynamic> datosIniciales;

  const AdminVehiculoFormScreen({
    super.key,
    required this.vehiculoId,
    required this.datosIniciales,
  });

  @override
  State<AdminVehiculoFormScreen> createState() => _AdminVehiculoFormScreenState();
}

class _AdminVehiculoFormScreenState extends State<AdminVehiculoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  // Controladores de texto
  late TextEditingController _marcaController;
  late TextEditingController _modeloController;
  late TextEditingController _anioController;
  late TextEditingController _empresaController;
  
  // Variables para fechas
  String? _fechaRto;
  String? _fechaSeguro;

  @override
  void initState() {
    super.initState();
    // Precargamos los datos que ya existen
    _marcaController = TextEditingController(text: widget.datosIniciales['MARCA'] ?? '');
    _modeloController = TextEditingController(text: widget.datosIniciales['MODELO'] ?? '');
    _anioController = TextEditingController(text: widget.datosIniciales['AÑO'] ?? '');
    _empresaController = TextEditingController(text: widget.datosIniciales['EMPRESA'] ?? '');
    _fechaRto = widget.datosIniciales['VENCIMIENTO_RTO'];
    _fechaSeguro = widget.datosIniciales['VENCIMIENTO_SEGURO'];
  }

  @override
  void dispose() {
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _empresaController.dispose();
    super.dispose();
  }

  // Función para seleccionar fecha
  Future<void> _seleccionarFecha(BuildContext context, bool esRto) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        // Guardamos en formato YYYY-MM-DD
        String fechaFormateada = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
        if (esRto) {
          _fechaRto = fechaFormateada;
        } else {
          _fechaSeguro = fechaFormateada;
        }
      });
    }
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // Operación asíncrona en Firebase
      await FirebaseFirestore.instance
          .collection('VEHICULOS')
          .doc(widget.vehiculoId)
          .update({
        'MARCA': _marcaController.text.trim().toUpperCase(),
        'MODELO': _modeloController.text.trim().toUpperCase(),
        'AÑO': _anioController.text.trim(),
        'EMPRESA': _empresaController.text.trim().toUpperCase(),
        'VENCIMIENTO_RTO': _fechaRto,
        'VENCIMIENTO_SEGURO': _fechaSeguro,
        'ULTIMA_MODIFICACION': FieldValue.serverTimestamp(),
      });

      // --- MODIFICACIÓN AQUÍ: Guardar contra gaps asíncronos ---
      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vehículo actualizado con éxito")),
      );
    } catch (e) {
      // Verificamos mounted también en el catch por si el error tarda en responder
      if (!mounted) return;

      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al actualizar: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Editando ${widget.datosIniciales['DOMINIO'] ?? 'Vehículo'}"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/fondo_login.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.7)),
          
          SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildSectionTitle("DATOS GENERALES"),
                  _buildTextField(_marcaController, "Marca", Icons.branding_watermark),
                  _buildTextField(_modeloController, "Modelo", Icons.directions_car),
                  _buildTextField(_anioController, "Año", Icons.calendar_today, isNumber: true),
                  _buildTextField(_empresaController, "Empresa", Icons.business),
                  
                  const SizedBox(height: 25),
                  _buildSectionTitle("VENCIMIENTOS"),
                  
                  _buildDatePickerTile("Vencimiento RTO", _fechaRto, () => _seleccionarFecha(context, true)),
                  _buildDatePickerTile("Vencimiento Seguro", _fechaSeguro, () => _seleccionarFecha(context, false)),

                  const SizedBox(height: 40),
                  
                  _isSaving 
                    ? const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
                    : ElevatedButton(
                        onPressed: _guardarCambios,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("GUARDAR CAMBIOS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(title, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          prefixIcon: Icon(icon, color: Colors.orangeAccent, size: 20),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.1),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        validator: (value) => value == null || value.isEmpty ? "Campo obligatorio" : null,
      ),
    );
  }

  Widget _buildDatePickerTile(String label, String? fecha, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event, color: Colors.orangeAccent),
      title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      subtitle: Text(fecha ?? "Seleccionar fecha", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white30, size: 14),
    );
  }
}