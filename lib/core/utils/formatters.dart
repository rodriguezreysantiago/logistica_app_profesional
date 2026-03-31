class AppFormatters {
  // --- FUNCIONES DE LÓGICA (Todas estáticas para acceso directo) ---

  static String formatearDNI(dynamic dni) {
    final String s = dni?.toString() ?? "";
    if (s.length < 7 || s.length > 8) return s;
    return s.length == 7 
        ? "${s.substring(0, 1)}.${s.substring(1, 4)}.${s.substring(4)}"
        : "${s.substring(0, 2)}.${s.substring(2, 5)}.${s.substring(5)}";
  }

  static String formatearCUIL(dynamic cuil) {
    final String s = cuil?.toString() ?? "";
    if (s.length != 11) return s;
    // Formato: 20-12345678-9
    return "${s.substring(0, 2)}-${s.substring(2, 10)}-${s.substring(10)}";
  }

  static String formatearFecha(String? fecha) {
    if (fecha == null || fecha.isEmpty || fecha == "---" || fecha == "nan") {
      return "Sin datos";
    }
    try {
      final String f = fecha.replaceAll('/', '-');
      final List<String> partes = f.split('-');
      if (partes.length == 3) {
        // Si viene YYYY-MM-DD lo pasa a DD/MM/YYYY
        if (partes[0].length == 4) {
          return "${partes[2]}/${partes[1]}/${partes[0]}";
        }
        // Si ya viene DD-MM-YYYY solo cambia el separador
        return "${partes[0]}/${partes[1]}/${partes[2]}";
      }
      return fecha;
    } catch (e) { 
      return fecha; 
    }
  }

  static int calcularDiasRestantes(String? fecha) {
    if (fecha == null || fecha.isEmpty || fecha == "---" || fecha == "nan") {
      return 999;
    }
    try {
      final String f = fecha.replaceAll('/', '-');
      final List<String> partes = f.split('-');
      DateTime fVto;
      
      if (partes[0].length == 4) {
        fVto = DateTime.parse(f);
      } else {
        // Ajusta formato DD-MM-YYYY a objeto DateTime
        fVto = DateTime.parse("${partes[2]}-${partes[1].padLeft(2,'0')}-${partes[0].padLeft(2,'0')}");
      }
      
      // Calculamos la diferencia con el día de hoy
      final hoy = DateTime.now();
      final soloFechaHoy = DateTime(hoy.year, hoy.month, hoy.day);
      return fVto.difference(soloFechaHoy).inDays;
    } catch (_) { 
      return 999; 
    }
  }
}
