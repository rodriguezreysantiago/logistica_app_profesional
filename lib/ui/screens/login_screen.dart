import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/services/prefs_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _dniController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  
  final FocusNode _dniFocus = FocusNode(); 
  final FocusNode _passFocus = FocusNode();
  
  bool _isLoading = false;
  bool _obscurePass = true; // ✅ MENTOR: Variable para controlar la visibilidad de la contraseña

  @override
  void dispose() {
    _dniController.dispose();
    _passController.dispose();
    _dniFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final String dni = _dniController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final String pass = _passController.text.trim();
    
    if (dni.isEmpty || pass.isEmpty) {
      _mostrarError(messenger, "Completá todos los campos para ingresar");
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final doc = await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).get();
      
      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data()!;
        
        if (data['CONTRASEÑA'].toString() == pass) {
          
          final String nombre = data['NOMBRE'] ?? "Usuario";
          final String rol = data['ROL'] ?? "USUARIO";

          await PrefsService.guardarUsuario(
            dni: dni,
            nombre: nombre,
            rol: rol,
          );

          if (!mounted) return;

          navigator.pushReplacementNamed(
            '/home', 
            arguments: {
              'dni': dni,
              'nombre': nombre,
              'rol': rol,
            },
          );
        } else {
          _mostrarError(messenger, "Contraseña incorrecta. Verificá los datos.");
        }
      } else {
        _mostrarError(messenger, "El DNI ingresado no está registrado en el sistema");
      }
    } catch (e) {
      if (mounted) {
        _mostrarError(messenger, "Fallo de conexión o error de sistema: $e");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarError(ScaffoldMessengerState messenger, String mensaje) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(mensaje, style: const TextStyle(fontWeight: FontWeight.bold)), 
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimario = Theme.of(context).colorScheme.primary;

    // ✅ MENTOR: GestureDetector envuelve el Scaffold para ocultar el teclado al tocar fuera
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true, 
        body: Stack(
          children: [
            // IMAGEN DE FONDO
            Positioned.fill(
              child: Image.asset(
                'assets/images/fondo_login.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => 
                    Container(color: Theme.of(context).scaffoldBackgroundColor),
              ),
            ),
            
            // OVERLAY OSCURO
            Positioned.fill(
              child: Container(color: Colors.black.withAlpha(180)), // Un poco más oscuro para mejor contraste
            ),

            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Container(
                  width: 420, 
                  padding: const EdgeInsets.all(35),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface, // ✅ MENTOR: Adaptado al tema oscuro
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: colorPrimario.withAlpha(30)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(150),
                        blurRadius: 25,
                        offset: const Offset(0, 15),
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // LOGOTIPO S.M.A.R.T.
                      Text(
                        "S.M.A.R.T.",
                        style: TextStyle(
                          fontSize: 38, 
                          fontWeight: FontWeight.bold, 
                          color: colorPrimario,
                          letterSpacing: 6
                        ),
                      ),
                      const Text(
                        "CONTROL DE LOGÍSTICA PROFESIONAL", 
                        style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 45),
                      
                      // CAMPO DNI (ID DE DOCUMENTO)
                      TextField(
                        controller: _dniController,
                        focusNode: _dniFocus,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: "DNI (Usuario)",
                          prefixIcon: Icon(Icons.person_outline, color: colorPrimario),
                        ),
                        onSubmitted: (_) => FocusScope.of(context).requestFocus(_passFocus),
                      ),
                      
                      const SizedBox(height: 25),
                      
                      // CAMPO CONTRASEÑA
                      TextField(
                        controller: _passController,
                        focusNode: _passFocus,
                        obscureText: _obscurePass, // ✅ MENTOR: Estado de visibilidad
                        style: const TextStyle(fontSize: 18, color: Colors.white),
                        decoration: InputDecoration(
                          labelText: "Contraseña",
                          prefixIcon: Icon(Icons.lock_outline, color: colorPrimario),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePass ? Icons.visibility_off : Icons.visibility,
                              color: Colors.white38,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePass = !_obscurePass;
                              });
                            },
                          ),
                        ),
                        onSubmitted: (_) => _login(),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // BOTÓN DE ACCESO BLINDADO
                      _isLoading 
                      ? CircularProgressIndicator(color: colorPrimario)
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 60),
                            backgroundColor: colorPrimario,
                            foregroundColor: Colors.black, // Contraste oscuro sobre verde/naranja
                            elevation: 8,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                          onPressed: _login,
                          child: const Text(
                            "INICIAR SESIÓN", 
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)
                          ),
                        ),
                      const SizedBox(height: 25),
                      const Text(
                        "v2.0.26 - Bahía Blanca, Argentina",
                        style: TextStyle(color: Colors.white24, fontSize: 10),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}