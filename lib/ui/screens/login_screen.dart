import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/auth_service.dart';

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

  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePass = true;

  @override
  void dispose() {
    _dniController.dispose();
    _passController.dispose();
    _dniFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final String dni = _dniController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final String pass = _passController.text.trim();

    if (dni.isEmpty || pass.isEmpty) {
      _mostrarError(messenger, "Completá todos los campos para ingresar");
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authService.login(
      dni: dni,
      password: pass,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result.success) {
      navigator.pushReplacementNamed(
        '/home',
        arguments: {
          'dni': result.dni,
          'nombre': result.nombre,
          'rol': result.rol,
        },
      );
    } else {
      _mostrarError(
        messenger,
        result.message ?? "No se pudo iniciar sesión",
      );
    }
  }

  void _mostrarError(ScaffoldMessengerState messenger, String mensaje) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorPrimario = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/fondo_login.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Container(color: Theme.of(context).scaffoldBackgroundColor),
              ),
            ),
            Positioned.fill(
              child: Container(
                color: Colors.black.withAlpha(180),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Container(
                  width: 420,
                  padding: const EdgeInsets.all(35),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: colorPrimario.withAlpha(30),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(150),
                        blurRadius: 25,
                        offset: const Offset(0, 15),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "S.M.A.R.T.",
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          color: colorPrimario,
                          letterSpacing: 6,
                        ),
                      ),
                      const Text(
                        "CONTROL DE LOGÍSTICA PROFESIONAL",
                        style: TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 45),
                      TextField(
                        controller: _dniController,
                        focusNode: _dniFocus,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          labelText: "DNI (Usuario)",
                          prefixIcon: Icon(
                            Icons.person_outline,
                            color: colorPrimario,
                          ),
                        ),
                        onSubmitted: (_) {
                          FocusScope.of(context).requestFocus(_passFocus);
                        },
                      ),
                      const SizedBox(height: 25),
                      TextField(
                        controller: _passController,
                        focusNode: _passFocus,
                        obscureText: _obscurePass,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                        ),
                        decoration: InputDecoration(
                          labelText: "Contraseña",
                          prefixIcon: Icon(
                            Icons.lock_outline,
                            color: colorPrimario,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePass
                                  ? Icons.visibility_off
                                  : Icons.visibility,
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
                      _isLoading
                          ? CircularProgressIndicator(color: colorPrimario)
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 60),
                                backgroundColor: colorPrimario,
                                foregroundColor: Colors.black,
                                elevation: 8,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              onPressed: _isLoading ? null : _login,
                              child: const Text(
                                "INICIAR SESIÓN",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                      const SizedBox(height: 25),
                      const Text(
                        "v2.0.26 - Bahía Blanca, Argentina",
                        style: TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                        ),
                      ),
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
