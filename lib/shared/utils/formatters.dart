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

  /// Alias publico de `_parseUniversalDate`. Util cuando el caller
  /// quiere un `DateTime?` y ya esta usando `AppFormatters` para otras
  /// cosas. Acepta multiples formatos (ISO YYYY-MM-DD, DD-MM-YYYY,
  /// DD/MM/YYYY, DateTime nativo) y devuelve null si no parsea.
  ///
  /// Preferir esto sobre `DateTime.tryParse(s)` directo cuando se
  /// parsean campos `VENCIMIENTO_*` o `ULTIMO_SERVICE_FECHA` cuyo
  /// formato historico puede variar (siempre se guarda ISO desde la
  /// app, pero migraciones viejas o ediciones manuales en console
  /// pudieron dejar DD/MM en la BD).
  static DateTime? tryParseFecha(dynamic fecha) =>
      _parseUniversalDate(fecha);

  /// Devuelve `YYYY-MM-DD` usando los componentes LOCALES del DateTime.
  ///
  /// Reemplazo seguro de los patrones:
  ///   - `dt.toString().split(' ').first` (funciona si dt es local,
  ///     pero rompe si es UTC -- te da el dia anterior en TZ ART).
  ///   - `dt.toIso8601String().split('T').first` (siempre devuelve
  ///     componentes UTC -- entre 21:00 y 23:59 ART te da el dia
  ///     siguiente).
  ///
  /// Uso tipico: convertir el DateTime que devuelve `pickFecha(...)` a
  /// string para guardarlo en Firestore en el campo VENCIMIENTO_*.
  /// Asi no importa si el DateTime es local, UTC o vino de un parse
  /// raro -- siempre se guarda el dia que el admin tipeo.
  static String aIsoFechaLocal(DateTime d) {
    final l = d.isUtc ? d.toLocal() : d;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }

  // --- FORMATEAR FECHA (DD/MM/YYYY) ---
  static String formatearFecha(dynamic fecha) {
    final DateTime? parsed = _parseUniversalDate(fecha);

    if (parsed != null) {
      return "${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}";
    }

    // Si no pudo parsear, devuelve lo que ingresó por defecto
    return fecha?.toString() ?? "Sin datos";
  }

  /// Formatea un DateTime como `HH:mm` (default) o `HH:mm:ss` en hora local.
  ///
  /// Útil para mostrar SOLO la hora — para fecha + hora completa usar
  /// [formatearFechaHora]. Si el DateTime es UTC, lo convierte a local
  /// antes de formatear.
  ///
  /// Reemplaza el patrón duplicado `_formatHora` que vivía privado en
  /// pantallas que solo necesitaban formatear hora rápido (ej. timeline
  /// del Sync Dashboard).
  static String formatearHora(DateTime fecha, {bool conSegundos = false}) {
    final l = fecha.isUtc ? fecha.toLocal() : fecha;
    String two(int n) => n.toString().padLeft(2, '0');
    final base = '${two(l.hour)}:${two(l.minute)}';
    return conSegundos ? '$base:${two(l.second)}' : base;
  }

  /// Formatea un DateTime como `DD/MM/YYYY HH:mm:ss` en hora local.
  ///
  /// Reemplazo seguro de `.toIso8601String()` para cualquier display que
  /// le llegue al usuario (logs en pantalla, debug snapshots, etc.). ISO
  /// expone formato técnico (`2026-05-03T23:45:32.123`) que en AR no se
  /// reconoce y obliga al usuario a calcular TZ mentalmente.
  ///
  /// Si el DateTime es UTC, lo convierte a local antes de formatear.
  /// Acepta `null` y devuelve "—" como placeholder consistente con la
  /// UI del resto de la app.
  static String formatearFechaHora(DateTime? fecha) {
    if (fecha == null) return '—';
    final l = fecha.isUtc ? fecha.toLocal() : fecha;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} '
        '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  // --- CÁLCULO DE DÍAS (PARA EL SEMÁFORO) ---
  //
  // Devuelve `null` cuando no se pudo parsear la fecha (input vacío,
  // null, "---", o string corrupto). Antes devolvía sentinel `999`
  // -- el caller lo interpretaba como "muy lejos en el futuro" y el
  // badge lo pintaba verde "OK", silenciando alarmas cuando un campo
  // VENCIMIENTO_X tenia valor invalido por typo en la consola.
  // Ahora null obliga al caller a tri-state: sin fecha / invalida / valida.
  static int? calcularDiasRestantes(dynamic fecha) {
    final DateTime? fVto = _parseUniversalDate(fecha);
    if (fVto == null) return null;

    final vtoNormalizado = DateTime(fVto.year, fVto.month, fVto.day);
    final ahora = DateTime.now();
    final hoyNormalizado = DateTime(ahora.year, ahora.month, ahora.day);
    return vtoNormalizado.difference(hoyNormalizado).inDays;
  }
}
