class AppFormatters {
  // --- FORMATEAR KILOMETRAJE (1.232.232,0) ---
  static String formatearKilometraje(dynamic valor) {
    if (valor == null || valor == 0 || valor == "0" || valor == "" || valor.toString().toLowerCase() == "nan") return "0,0";
    
    try {
      String raw = valor.toString().replaceAll(',', '.'); 
      double numero = double.parse(raw);
      
      String fixed = numero.toStringAsFixed(1).replaceAll('.', ',');
      
      List<String> partes = fixed.split(',');
      String entera = partes[0];
      String decimal = partes[1];

      final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
      entera = entera.replaceAllMapped(reg, (Match m) => '${m[1]}.');

      return "$entera,$decimal";
    } catch (e) {
      return "0,0";
    }
  }

  // --- FORMATEAR DNI (XX.XXX.XXX) ---
  static String formatearDNI(dynamic dni) {
    final String s = dni?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? "";
    if (s.length < 7 || s.length > 8) return s;
    return s.length == 7 
        ? "${s.substring(0, 1)}.${s.substring(1, 4)}.${s.substring(4)}"
        : "${s.substring(0, 2)}.${s.substring(2, 5)}.${s.substring(5)}";
  }

  // --- FORMATEAR CUIL (XX-XXXXXXXX-X) ---
  static String formatearCUIL(dynamic cuil) {
    final String s = cuil?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? "";
    if (s.length != 11) return s;
    return "${s.substring(0, 2)}-${s.substring(2, 10)}-${s.substring(10)}";
  }

  // --- FORMATEAR FECHA (DD/MM/YYYY) ---
  static String formatearFecha(String? fecha) {
    if (fecha == null || fecha.isEmpty || fecha == "---" || fecha.toLowerCase() == "nan") {
      return "Sin datos";
    }
    try {
      // ✅ MENTOR: Limpiamos cualquier rastro de horas (T o espacio)
      final String soloFecha = fecha.split('T').first.split(' ').first;
      final String f = soloFecha.replaceAll('/', '-').trim();
      
      final List<String> partes = f.split('-');
      if (partes.length == 3) {
        if (partes[0].length == 4) { // YYYY-MM-DD
          return "${partes[2].padLeft(2, '0')}/${partes[1].padLeft(2, '0')}/${partes[0]}";
        }
        return "${partes[0].padLeft(2, '0')}/${partes[1].padLeft(2, '0')}/${partes[2]}";
      }
      return soloFecha;
    } catch (e) { 
      return fecha; 
    }
  }

  // --- CÁLCULO DE DÍAS (PARA EL SEMÁFORO) ---
  static int calcularDiasRestantes(String? fecha) {
    if (fecha == null || fecha.isEmpty || fecha == "---" || fecha.toLowerCase() == "nan") {
      return 999;
    }
    try {
      // ✅ MENTOR: Aplicamos la misma limpieza de horas para evitar crasheos en el parseo
      final String soloFecha = fecha.split('T').first.split(' ').first;
      final String f = soloFecha.replaceAll('/', '-').trim();
      
      final List<String> partes = f.split('-');
      DateTime fVto;
      
      if (partes[0].length == 4) {
        fVto = DateTime.parse(f);
      } else {
        fVto = DateTime(
          int.parse(partes[2]), 
          int.parse(partes[1]), 
          int.parse(partes[0])
        );
      }
      
      final vtoNormalizado = DateTime(fVto.year, fVto.month, fVto.day);
      final ahora = DateTime.now();
      final hoyNormalizado = DateTime(ahora.year, ahora.month, ahora.day);
      
      return vtoNormalizado.difference(hoyNormalizado).inDays;
    } catch (_) { 
      return 999; 
    }
  }
}