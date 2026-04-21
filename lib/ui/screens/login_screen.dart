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

  @override
  void dispose() {
    _dniController.dispose();
    _passController.dispose();
    _dniFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // Limpieza de DNI: quitamos puntos o espacios por si acaso
    final String dni = _dniController.text.trim().replaceAll('.', '');
    final String pass = _passController.text.trim();
    
    if (dni.isEmpty || pass.isEmpty) {
      _mostrarError("Completá todos los campos para ingresar");
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      // Buscamos el legajo por DNI (que es el ID del documento)
      final doc = await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).get();
      
      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data()!;
        
        // VALIDACIÓN DE CONTRASEÑA (Soporta número o texto en Firebase)
        if (data['CONTRASEÑA'].toString() == pass) {
          
          final String nombre = data['NOMBRE'] ?? "Usuario";
          final String rol = data['ROL'] ?? "USUARIO";

          // --- GUARDAR SESIÓN LOCALMENTE ---
          await PrefsService.guardarUsuario(
            dni: dni,
            nombre: nombre,
            rol: rol,
          );

          if (!mounted) return;

          // NAVEGACIÓN REEMPLAZANDO LA PILA (Para que no puedan volver atrás al login)
          Navigator.pushReplacementNamed(
            context, 
            '/home', 
            arguments: {
              'dni': dni,
              'nombre': nombre,
              'rol': rol,
            },
          );
        } else {
          _mostrarError("Contraseña incorrecta. Verificá los datos.");
        }
      } else {
        _mostrarError("El DNI ingresado no está registrado en el sistema");
      }
    } catch (e) {
      if (mounted) {
        _mostrarError("Fallo de conexión o error de sistema: $e");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje), 
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimario = Theme.of(context).colorScheme.primary;

    return Scaffold(
      resizeToAvoidBottomInset: true, 
      body: Stack(
        children: [
          // IMAGEN DE FONDO
          Positioned.fill(
            child: Image.asset(
              'assets/images/fondo_login.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => 
                  Container(color: const Color(0xFF0D1D2D)),
            ),
          ),
          
          // OVERLAY OSCURO
          Positioned.fill(
            child: Container(color: Colors.black.withAlpha(140)),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Container(
                width: 420, // Ajuste para pantallas Desktop (Windows)
                padding: const EdgeInsets.all(35),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(245), 
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(100),
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
                      style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                    const SizedBox(height: 45),
                    
                    // CAMPO DNI (ID DE DOCUMENTO)
                    TextField(
                      controller: _dniController,
                      focusNode: _dniFocus,
                      autofocus: true, 
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: "DNI (Usuario)",
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      onSubmitted: (_) => FocusScope.of(context).requestFocus(_passFocus),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // CAMPO CONTRASEÑA
                    TextField(
                      controller: _passController,
                      focusNode: _passFocus,
                      obscureText: true,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        labelText: "Contraseña",
                        prefixIcon: const Icon(Icons.lock_person_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // BOTÓN DE ACCESO BLINDADO
                    _isLoading 
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 60),
                          backgroundColor: colorPrimario,
                          foregroundColor: Colors.white,
                          elevation: 8,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        onPressed: _login,
                        child: const Text(
                          "INICIAR SESIÓN", 
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                        ),
                      ),
                    const SizedBox(height: 15),
                    const Text(
                      "v2.0.26 - Bahía Blanca, Argentina",
                      style: TextStyle(color: Colors.grey, fontSize: 10),
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}