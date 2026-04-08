import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

      if (doc.exists && doc.data()!['CLAVE'].toString() == pass) {
        Navigator.pushReplacementNamed(
          context, 
          '/home', 
          arguments: {
            'dni': dni,
            'nombre': doc.data()!['CHOFER'] ?? "Usuario",
            'rol': doc.data()!['ROL'] ?? "USUARIO",
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("DNI o Clave incorrectos"))
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error de conexión: $e"))
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimario = Theme.of(context).colorScheme.primary;

    return Scaffold(
      // Evita que el fondo se deforme cuando aparece el teclado
      resizeToAvoidBottomInset: false, 
      body: Stack(
        children: [
          // 1. Imagen de Fondo (Colores originales)
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
          
          // --- SE ELIMINÓ EL CONTAINER AZUL QUE MODIFICABA LOS COLORES ---

          // 2. Formulario centralizado
          Center(
            child: SingleChildScrollView(
              child: Container(
                width: 400,
                // Margen para pantallas pequeñas
                margin: const EdgeInsets.symmetric(horizontal: 20), 
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  // Blanco con opacidad alta para no ensuciar la imagen de fondo
                  color: Colors.white.withValues(alpha: 0.9), 
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
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
                    
                    // --- CAMPO DNI ---
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
                    
                    // --- CAMPO CONTRASEÑA ---
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