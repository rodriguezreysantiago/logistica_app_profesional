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
  
  // Nodos de foco para controlar el teclado
  final FocusNode _dniFocus = FocusNode(); 
  final FocusNode _passFocus = FocusNode();
  
  bool _isLoading = false;

  @override
  void dispose() {
    // Limpiamos los controladores y nodos al cerrar la pantalla
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
      body: Stack(
        children: [
          // 1. Imagen de Fondo
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/fondo_login.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // 2. Filtro oscuro (Corregido a WithOpacity para mejor compatibilidad)
          Container(color: Colors.blue.withValues(alpha:0.5)),
          
          // 3. Formulario
          Center(
            child: SingleChildScrollView(
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.85),
                  borderRadius: BorderRadius.circular(20),
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
                    const Text("Logística y Monitoreo", style: TextStyle(color: Colors.blueGrey)),
                    const SizedBox(height: 30),
                    
                    // --- CAMPO DNI ---
                    TextField(
                      controller: _dniController,
                      focusNode: _dniFocus,
                      autofocus: true, // ✅ ESTO ACTIVA EL TECLADO AL ENTRAR
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "DNI",
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
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
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    _isLoading 
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          backgroundColor: colorPrimario,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _login,
                        child: const Text("INGRESAR"),
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