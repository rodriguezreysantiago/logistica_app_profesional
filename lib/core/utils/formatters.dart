class AppFormatters {
  // --- FORMATEAR KILOMETRAJE (1.232.232,0) ---
  static String formatearKilometraje(dynamic valor) {
    if (valor == null || valor == 0 || valor == "0" || valor == "" || valor == "nan") return "0,0";
    
    try {
      // ✅ Mentora: Limpieza robusta. Nos quedamos solo con números y el punto decimal.
      String raw = valor.toString().replaceAll(',', '.'); 
      double numero = double.parse(raw);
      
      // 1. Convertimos a String con 1 decimal y cambiamos punto por coma
      String fixed = numero.toStringAsFixed(1).replaceAll('.', ',');
      
      // 2. Separamos la parte entera de la decimal
      List<String> partes = fixed.split(',');
      String entera = partes[0];
      String decimal = partes[1];

      // 3. Agregamos los puntos de miles a la parte entera usando Regex
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
    if (fecha == null || fecha.isEmpty || fecha == "---" || fecha == "nan") {
      return "Sin datos";
    }
    try {
      final String f = fecha.replaceAll('/', '-').trim();
      final List<String> partes = f.split('-');
      if (partes.length == 3) {
        if (partes[0].length == 4) { // YYYY-MM-DD
          return "${partes[2].padLeft(2, '0')}/${partes[1].padLeft(2, '0')}/${partes[0]}";
        }
        return "${partes[0].padLeft(2, '0')}/${partes[1].padLeft(2, '0')}/${partes[2]}";
      }
      return fecha;
    } catch (e) { 
      return fecha; 
    }
  }

  // --- CÁLCULO DE DÍAS (PARA EL SEMÁFORO) ---
  static int calcularDiasRestantes(String? fecha) {
    if (fecha == null || fecha.isEmpty || fecha == "---" || fecha == "nan") {
      return 999;
    }
    try {
      final String f = fecha.replaceAll('/', '-').trim();
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
      
      // ✅ Mentora: Normalizamos AMBAS fechas a las 00:00:00 para que el cálculo sea exacto
      final vtoNormalizado = DateTime(fVto.year, fVto.month, fVto.day);
      final ahora = DateTime.now();
      final hoyNormalizado = DateTime(ahora.year, ahora.month, ahora.day);
      
      return vtoNormalizado.difference(hoyNormalizado).inDays;
    } catch (_) { 
      return 999; 
    }
  }
}