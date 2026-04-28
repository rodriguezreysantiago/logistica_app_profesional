import 'package:flutter/services.dart';

/// Formatter que convierte el texto del campo a MAYÚSCULAS a medida que
/// se tipea, **respetando la posición del cursor y el borrado**.
///
/// ## Por qué no usar `textCapitalization: TextCapitalization.characters`
///
/// El flag `TextCapitalization.characters` está pensado para teclados
/// virtuales (mobile): le indica al sistema operativo que el teclado
/// debe mostrar las mayúsculas. En Windows desktop con teclado físico
/// causa un bug conocido: el handler que hace la conversión "se come"
/// la tecla **Backspace**, dejando al usuario sin poder borrar.
///
/// Este formatter es la alternativa que **sí funciona en desktop**:
/// solo transforma el texto a mayúsculas, sin tocar selección ni
/// keystroke handling. Backspace, Delete y cualquier otra tecla siguen
/// funcionando normal.
///
/// Uso:
/// ```dart
/// TextField(
///   controller: ctrl,
///   inputFormatters: [UpperCaseInputFormatter()],
/// )
/// ```
class UpperCaseInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: newValue.composing,
    );
  }
}
