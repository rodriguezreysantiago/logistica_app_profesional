import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/formatters.dart';

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

  late TextEditingController _marcaController;
  late TextEditingController _modeloController;
  late TextEditingController _anioController;
  late TextEditingController _empresaController;
  late TextEditingController _vinController; // <--- AGREGADO

  String? _fechaRto;
  String? _fechaSeguro;

  @override
  void initState() {
    super.initState();
    _marcaController = TextEditingController(text: widget.datosIniciales['MARCA'] ?? '');
    _modeloController = TextEditingController(text: widget.datosIniciales['MODELO'] ?? '');
    _anioController = TextEditingController(text: (widget.datosIniciales['ANIO'] ?? widget.datosIniciales['AÑO'])?.toString() ?? '');
    _empresaController = TextEditingController(text: widget.datosIniciales['EMPRESA'] ?? '');
    _vinController = TextEditingController(text: widget.datosIniciales['VIN'] ?? ''); // <--- AGREGADO
    _fechaRto = widget.datosIniciales['VENCIMIENTO_RTO'];
    _fechaSeguro = widget.datosIniciales['VENCIMIENTO_SEGURO'];
  }

  @override
  void dispose() {
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _empresaController.dispose();
    _vinController.dispose(); // <--- AGREGADO
    super.dispose();
  }

  DateTime _parseFecha(String? fecha) {
    if (fecha == null || fecha.isEmpty) return DateTime.now();
    try {
      return DateTime.parse(fecha);
    } catch (_) {
      return DateTime.now();
    }
  }

  Future<void> _seleccionarFecha(BuildContext context, bool esRto) async {
    final DateTime initialDate = esRto ? _parseFecha(_fechaRto) : _parseFecha(_fechaSeguro);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      locale: const Locale('es', 'AR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.orangeAccent,
              onPrimary: Colors.black,
              surface: Color(0xFF1A3A5A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        String fechaFormateada = picked.toString().split(' ')[0];
        if (esRto) {
          _fechaRto = fechaFormateada;
        } else {
          _fechaSeguro = fechaFormateada;
        }
      });
    }
  }

  void _mostrarSelectorEmpresa() {
    final List<String> empresas = [
      "SUCESION DE VECCHI CARLOS LUIS CUIT: 20-08569424-4",
      "VECCHI ARIEL Y VECCHI GRACIELA S.R.L (30-70910015-3)"
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D1D2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Seleccionar Empresa", style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: empresas.map((e) => ListTile(
            title: Text(e, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            onTap: () {
              setState(() => _empresaController.text = e);
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;
    
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (_fechaRto == null || _fechaSeguro == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text("Faltan fechas de vencimiento"), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final String idLimpio = widget.vehiculoId.trim().toUpperCase();

      await FirebaseFirestore.instance
          .collection('VEHICULOS')
          .doc(idLimpio)
          .update({
        'MARCA': _marcaController.text.trim().toUpperCase(),
        'MODELO': _modeloController.text.trim().toUpperCase(),
        'ANIO': int.parse(_anioController.text.trim()),
        'EMPRESA': _empresaController.text.trim().toUpperCase(),
        'VIN': _vinController.text.trim().toUpperCase(), // <--- GUARDAMOS EL VIN
        'VENCIMIENTO_RTO': _fechaRto,
        'VENCIMIENTO_SEGURO': _fechaSeguro,
        'fecha_ultima_actualizacion': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text("Unidad actualizada correctamente"), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text("Error al guardar: $e"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Ficha Técnica: ${widget.vehiculoId}"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/fondo_login.jpg', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withAlpha(200)),
          ),
          SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildSectionTitle("INFORMACIÓN DE UNIDAD"),
                  _buildTextField(_marcaController, "Marca / Fabricante", Icons.branding_watermark),
                  _buildTextField(_modeloController, "Modelo / Descripción", Icons.info_outline),
                  _buildTextField(_anioController, "Año (Modelo)", Icons.calendar_today, isNumber: true),
                  
                  // CAMPO VIN (Especial para tractores Volvo)
                  _buildTextField(_vinController, "Código VIN (17 caracteres)", Icons.fingerprint, isVin: true),
                  
                  const SizedBox(height: 10),
                  _buildEmpresaTile(),

                  const SizedBox(height: 30),
                  _buildSectionTitle("AUDITORÍA DE VENCIMIENTOS"),

                  _buildDatePickerTile(
                    "Vencimiento RTO",
                    _fechaRto,
                    () => _seleccionarFecha(context, true),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  _buildDatePickerTile(
                    "Vencimiento Póliza Seguro",
                    _fechaSeguro,
                    () => _seleccionarFecha(context, false),
                  ),

                  const SizedBox(height: 60),

                  _isSaving
                      ? const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
                      : ElevatedButton.icon(
                          onPressed: _guardarCambios,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text("GUARDAR FICHA", style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: Colors.black,
                            minimumSize: const Size(double.infinity, 55),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                  const SizedBox(height: 20),
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
      padding: const EdgeInsets.only(bottom: 15, left: 5),
      child: Text(title, style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isNumber = false, bool isVin = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          prefixIcon: Icon(icon, color: Colors.orangeAccent, size: 18),
          filled: true,
          fillColor: Colors.white.withAlpha(20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        validator: (value) {
          if (isVin) return null; // El VIN es opcional (solo para Volvo)
          if (value == null || value.isEmpty) return "Campo requerido";
          if (isNumber) {
            final n = int.tryParse(value);
            if (n == null) return "Número inválido";
            if (n < 1950 || n > 2030) return "Año fuera de rango";
          }
          return null;
        },
      ),
    );
  }

  Widget _buildEmpresaTile() {
    return InkWell(
      onTap: _mostrarSelectorEmpresa,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white.withAlpha(20), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.business, color: Colors.orangeAccent, size: 20),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Razón Social Titular", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    _empresaController.text.isEmpty ? "Tocar para seleccionar..." : _empresaController.text,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePickerTile(String label, String? fecha, VoidCallback onTap) {
    int dias = AppFormatters.calcularDiasRestantes(fecha ?? "");
    Color colorSemaforo = dias < 0 ? Colors.red : (dias <= 14 ? Colors.orange : (dias <= 30 ? Colors.greenAccent : Colors.blueAccent));

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: Icon(Icons.edit_calendar, color: colorSemaforo, size: 22),
      title: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      subtitle: Text(AppFormatters.formatearFecha(fecha ?? ""), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colorSemaforo.withAlpha(40), 
          borderRadius: BorderRadius.circular(6), 
          border: Border.all(color: colorSemaforo.withAlpha(100))
        ),
        child: Text("${dias}d", style: TextStyle(color: colorSemaforo, fontWeight: FontWeight.bold, fontSize: 11)),
      ),
    );
  }
}