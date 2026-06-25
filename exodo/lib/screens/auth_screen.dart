import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/exodo_theme.dart';

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

    if (email.isEmpty || pass.isEmpty || (!isLogin && name.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor llena todos los campos')));
      return;
    }

    setState(() => isLoading = true);

    try {
      if (isLogin) {
        await SupabaseService.signIn(email, pass);
      } else {
        await SupabaseService.signUp(email, pass, name);
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
                const Icon(Icons.blur_on, size: 64, color: ExodoColors.amber),
                const SizedBox(height: 16),
                Text('Éxodo by Behavior', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TabBtn(title: 'Iniciar Sesión', active: isLogin, onTap: () => setState(() => isLogin = true)),
                    const SizedBox(width: 16),
                    _TabBtn(title: 'Crear Cuenta', active: !isLogin, onTap: () => setState(() => isLogin = false)),
                  ],
                ),
                const SizedBox(height: 28),
                if (!isLogin) ...[
                  TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nombre Completo', prefixIcon: Icon(Icons.person_outline))),
                  const SizedBox(height: 16),
                ],
                TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo Electrónico', prefixIcon: Icon(Icons.email_outlined))),
                const SizedBox(height: 16),
                TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña', prefixIcon: Icon(Icons.lock_outline))),
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
                    child: isLoading ? const CircularProgressIndicator(color: ExodoColors.background) : Text(isLogin ? 'Entrar' : 'Registrarse', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 28),
                Text('O continúa con', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                InkWell(
                  onTap: isLoading ? null : () async {
                    setState(() => isLoading = true);
                    try {
                      await SupabaseService.signInWithGoogle();
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error Google Auth: $e')));
                    } finally {
                      if (mounted) setState(() => isLoading = false);
                    }
                  },
                  borderRadius: BorderRadius.circular(25),
                  child: Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: ExodoColors.border),
                      color: ExodoColors.surface,
                    ),
                    child: const Text('G', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: ExodoColors.textPrimary)),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: active ? ExodoColors.amber : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? ExodoColors.amber : ExodoColors.border),
        ),
        child: Text(title, style: TextStyle(color: active ? ExodoColors.background : ExodoColors.textSecondary, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
