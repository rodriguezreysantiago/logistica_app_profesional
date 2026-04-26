import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/checklist_data.dart';
import '../../core/services/prefs_service.dart';

class UserChecklistFormScreen extends StatefulWidget {
  final String tipo; // "TRACTOR" o "BATEA"
  final String patente;

  const UserChecklistFormScreen({
    super.key, 
    required this.tipo, 
    required this.patente
  });

  @override
  State<UserChecklistFormScreen> createState() => _UserChecklistFormScreenState();
}

class _UserChecklistFormScreenState extends State<UserChecklistFormScreen> {
  final Map<String, String> _respuestas = {};
  final Map<String, String> _observaciones = {};
  
  bool _enviando = false;

  @override
  Widget build(BuildContext context) {
    final Map<String, List<String>> secciones = 
        widget.tipo == "TRACTOR" ? ChecklistData.itemsTractor : ChecklistData.itemsBatea;

    // ✅ MENTOR: GestureDetector para ocultar el teclado al tocar fuera de los inputs
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Column(
            children: [
              Text("CHECKLIST MENSUAL ${widget.tipo}", style: const TextStyle(fontSize: 14, color: Colors.white)),
              Text(
                "UNIDAD: ${widget.patente}", 
                style: const TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold, letterSpacing: 1.5)
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            // ✅ MENTOR: Fondo unificado con el resto de la app
            Positioned.fill(
              child: Image.asset(
                'assets/images/fondo_login.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => 
                    Container(color: Theme.of(context).scaffoldBackgroundColor),
              ),
            ),
            Positioned.fill(
              child: Container(color: Colors.black.withAlpha(200)),
            ),

            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withAlpha(20),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.orangeAccent.withAlpha(50))
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.orangeAccent, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Es obligatorio completar todos los puntos. Detalle cualquier novedad en el campo de texto.",
                                  style: TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25),
                        ...secciones.entries.map((sec) => _buildSeccion(sec.key, sec.value)),
                      ],
                    ),
                  ),
                  _buildBotonEnviar(secciones),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeccion(String titulo, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(50))
          ),
          child: Text(titulo.toUpperCase(), 
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ),
        const SizedBox(height: 15),
        ...items.map((item) => _buildItemPregunta(item)),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildItemPregunta(String item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface, // ✅ MENTOR: Hereda el color global
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ["BUE", "REG", "MAL"].map((estado) {
              bool seleccionado = _respuestas[item] == estado;
              return ChoiceChip(
                label: Container(
                  width: 50,
                  alignment: Alignment.center,
                  child: Text(estado, style: TextStyle(color: seleccionado ? Colors.black : Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
                ),
                selected: seleccionado,
                selectedColor: _getColor(estado),
                backgroundColor: Colors.black26,
                side: BorderSide(color: seleccionado ? _getColor(estado) : Colors.white24),
                onSelected: (val) {
                  setState(() {
                    _respuestas[item] = estado;
                    // Limpia el comentario si vuelve a poner BUE
                    if (estado == "BUE") {
                      _observaciones.remove(item);
                    }
                  });
                },
              );
            }).toList(),
          ),
          
          // Animación suave al desplegar el campo de texto
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: (_respuestas[item] == "REG" || _respuestas[item] == "MAL")
              ? Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: "Explique la novedad encontrada...",
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.black.withAlpha(100),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _getColor(_respuestas[item]!))
                      )
                    ),
                    onChanged: (val) => _observaciones[item] = val,
                  ),
                )
              : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Color _getColor(String estado) {
    if (estado == "BUE") return Colors.greenAccent;
    if (estado == "REG") return Colors.orangeAccent;
    return Colors.redAccent;
  }

  Widget _buildBotonEnviar(Map<String, List<String>> secciones) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 10,
            offset: const Offset(0, -5)
          )
        ]
      ),
      child: SafeArea(
        top: false,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            minimumSize: const Size(double.infinity, 55),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _enviando ? null : () => _validarYEnviar(secciones),
          child: _enviando 
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text("GUARDAR REGISTRO FINAL", 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1)),
        ),
      ),
    );
  }

  Future<void> _validarYEnviar(Map<String, List<String>> secciones) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final int totalItemsRequeridos = secciones.values.expand((e) => e).length;

    if (_respuestas.length < totalItemsRequeridos) {
      _notificar(messenger, "⚠️ Faltan puntos por responder (${_respuestas.length} de $totalItemsRequeridos).");
      return;
    }

    bool faltaComentario = false;
    _respuestas.forEach((key, value) {
      if ((value == "REG" || value == "MAL") && (_observaciones[key] == null || _observaciones[key]!.trim().isEmpty)) {
        faltaComentario = true;
      }
    });

    if (faltaComentario) {
      _notificar(messenger, "⚠️ Debe detallar el motivo en los puntos marcados como REG o MAL.");
      return;
    }

    setState(() => _enviando = true);

    try {
      final now = DateTime.now();
      
      await FirebaseFirestore.instance.collection('CHECKLISTS').add({
        'ANIO': now.year,                              
        'DNI': PrefsService.dni,               
        'FECHA': FieldValue.serverTimestamp(), 
        'MES': now.month,                              
        'NOMBRE': PrefsService.nombre.toUpperCase(), 
        'DOMINIO': widget.patente,                     
        'TIPO': widget.tipo,                   
        'RESPUESTAS': _respuestas,                     
        'OBSERVACIONES': _observaciones,               
      });

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text("✅ Registro guardado con éxito", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.green),
        );
        navigator.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        _notificar(messenger, "❌ Error al guardar: $e");
      }
    }
  }

  void _notificar(ScaffoldMessengerState messenger, String mensaje) {
    messenger.showSnackBar(
      SnackBar(content: Text(mensaje, style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.redAccent),
    );
  }
}