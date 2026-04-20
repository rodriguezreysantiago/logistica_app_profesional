import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/services/prefs_service.dart'; // <--- IMPORTANTE: TU NUEVO SERVICIO

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
    final String dni = _dniController.text.trim();
    final String pass = _passController.text.trim();
    if (dni.isEmpty || pass.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('EMPLEADOS').doc(dni).get();
      
      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data()!;
        
        // VALIDACIÓN CONTRA EL CAMPO 'CONTRASEÑA'
        if (data['CONTRASEÑA'].toString() == pass) {
          
          // --- NUEVO: GUARDAR SESIÓN LOCALMENTE ---
          await PrefsService.guardarUsuario(
            dni: dni,
            nombre: data['NOMBRE'] ?? "Usuario",
            rol: data['ROL'] ?? "USUARIO",
          );

          if (!mounted) return;

          Navigator.pushReplacementNamed(
            context, 
            '/home', 
            arguments: {
              'dni': dni,
              'nombre': data['NOMBRE'] ?? "Usuario",
              'rol': data['ROL'] ?? "USUARIO",
            },
          );
        } else {
          _mostrarError("DNI o Contraseña incorrectos");
        }
      } else {
        _mostrarError("El usuario no existe");
      }
    } catch (e) {
      if (mounted) {
        _mostrarError("Error de conexión: $e");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.redAccent)
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimario = Theme.of(context).colorScheme.primary;

    return Scaffold(
      resizeToAvoidBottomInset: false, 
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/fondo_login.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          
          Center(
            child: SingleChildScrollView(
              child: Container(
                width: 400,
                margin: const EdgeInsets.symmetric(horizontal: 20), 
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(230), 
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(50),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "S.M.A.R.T.",
                      style: TextStyle(
                        fontSize: 32, 
                        fontWeight: FontWeight.bold, 
                        color: colorPrimario,
                        letterSpacing: 4
                      ),
                    ),
                    const Text(
                      "Logística y Monitoreo", 
                      style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w500)
                    ),
                    const SizedBox(height: 35),
                    
                    TextField(
                      controller: _dniController,
                      focusNode: _dniFocus,
                      autofocus: true, 
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "DNI",
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white54,
                      ),
                      onSubmitted: (_) => FocusScope.of(context).requestFocus(_passFocus),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    TextField(
                      controller: _passController,
                      focusNode: _passFocus,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Contraseña",
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white54,
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    
                    const SizedBox(height: 35),
                    
                    _isLoading 
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 55),
                          backgroundColor: colorPrimario,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        onPressed: _login,
                        child: const Text(
                          "INGRESAR", 
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                        ),
                      ),
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