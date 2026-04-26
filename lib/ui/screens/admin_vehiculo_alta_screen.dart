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
  bool _guardando = false; 

  final List<String> _empresas = [
    "VECCHI ARIEL Y VECCHI GRACIELA S.R.L: (30-70910015-3)",
    "SUCESION DE VECCHI CARLOS LUIS: (20-08569424-4)"
  ];

  @override
  void initState() {
    super.initState();
    // ✅ MENTOR: Pre-cargamos datos fijos de la flota para agilizar el alta y evitar errores de tipeo.
    _marcaCtrl.text = "VOLVO";
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

  Future<void> _guardarVehiculo() async {
    // Si la validación falla, cortamos la ejecución acá.
    if (!_formKey.currentState!.validate()) return;
    if (_guardando) return; 

    setState(() => _guardando = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final String patente = _patenteCtrl.text.trim().toUpperCase().replaceAll(' ', '');

    try {
      final doc = await FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).get();
      
      if (doc.exists) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text("Error: Esta patente ya está registrada en la flota"), backgroundColor: Colors.redAccent)
        );
        setState(() => _guardando = false);
        return;
      }

      // ✅ MENTOR: Preparamos el payload limpio antes de enviarlo. 
      // Esto facilita la lectura y futuras modificaciones.
      final Map<String, dynamic> vehiculoData = {
        'DOMINIO': patente,
        'TIPO': _tipoSeleccionado,
        'MARCA': _marcaCtrl.text.trim().toUpperCase(),
        'MODELO': _modeloCtrl.text.trim().toUpperCase(),
        'ANIO': int.tryParse(_anioCtrl.text.trim()) ?? 0,
        'VIN': _tipoSeleccionado == 'TRACTOR' ? _vinCtrl.text.trim().toUpperCase() : '-',
        'EMPRESA': _empresaSeleccionada,
        'ESTADO': 'LIBRE', 
        'KM_ACTUAL': 0,
        'fecha_alta': FieldValue.serverTimestamp(),
        'ARCHIVO_RTO': '-',
        'ARCHIVO_SEGURO': '-',
        'VENCIMIENTO_RTO': '',
        'VENCIMIENTO_SEGURO': '',
      };

      await FirebaseFirestore.instance.collection('VEHICULOS').doc(patente).set(vehiculoData);

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Unidad registrada con éxito"), backgroundColor: Colors.green)
      );
      
      navigator.pop(); 

    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Error de conexión al guardar: $e"), backgroundColor: Colors.redAccent)
      );
      setState(() => _guardando = false); 
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
      // ✅ MENTOR: GesturDetector quita el foco (cierra el teclado) si el usuario toca afuera de los campos.
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInput(
                  label: "Patente / Dominio", 
                  ctrl: _patenteCtrl, 
                  icon: Icons.pin, 
                  hint: "Ej: AA123BB o AAA123",
                  isPatente: true,
                ),
                const Text("Tipo de Unidad", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _buildTipoSelector(),
                const SizedBox(height: 25),
                
                // ✅ MENTOR: La marca está bloqueada (readOnly) porque es estandar de flota.
                _buildInput(label: "Marca", ctrl: _marcaCtrl, icon: Icons.factory, readOnly: true),
                _buildInput(label: "Modelo", ctrl: _modeloCtrl, icon: Icons.commute),
                _buildInput(
                  label: "Año (Modelo)", 
                  ctrl: _anioCtrl, 
                  icon: Icons.calendar_today, 
                  isNumeric: true, 
                  maxLength: 4,
                  isAnio: true,
                ),
                
                // Si no es TRACTOR, ocultamos el campo VIN para limpiar la pantalla visualmente.
                if (_tipoSeleccionado == 'TRACTOR')
                  _buildInput(
                    label: "Código VIN", 
                    ctrl: _vinCtrl, 
                    icon: Icons.fingerprint, 
                    hint: "Obligatorio (17 caracteres)", 
                    isVin: true,
                    textInputAction: TextInputAction.done,
                  ),
                
                const Text("Empresa Propietaria", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _buildEmpresaDropdown(),
                const SizedBox(height: 40),
                
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
      ),
    );
  }

  // ✅ MENTOR: Usar parámetros nombrados ({}) hace que la llamada a la función sea mucho más clara.
  Widget _buildInput({
    required String label, 
    required TextEditingController ctrl, 
    required IconData icon, 
    bool isNumeric = false, 
    String? hint, 
    int? maxLength, 
    bool isVin = false,
    bool isPatente = false,
    bool isAnio = false,
    bool readOnly = false,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: ctrl,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        textInputAction: textInputAction,
        maxLength: maxLength,
        readOnly: readOnly,
        style: TextStyle(color: readOnly ? Colors.white54 : Colors.white, fontSize: 14),
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          counterText: "", // Oculta el contador visual de caracteres para un diseño más limpio
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
          labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
          prefixIcon: Icon(icon, color: readOnly ? Colors.white24 : Colors.greenAccent, size: 20),
          filled: true,
          fillColor: readOnly ? Colors.white.withAlpha(2) : Colors.white.withAlpha(5),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.greenAccent)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent)),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return "Campo obligatorio";
          
          if (isPatente) {
            // ✅ MENTOR: Expresión regular para validar formato AA123BB o AAA123
            final regex = RegExp(r'^([A-Z]{2}\d{3}[A-Z]{2}|[A-Z]{3}\d{3})$');
            final patenteLimpia = value.trim().toUpperCase().replaceAll(' ', '');
            if (!regex.hasMatch(patenteLimpia)) {
              return "Formato inválido (Ej: AA123BB o AAA123)";
            }
          }

          if (isAnio) {
            final anio = int.tryParse(value.trim());
            if (anio == null) return "Ingrese un año válido";
            if (anio < 2015) return "Solo se admiten unidades modelo 2015 en adelante";
            if (anio > DateTime.now().year + 1) return "Año fuera de rango";
          }

          if (isVin && value.trim().length != 17) {
            return "El código VIN debe tener exactamente 17 caracteres";
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
               _vinCtrl.clear(); // Limpiamos el VIN si cambian a un acoplado
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