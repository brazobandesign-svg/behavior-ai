import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/supabase_service.dart';
import 'services/app_state.dart';
import 'theme/exodo_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: const ExodoApp(),
    ),
  );
}

class ExodoApp extends StatelessWidget {
  const ExodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Éxodo by Behavior',
      debugShowCheckedModeBanner: false,
      theme: ExodoTheme.darkTheme,
      home: const _RootSwitcher(),
    );
  }
}

class _RootSwitcher extends StatelessWidget {
  const _RootSwitcher();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = SupabaseService.currentUser;

    // 1. Si no ha iniciado sesión -> Pantalla de Autenticación
    if (user == null) {
      return const AuthScreen();
    }

    // 2. Si inició sesión pero no ha elegido perfil profesional (Docente/Abogado/General) -> Onboarding
    if (state.profile?.onboarding == null) {
      return const OnboardingScreen();
    }

    // 3. Todo listo -> Chat Principal
    return const ChatScreen();
  }
}
