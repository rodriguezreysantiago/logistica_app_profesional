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
  // Almacena las respuestas: { "1. GUARDABARROS": "BUE" }
  final Map<String, String> _respuestas = {};
  // Almacena los comentarios: { "1. GUARDABARROS": "Soporte flojo" }
  final Map<String, String> _observaciones = {};
  
  bool _enviando = false;

  @override
  Widget build(BuildContext context) {
    // Obtenemos los ítems correctos según el tipo de unidad
    final Map<String, List<String>> secciones = 
        widget.tipo == "TRACTOR" ? ChecklistData.itemsTractor : ChecklistData.itemsBatea;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1D2D),
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          children: [
            Text("CHECKLIST MENSUAL ${widget.tipo}", style: const TextStyle(fontSize: 14)),
            Text(
              "UNIDAD: ${widget.patente}", 
              style: const TextStyle(fontSize: 11, color: Colors.orangeAccent, fontWeight: FontWeight.bold)
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  "Es obligatorio completar todos los puntos. Detalle cualquier novedad en el campo de texto.",
                  style: TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ...secciones.entries.map((sec) => _buildSeccion(sec.key, sec.value)),
              ],
            ),
          ),
          _buildBotonEnviar(secciones),
        ],
      ),
    );
  }

  Widget _buildSeccion(String titulo, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(5)
          ),
          child: Text(titulo, 
            style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ),
        const SizedBox(height: 10),
        ...items.map((item) => _buildItemPregunta(item)),
        const SizedBox(height: 25),
      ],
    );
  }

  Widget _buildItemPregunta(String item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A5A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ["BUE", "REG", "MAL"].map((estado) {
              bool seleccionado = _respuestas[item] == estado;
              return ChoiceChip(
                label: Text(estado, style: TextStyle(color: seleccionado ? Colors.black : Colors.white, fontSize: 11)),
                selected: seleccionado,
                selectedColor: _getColor(estado),
                backgroundColor: const Color(0xFF0D1D2D),
                onSelected: (val) {
                  setState(() => _respuestas[item] = estado);
                },
              );
            }).toList(),
          ),
          if (_respuestas[item] == "REG" || _respuestas[item] == "MAL")
            Padding(
              padding: const EdgeInsets.only(top: 15),
              child: TextField(
                style: const TextStyle(color: Colors.white, fontSize: 13),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: "Explique la novedad encontrada...",
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (val) => _observaciones[item] = val,
              ),
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
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF0D1D2D),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          minimumSize: const Size(double.infinity, 55),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _enviando ? null : () => _validarYEnviar(secciones),
        child: _enviando 
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text("GUARDAR REGISTRO FINAL", 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }

  Future<void> _validarYEnviar(Map<String, List<String>> secciones) async {
    // Calculamos el total real de ítems desde el diccionario para evitar errores
    final int totalItemsRequeridos = secciones.values.expand((e) => e).length;

    // 1. Validar que se hayan respondido todos los puntos
    if (_respuestas.length < totalItemsRequeridos) {
      _notificar("⚠️ Faltan puntos por responder (${_respuestas.length} de $totalItemsRequeridos).");
      return;
    }

    // 2. Validar que los REG/MAL tengan comentario
    bool faltaComentario = false;
    _respuestas.forEach((key, value) {
      if ((value == "REG" || value == "MAL") && (_observaciones[key] == null || _observaciones[key]!.trim().isEmpty)) {
        faltaComentario = true;
      }
    });

    if (faltaComentario) {
      _notificar("⚠️ Debe detallar el motivo en los puntos marcados como REG o MAL.");
      return;
    }

    setState(() => _enviando = true);

    try {
      final now = DateTime.now();
      
      // ✅ Respetamos la estructura exacta de tu captura de Firestore
      await FirebaseFirestore.instance.collection('CHECKLISTS').add({
        'ANIO': now.year,                             // int64
        'DNI': PrefsService.dni,               // string
        'FECHA': FieldValue.serverTimestamp(), // timestamp
        'MES': now.month,                             // int64
        'NOMBRE': PrefsService.nombre.toUpperCase(), // string "SANTIAGO"
        'DOMINIO': widget.patente,                    // string
        'TIPO': widget.tipo,                   // string
        'RESPUESTAS': _respuestas,                    // map con strings "1. GUARDABARROS"
        'OBSERVACIONES': _observaciones,              // map con observaciones
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Registro guardado con éxito"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        _notificar("❌ Error al guardar: $e");
      }
    }
  }

  void _notificar(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.redAccent),
    );
  }
}