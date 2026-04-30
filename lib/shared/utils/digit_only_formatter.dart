import 'package:flutter/services.dart';

/// `TextInputFormatter` que descarta cualquier carácter que no sea
/// dígito 0-9.
///
/// Pensado para campos como DNI, CUIL, teléfono, código postal — donde
/// `keyboardType: TextInputType.number` ayuda en mobile pero **no
/// alcanza** porque:
///
/// - En desktop / web los teclados físicos dejan tipear cualquier letra.
/// - En Android algunas teclas IME inyectan caracteres no numéricos
///   (espacios, "-", "(", etc.) cuando el usuario activa el modo texto.
/// - Pegar (paste) desde el clipboard nunca pasa por el `keyboardType`.
///
/// Este formatter es la red de seguridad real para garantizar que el
/// dato persistido en Firestore sea solo dígitos.
///
/// Uso:
/// ```dart
/// TextFormField(
///   keyboardType: TextInputType.number,
///   inputFormatters: [DigitOnlyFormatter()],
///   ...
/// )
/// ```
class DigitOnlyFormatter extends TextInputFormatter {
  /// Si se pasa un [maxLength], el formatter trunca a esa longitud
  /// (útil para DNI 8 dígitos, CUIL 11 dígitos). Si no, no impone límite.
  /// Igualmente conviene usar `maxLength` del `TextFormField` para que
  /// se vea el contador y la UI lo respete visualmente.
  final int? maxLength;

  DigitOnlyFormatter({this.maxLength});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Filtro estricto: cualquier carácter que no sea \d se descarta.
    var limpio = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (maxLength != null && limpio.length > maxLength!) {
      limpio = limpio.substring(0, maxLength!);
    }

    // Recalculamos la posición del cursor: el offset original puede
    // haber quedado más allá del nuevo largo si descartamos chars.
    final offset = limpio.length < newValue.selection.baseOffset
        ? limpio.length
        : newValue.selection.baseOffset;

    return TextEditingValue(
      text: limpio,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
