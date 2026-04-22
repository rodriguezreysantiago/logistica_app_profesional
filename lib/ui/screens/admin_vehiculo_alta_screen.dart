import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminVehiculoAltaScreen extends StatefulWidget {
  const AdminVehiculoAltaScreen({super.key});

  @override
  State<AdminVehiculoAltaScreen> createState() => _AdminVehiculoAltaScreenState();
}

class _AdminVehiculoAltaScreenState extends State<AdminVehiculoAltaScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _patenteCtrl = TextEditingController();
  final TextEditingController _marcaCtrl = TextEditingController();
  final TextEditingController _modeloCtrl = TextEditingController();
  final TextEditingController _anioCtrl = TextEditingController();
  final TextEditingController _vinCtrl = TextEditingController(); // <--- AGREGADO

  String _tipoSeleccionado = 'TRACTOR';
  String _empresaSeleccionada = "SUCESION DE VECCHI CARLOS LUIS CUIT: 20-08569424-4";

  final List<String> _empresas = [
    "SUCESION DE VECCHI CARLOS LUIS CUIT: 20-08569424-4",
    "VECCHI ARIEL Y VECCHI GRACIELA S.R.L (30-70910015-3)"
  ];

  @override
  void dispose() {
    _patenteCtrl.dispose();
    _marcaCtrl.dispose();
    _modeloCtrl.dispose();
    _anioCtrl.dispose();
    _vinCtrl.dispose(); // <--- AGREGADO
    super.dispose();
  }

  Future<void> _guardarVehiculo() async {
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final String patente = _patenteCtrl.text.trim().toUpperCase();

    try {
      final doc = await FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).get();
      if (doc.exists) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Error: Esta patente ya existe"), backgroundColor: Colors.red)
        );
        return;
      }

      await FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).set({
        'DOMINIO': patente,
        'TIPO': _tipoSeleccionado,
        'MARCA': _marcaCtrl.text.trim().toUpperCase(),
        'MODELO': _modeloCtrl.text.trim().toUpperCase(),
        'ANIO': int.tryParse(_anioCtrl.text.trim()) ?? 0, // Guardado como número
        'VIN': _vinCtrl.text.trim().toUpperCase(), // <--- SE GUARDA EL VIN AQUÍ
        'EMPRESA': _empresaSeleccionada, // <--- AGREGADO
        'ESTADO': 'LIBRE', 
        'KM_ACTUAL': '0',
        'fecha_alta': FieldValue.serverTimestamp(),
        'ARCHIVO_RTO': '-',
        'ARCHIVO_SEGURO': '-',
        'VENCIMIENTO_RTO': '',
        'VENCIMIENTO_SEGURO': '',
      });

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Unidad registrada con éxito"), backgroundColor: Colors.green)
      );
      navigator.pop();

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
        title: const Text("Alta de Nueva Unidad"),
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
              _buildInput("Patente / Dominio", _patenteCtrl, Icons.pin, hint: "Ej: AA123BB o ABC123"),
              const Text("Tipo de Unidad", style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 10),
              _buildTipoSelector(),
              const SizedBox(height: 25),
              _buildInput("Marca", _marcaCtrl, Icons.factory),
              _buildInput("Modelo", _modeloCtrl, Icons.commute),
              _buildInput("Año (Modelo)", _anioCtrl, Icons.calendar_today, isNumeric: true),
              
              // CAMPO VIN NUEVO
              _buildInput(
                "Código VIN", 
                _vinCtrl, 
                Icons.fingerprint, 
                hint: "Obligatorio para Volvo (17 caracteres)",
                esOpcional: _tipoSeleccionado != 'TRACTOR' // Opcional si no es camión
              ),

              const Text("Empresa Propietaria", style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 10),
              _buildEmpresaDropdown(),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: _guardarVehiculo,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text("REGISTRAR EN FLOTA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController ctrl, IconData icon, {bool isNumeric = false, String? hint, bool esOpcional = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: ctrl,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Colors.white),
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
          labelStyle: const TextStyle(color: Colors.white60),
          prefixIcon: Icon(icon, color: Colors.greenAccent, size: 20),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white24)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.greenAccent)),
        ),
        validator: (value) {
          if (esOpcional) return null;
          return (value == null || value.isEmpty) ? "Campo obligatorio" : null;
        },
      ),
    );
  }

  Widget _buildTipoSelector() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'TRACTOR', label: Text('Tractor'), icon: Icon(Icons.local_shipping, size: 16)),
          ButtonSegment(value: 'BATEA', label: Text('Batea'), icon: Icon(Icons.view_agenda, size: 16)),
          ButtonSegment(value: 'TOLVA', label: Text('Tolva'), icon: Icon(Icons.difference, size: 16)),
        ],
        selected: {_tipoSeleccionado},
        onSelectionChanged: (Set<String> newSelection) {
          setState(() => _tipoSeleccionado = newSelection.first);
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Colors.white.withAlpha(10),
          foregroundColor: Colors.white,
          selectedBackgroundColor: Colors.greenAccent,
          selectedForegroundColor: Colors.black,
          side: const BorderSide(color: Colors.white24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildEmpresaDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24)
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _empresaSeleccionada,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A3A5A),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: _empresas.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (val) => setState(() => _empresaSeleccionada = val!),
        ),
      ),
    );
  }
}