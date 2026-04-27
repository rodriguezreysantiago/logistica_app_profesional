import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static late SharedPreferences _prefs;

  // ✅ MEJORA PRO: Claves centralizadas para evitar errores de tipeo (Magic Strings)
  static const String _keyDni = 'dni';
  static const String _keyNombre = 'nombre';
  static const String _keyRol = 'rol';
  static const String _keyIsLoggedIn = 'isLoggedIn';

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
    await _prefs.setString(_keyDni, dni);
    await _prefs.setString(_keyNombre, nombre);
    await _prefs.setString(_keyRol, rol);
    await _prefs.setBool(_keyIsLoggedIn, true);
  }

  // Obtener datos guardados (Lectura segura)
  static String get dni => _prefs.getString(_keyDni) ?? '';
  static String get nombre => _prefs.getString(_keyNombre) ?? '';
  static String get rol => _prefs.getString(_keyRol) ?? '';
  static bool get isLoggedIn => _prefs.getBool(_keyIsLoggedIn) ?? false;

  // Cerrar sesión (nombre más claro y borrado seguro)
  static Future<void> limpiarSesion() async {
    await _prefs.remove(_keyDni);
    await _prefs.remove(_keyNombre);
    await _prefs.remove(_keyRol);
    // Aseguramos que el flag de logueo pase explícitamente a false
    await _prefs.setBool(_keyIsLoggedIn, false); 
  }

  // Compatibilidad con código anterior (por si lo usaste en otras pantallas)
  static Future<void> clear() async {
    await limpiarSesion();
  }
}