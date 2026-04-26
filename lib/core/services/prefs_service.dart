import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static late SharedPreferences _prefs;

  // Inicializar antes del runApp
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Guardar datos del login
  static Future<void> guardarUsuario({
    required String dni,
    required String nombre,
    required String rol,
  }) async {
    await _prefs.setString('dni', dni);
    await _prefs.setString('nombre', nombre);
    await _prefs.setString('rol', rol);
    await _prefs.setBool('isLoggedIn', true);
  }

  // Obtener datos guardados
  static String get dni => _prefs.getString('dni') ?? '';
  static String get nombre => _prefs.getString('nombre') ?? '';
  static String get rol => _prefs.getString('rol') ?? '';
  static bool get isLoggedIn => _prefs.getBool('isLoggedIn') ?? false;

  // Cerrar sesión (nombre más claro)
  static Future<void> limpiarSesion() async {
    await _prefs.remove('dni');
    await _prefs.remove('nombre');
    await _prefs.remove('rol');
    await _prefs.setBool('isLoggedIn', false);
  }

  // Compatibilidad con código anterior
  static Future<void> clear() async {
    await limpiarSesion();
  }
}
