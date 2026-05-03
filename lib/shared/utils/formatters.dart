import 'package:flutter/services.dart';

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

  /// Formatea un número con `.` como separador de miles, formato AR:
  /// - `formatearMiles(123456789)` → `"123.456.789"` (entero, sin decimales).
  /// - `formatearMiles(123456789.5, decimales: 2)` → `"123.456.789,50"`.
  /// - `formatearMonto(45000)` → `"45.000,00"` (siempre 2 decimales, plata).
  ///
  /// Usar para km, contadores, lecturas de odómetro — cualquier entero
  /// ≥ 1000 que el operador tenga que leer rápido. Para plata, preferir
  /// `formatearMonto` que fuerza `,00` para consistencia visual.
  ///
  /// Aceptamos `num?` para que el caller no tenga que castear. Null → `"—"`.
  static String formatearMiles(num? valor, {int decimales = 0}) {
    if (valor == null) return '—';
    final negativo = valor < 0;
    final abs = valor.abs();
    final entero = abs.truncate();
    final s = entero.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final parteEntera = s.replaceAllMapped(reg, (m) => '${m[1]}.');
    String resultado;
    if (decimales > 0) {
      // toStringAsFixed redondea correctamente y siempre rellena con 0.
      final decStr = abs.toStringAsFixed(decimales).split('.').last;
      resultado = '$parteEntera,$decStr';
    } else {
      resultado = parteEntera;
    }
    return negativo ? '-$resultado' : resultado;
  }

  /// Formato AR para montos en pesos: siempre 2 decimales con `,` y
  /// miles con `.` (`123456.5 → "123.456,50"`, `45000 → "45.000,00"`).
  /// No agrega símbolo `$` — el caller lo prepende si lo necesita
  /// (algunas pantallas usan label "Costo ($)" en vez del símbolo en
  /// el valor).
  static String formatearMonto(num? valor) =>
      formatearMiles(valor, decimales: 2);

  /// `TextInputFormatter` que reformatea el input en vivo a estilo AR
  /// con `.` como separador de miles: el usuario tipea `200000` y ve
  /// `200.000`; sigue escribiendo y ve `2.000.000`. Solo acepta
  /// dígitos — todo otro caracter se descarta.
  ///
  /// Para leer el valor numérico del controller, usar
  /// `parsearMiles(controller.text)` (acepta el string formateado o
  /// uno crudo sin puntos).
  ///
  /// Limitación: no soporta decimales — pensado para enteros (km,
  /// pesos enteros). Si hace falta decimal, agregar variante separada
  /// para no complicar el cursor handling.
  static final TextInputFormatter inputMiles = _MilesInputFormatter();

  /// Parsea un string formateado con `.` (ej. "200.000") a `int`. Si
  /// el string viene sin separadores (ej. "200000") también funciona.
  /// Devuelve `null` si está vacío o no es numérico.
  static int? parsearMiles(String? texto) {
    if (texto == null) return null;
    final limpio = texto.replaceAll('.', '').trim();
    if (limpio.isEmpty) return null;
    return int.tryParse(limpio);
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

/// Implementación interna del input formatter expuesto como
/// `AppFormatters.inputMiles`. Mantengo la clase privada al archivo —
/// el caller siempre pasa por el helper estático.
///
/// Estrategia para preservar la posición del cursor: contamos cuántos
/// dígitos había antes del cursor en el texto crudo, reformateamos, y
/// reposicionamos el cursor para que quede después del mismo número
/// de dígitos. Si no se hiciera esto, el cursor "salta" al final cada
/// vez que se inserta un punto.
class _MilesInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Solo dígitos.
    final soloDigitos = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (soloDigitos.isEmpty) {
      return const TextEditingValue(text: '');
    }
    // Cuántos dígitos hay antes de la posición del cursor en el nuevo
    // texto (ignorando los puntos que quedaron a la izquierda).
    final cursorRaw = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitosAntesCursor = newValue.text
        .substring(0, cursorRaw)
        .replaceAll(RegExp(r'\D'), '')
        .length;

    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = soloDigitos.replaceAllMapped(reg, (m) => '${m[1]}.');

    // Reposicionar el cursor: avanzar por `formateado` saltando puntos
    // hasta haber pasado `digitosAntesCursor` dígitos.
    var nuevoCursor = 0;
    var contador = 0;
    while (contador < digitosAntesCursor && nuevoCursor < formateado.length) {
      if (formateado[nuevoCursor] != '.') contador++;
      nuevoCursor++;
    }

    return TextEditingValue(
      text: formateado,
      selection: TextSelection.collapsed(offset: nuevoCursor),
    );
  }
}
