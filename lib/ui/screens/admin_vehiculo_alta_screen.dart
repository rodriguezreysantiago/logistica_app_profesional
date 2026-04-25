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
  final TextEditingController _vinCtrl = TextEditingController();

  String _tipoSeleccionado = 'TRACTOR';
  
  String _empresaSeleccionada = "VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)";
  bool _guardando = false; // ✅ ESCUDO: Estado para bloquear doble clicks

  final List<String> _empresas = [
    "VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)",
    "SUCESION DE VECCHI CARLOS LUIS: (20-08569424-4)"
  ];

  @override
  void dispose() {
    _patenteCtrl.dispose();
    _marcaCtrl.dispose();
    _modeloCtrl.dispose();
    _anioCtrl.dispose();
    _vinCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardarVehiculo() async {
    if (!_formKey.currentState!.validate()) return;
    if (_guardando) return; // ✅ ESCUDO: Si ya está guardando, aborta el click extra

    setState(() => _guardando = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // ✅ NORMALIZACIÓN CRÍTICA: Mayúsculas, sin espacios adelante/atrás, y sin espacios en el medio.
    final String patente = _patenteCtrl.text.trim().toUpperCase().replaceAll(' ', '');

    try {
      final doc = await FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).get();
      
      if (doc.exists) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text("Error: Esta patente ya está registrada"), backgroundColor: Colors.red)
        );
        setState(() => _guardando = false);
        return;
      }

      await FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).set({
        'DOMINIO': patente,
        'TIPO': _tipoSeleccionado,
        'MARCA': _marcaCtrl.text.trim().toUpperCase(),
        'MODELO': _modeloCtrl.text.trim().toUpperCase(),
        'ANIO': int.tryParse(_anioCtrl.text.trim()) ?? 0,
        'VIN': _vinCtrl.text.trim().toUpperCase(),
        'EMPRESA': _empresaSeleccionada,
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
        const SnackBar(content: Text("Unidad registrada con éxito"), backgroundColor: Colors.green)
      );
      
      navigator.pop(); // Cierra la pantalla de formulario exitosamente

    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Error al guardar: $e"), backgroundColor: Colors.red)
      );
      setState(() => _guardando = false); // Reactivamos el botón si falla
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1D2D),
      appBar: AppBar(
        title: const Text("Alta de Nueva Unidad"),
        centerTitle: true,
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
              _buildInput("Patente / Dominio", _patenteCtrl, Icons.pin, hint: "Ej: AA123BB"),
              const Text("Tipo de Unidad", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _buildTipoSelector(),
              const SizedBox(height: 25),
              _buildInput("Marca", _marcaCtrl, Icons.factory),
              _buildInput("Modelo", _modeloCtrl, Icons.commute),
              _buildInput("Año (Modelo)", _anioCtrl, Icons.calendar_today, isNumeric: true, maxLength: 4),
              _buildInput("Código VIN", _vinCtrl, Icons.fingerprint, hint: "Obligatorio (17 caracteres)", esOpcional: _tipoSeleccionado != 'TRACTOR', isVin: true),
              const Text("Empresa Propietaria", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _buildEmpresaDropdown(),
              const SizedBox(height: 40),
              
              // ✅ BOTÓN INTELIGENTE: Cambia su diseño y se bloquea si está cargando
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: _guardando ? null : _guardarVehiculo,
                  icon: _guardando 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black54, strokeWidth: 2))
                      : const Icon(Icons.cloud_upload),
                  label: Text(
                    _guardando ? "REGISTRANDO..." : "REGISTRAR EN FLOTA", 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.greenAccent.withAlpha(100),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController ctrl, IconData icon, {bool isNumeric = false, String? hint, bool esOpcional = false, int? maxLength, bool isVin = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: ctrl,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        maxLength: maxLength,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          counterStyle: const TextStyle(color: Colors.white24),
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
          labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
          prefixIcon: Icon(icon, color: Colors.greenAccent, size: 20),
          filled: true,
          fillColor: Colors.white.withAlpha(5),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.greenAccent)),
        ),
        validator: (value) {
          if (esOpcional && (value == null || value.isEmpty)) return null;
          if (!esOpcional && (value == null || value.isEmpty)) return "Campo obligatorio";
          
          if (isVin && value != null && value.trim().length != 17) {
            return "El VIN debe tener exactamente 17 caracteres";
          }
          return null;
        },
      ),
    );
  }

  Widget _buildTipoSelector() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'TRACTOR', label: Text('Tractor', style: TextStyle(fontSize: 12)), icon: Icon(Icons.local_shipping, size: 16)),
          ButtonSegment(value: 'BATEA', label: Text('Batea', style: TextStyle(fontSize: 12)), icon: Icon(Icons.view_agenda, size: 16)),
          ButtonSegment(value: 'TOLVA', label: Text('Tolva', style: TextStyle(fontSize: 12)), icon: Icon(Icons.difference, size: 16)),
        ],
        selected: {_tipoSeleccionado},
        onSelectionChanged: (Set<String> newSelection) {
          setState(() {
             _tipoSeleccionado = newSelection.first;
             if (_tipoSeleccionado != 'TRACTOR') {
               _vinCtrl.clear();
             }
          });
        },
        style: SegmentedButton.styleFrom(
          backgroundColor: Colors.white.withAlpha(10),
          foregroundColor: Colors.white,
          selectedBackgroundColor: Colors.greenAccent,
          selectedForegroundColor: Colors.black,
          side: const BorderSide(color: Colors.white10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildEmpresaDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withAlpha(10), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
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
}