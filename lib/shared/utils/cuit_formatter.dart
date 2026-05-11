import 'package:flutter/services.dart';

/// Input formatter para CUIT/CUIL argentino — el usuario tipea solo
/// dígitos de corrido y el formatter inserta los guiones automáticos
/// mientras escribe:
///
///   tipea "20"          → muestra "20"
///   tipea "20123"       → muestra "20-123"
///   tipea "2012345678"  → muestra "20-12345678"
///   tipea "20123456789" → muestra "20-12345678-9"
///
/// Máximo 11 dígitos (formato AR). Cualquier caracter no-numérico
/// pegado o tipeado se ignora. Si el usuario borra, el formatter
/// reconstruye el formato desde los dígitos restantes.
///
/// Uso típico en un TextField:
/// ```dart
/// TextField(
///   keyboardType: TextInputType.number,
///   inputFormatters: [CuitInputFormatter()],
/// )
/// ```
///
/// Para deserializar (sacar guiones antes de persistir/comparar), usar
/// [CuitInputFormatter.soloDigitos].
class CuitInputFormatter extends TextInputFormatter {
  /// Largo máximo del CUIT/CUIL argentino: 11 dígitos.
  static const int maxDigitos = 11;

  /// Quita guiones, espacios, puntos — devuelve solo los dígitos.
  /// Útil para comparar dos CUITs ignorando cómo los tipearon.
  static String soloDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Formatea un string de dígitos como CUIT con guiones.
  /// `"20123456789"` → `"20-12345678-9"`. Acepta entradas ya
  /// formateadas (les saca los guiones primero) o parciales.
  static String formatear(String input) {
    final d = soloDigitos(input);
    final digits = d.length > maxDigitos ? d.substring(0, maxDigitos) : d;
    if (digits.length <= 2) return digits;
    if (digits.length <= 10) {
      return '${digits.substring(0, 2)}-${digits.substring(2)}';
    }
    return '${digits.substring(0, 2)}-'
        '${digits.substring(2, 10)}-'
        '${digits.substring(10)}';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatear(newValue.text);
    // Cursor siempre al final — los TextEditingValue con selection
    // intermedia complican el tipeo (cursor que salta al meter el
    // guion automático). Mantener al final es lo que la mayoría de
    // formatters de máscara hacen y es suficiente para CUIT que se
    // tipea siempre de izquierda a derecha.
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
