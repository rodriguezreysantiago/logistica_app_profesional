import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static late SharedPreferences _prefs;

  // ESTO SE LLAMA EN EL MAIN ANTES DEL RUNAPP
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // GUARDAR DATOS DEL LOGIN
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

  // OBTENER DATOS
  static String get dni => _prefs.getString('dni') ?? "";
  static String get nombre => _prefs.getString('nombre') ?? "";
  static String get rol => _prefs.getString('rol') ?? "";
  static bool get isLoggedIn => _prefs.getBool('isLoggedIn') ?? false;

  // CERRAR SESIÓN
  static Future<void> clear() async {
    // ✅ Mentora: Eliminación quirúrgica. Solo borramos los datos del usuario.
    // Así preservamos otras futuras configuraciones (ej: themeMode, notificaciones).
    await _prefs.remove('dni');
    await _prefs.remove('nombre');
    await _prefs.remove('rol');
    await _prefs.setBool('isLoggedIn', false); 
  }
}