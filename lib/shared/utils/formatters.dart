class AppFormatters {
  // ✅ MEJORA PRO: Constructor privado para evitar instanciaciones innecesarias
  AppFormatters._();

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

  // ===========================================================================
  // ✅ MEJORA PRO: HELPER PRIVADO PARA PARSEO UNIVERSAL DE FECHAS
  // ===========================================================================
  static DateTime? _parseUniversalDate(dynamic fecha) {
    if (fecha == null || fecha.toString().isEmpty || fecha == "---" || fecha.toString().toLowerCase() == "nan") {
      return null;
    }
    
    if (fecha is DateTime) return fecha;

    // Usamos tryParse en lugar de parse para no depender de excepciones
    // como flujo de control. Mismo resultado, sin throw + catch.
    try {
      final String stringFecha = fecha.toString();
      final String soloFecha = stringFecha.split('T').first.split(' ').first;
      final String f = soloFecha.replaceAll('/', '-').trim();

      final List<String> partes = f.split('-');
      if (partes.length == 3) {
        if (partes[0].length == 4) {
          // Formato YYYY-MM-DD (ISO).
          //
          // **Bug histórico fixeado**: antes hacíamos `DateTime.tryParse(f)`
          // que en Dart parsea "2026-05-30" como UTC midnight. En zonas
          // negativas (ART = UTC-3), al hacer `.toLocal()` o usar el
          // DateTime en operaciones con DateTime.now() (que es local)
          // el día se "atrasa" — la licencia que vence el 30/05 se
          // mostraba como 29/05.
          //
          // Ahora construimos DateTime local explícito con los
          // componentes manualmente, sin pasar por tryParse.
          final anio = int.tryParse(partes[0]);
          final mes = int.tryParse(partes[1]);
          final dia = int.tryParse(partes[2]);
          if (anio != null && mes != null && dia != null) {
            return DateTime(anio, mes, dia);
          }
          return null;
        }
        // Formato DD-MM-YYYY: parseamos cada componente con tryParse.
        final dia = int.tryParse(partes[0]);
        final mes = int.tryParse(partes[1]);
        final anio = int.tryParse(partes[2]);
        if (dia != null && mes != null && anio != null) {
          return DateTime(anio, mes, dia);
        }
      }
    } catch (_) {
      // Cualquier formato no contemplado → null
    }
    return null;
  }

  // --- FORMATEAR FECHA (DD/MM/YYYY) ---
  static String formatearFecha(dynamic fecha) {
    final DateTime? parsed = _parseUniversalDate(fec