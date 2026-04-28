import 'package:flutter/services.dart';

/// Formatter para campos de fecha tipeable en formato DD/MM/YYYY.
///
/// Acepta solo dígitos y va insertando las barras automáticamente:
/// - "12"        → "12"
/// - "1234"      → "12/34"
/// - "12345678"  → "12/34/5678"
///
/// Limita la longitud a 8 dígitos (o sea: "DD/MM/YYYY").
///
/// **Importante**: el cursor se reposiciona en función de los dígitos
/// que había a su izquierda en el input crudo, NO siempre al final.
/// Si fuera siempre al final, el backspace no funciona en algunas
/// plataformas (Windows desktop, sobre todo): el sistema interpreta
/// el "salto" del cursor como un reemplazo total y aborta el evento
/// de borrado. Con el cursor estable, backspace y delete funcionan
/// como se esperan.
///
/// Uso:
/// ```dart
/// TextField(
///   controller: ctrl,
///   keyboardType: TextInputType.number,
///   inputFormatters: [FechaInputFormatter()],
/// )
/// ```
class FechaInputFormatter extends TextInputFormatter {
  static bool _esDigito(int code) => code >= 0x30 && code <= 0x39;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 1) Cuántos DÍGITOS había a la izquierda del cursor en el texto
    //    crudo que viene del usuario. Ese es el "anchor" lógico que
    //    queremos preservar después de reformatear.
    final cursorRaw =
        newValue.selection.baseOffset.clamp(0, newValue.text.length);
    int digitosAntesCursor = 0;
    for (int i = 0; i < cursorRaw; i++) {
      if (_esDigito(newValue.text.codeUnitAt(i))) {
        digitosAntesCursor++;
      }
    }

    // 2) Limpiamos a solo dígitos y truncamos a 8 (DDMMYYYY).
    var digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length > 8) digitos = digitos.substring(0, 8);
    if (digitosAntesCursor > digitos.length) {
      digitosAntesCursor = digitos.length;
    }

    // 3) Reconstruimos el texto formateado y, en paralelo, calculamos
    //    en qué offset del texto formateado corresponde estar el
    //    cursor (justo después del N-ésimo dígito).
    final buf = StringBuffer();
    int nuevoCursor = 0;
    for (int i = 0; i < digitos.length; i++) {
      buf.write(digitos[i]);
      // Si el i-ésimo dígito que acabamos de escribir es el que estaba
      // a la izquierda del cursor original, marcamos el offset acá.
      if (i + 1 == digitosAntesCursor) {
        nuevoCursor = buf.length;
      }
      if ((i == 1 || i == 3) && i != digitos.length - 1) {
        buf.write('/');
      }
    }
    // Edge case: cursor al inicio (no había dígitos a la izquierda).
    if (digitosAntesCursor == 0) nuevoCursor = 0;

    final stringFinal = buf.toString();
    // Defensivo: clamp por si el cálculo se desfasó por algún caso raro.
    final cursorClamped = nuevoCursor.clamp(0, stringFinal.length);

    return TextEditingValue(
      text: stringFinal,
      selection: TextSelection.collapsed(offset: cursorClamped),
    );
  }
}
