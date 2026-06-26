import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/supabase_service.dart';
import '../services/app_state.dart';
import '../theme/exodo_theme.dart';

bool _isAuthEn(BuildContext context) {
  try {
    if (ui.PlatformDispatcher.instance.locale.languageCode == 'en') return true;
  } catch (_) {}
  return Localizations.localeOf(context).languageCode == 'en';
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  bool isLoading = false;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final isEn = _isAuthEn(context);

    if (email.isEmpty || pass.isEmpty || (!isLogin && name.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEn ? 'Please fill all fields' : 'Por favor llena todos los campos')));
      return;
    }

    setState(() => isLoading = true);

    try {
      if (isLogin) {
        await SupabaseService.signIn(email, pass);
      } else {
        final res = await SupabaseService.signUp(email, pass, name);
        if (res.session == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: ExodoColors.amber,
                content: Text(
                  isEn
                      ? '📬 Account created. Check your email for confirmation if required.'
                      : '📬 Cuenta creada. Si Supabase pide confirmación, revisa tu correo. Si no, ya puedes iniciar sesión.',
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                ),
              ),
            );
          }
        }
      }
      
      // Forzar recarga de estado si la sesión quedó activa
      if (SupabaseService.currentUser != null && mounted) {
        await context.read<AppState>().loadUserData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.blur_on, size: 68, color: ExodoColors.amber),
                const SizedBox(height: 12),
                Text('Éxodo by Behavior', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 36),

                // 1. PRIMERA OPCIÓN: Botón oficial de Continuar con Google
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            setState(() => isLoading = true);
                            try {
                              await SupabaseService.signInWithGoogle();
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error Google: $e')));
                              }
                            } finally {
                              if (mounted) setState(() => isLoading = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/google_logo.png',
                          width: 26,
                          height: 26,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          _isAuthEn(context) ? 'Continue with Google' : 'Continuar con Google',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.2),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Separador claro
                Row(
                  children: [
                    Expanded(child: Divider(color: ExodoColors.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(_isAuthEn(context) ? 'or with email' : 'o con correo electrónico', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    Expanded(child: Divider(color: ExodoColors.border)),
                  ],
                ),

                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TabBtn(title: _isAuthEn(context) ? 'Sign In' : 'Iniciar Sesión', active: isLogin, onTap: () => setState(() => isLogin = true)),
                    const SizedBox(width: 16),
                    _TabBtn(title: _isAuthEn(context) ? 'Sign Up' : 'Crear Cuenta', active: !isLogin, onTap: () => setState(() => isLogin = false)),
                  ],
                ),
                const SizedBox(height: 24),

                if (!isLogin) ...[
                  TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: _isAuthEn(context) ? 'Full Name' : 'Nombre Completo', prefixIcon: const Icon(Icons.person_outline))),
                  const SizedBox(height: 16),
                ],
                TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: _isAuthEn(context) ? 'Email' : 'Correo Electrónico', prefixIcon: const Icon(Icons.email_outlined))),
                const SizedBox(height: 16),
                TextField(controller: _passCtrl, obscureText: true, decoration: InputDecoration(labelText: _isAuthEn(context) ? 'Password' : 'Contraseña', prefixIcon: const Icon(Icons.lock_outline))),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ExodoColors.amber,
                      foregroundColor: ExodoColors.background,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: ExodoColors.background)
                        : Text(isLogin ? (_isAuthEn(context) ? 'Sign In with Email' : 'Entrar con Correo') : (_isAuthEn(context) ? 'Sign Up with Email' : 'Registrarse con Correo'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String title;
  final bool active;
  final VoidCallback onTap;

  const _TabBtn({required this.title, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              color: active ? ExodoColors.amber : ExodoColors.textSecondary,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 40,
            height: 2,
            color: active ? ExodoColors.amber : Colors.transparent,
          ),
        ],
      ),
    );
  }
}
