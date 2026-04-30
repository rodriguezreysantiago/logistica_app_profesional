// El smoke test default de Flutter (counter app) se eliminó porque
// `LogisticaApp` necesita Firebase, providers y SharedPreferences
// inicializados — no se puede pumpar sin un harness más completo.
//
// Los tests útiles de la app son unitarios y viven en archivos vecinos:
// - password_hasher_test.dart
// - ocr_service_test.dart
//
// Cuando agreguemos widget tests reales, conviene crear un harness
// `test/helpers/test_app.dart` que monte un MultiProvider con mocks
// de Firebase / Firestore (usando fake_cloud_firestore o similar).
//
// Por ahora dejamos un test trivial para que `flutter test` no se queje
// de un archivo vacío.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder — la suite de widgets vive en archivos hermanos', () {
    expect(2 + 2, 4);
  });
}
